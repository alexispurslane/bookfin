import 'package:flutter/foundation.dart';

import 'jellyfin.dart';
import 'model.dart';
import 'shelf.dart';
import 'store.dart';

typedef JellyfinClientFactory = JellyfinClient Function(
  Uri server,
  String deviceId,
);

/// Runs [work] on [input] in another isolate and completes with its result,
/// which comes back without a copy. [compute] is the default.
typedef CatalogHop = Future<R> Function<M, R>(R Function(M) work, M input);

/// What the last request to Jellyfin says about the server.
enum CatalogReach {
  /// No request for this account reached Jellyfin or failed to reach it
  /// since the app started or the account signed in. The library is the
  /// saved one.
  unknown,

  /// The last request reached Jellyfin. The library is the saved one or a
  /// fresh one, and either is fully usable.
  reached,

  /// The last request could not reach Jellyfin: a network error, a timeout
  /// or a server error. Only a later request that reaches Jellyfin ends it,
  /// so it stays while a retry runs.
  unreachable,

  /// Jellyfin no longer accepts the sign-in, so the account is signed out.
  signInExpired,

  /// Jellyfin denies this account access to its book libraries, so the
  /// library is empty. A saved denial survives a restart.
  accessRevoked,
}

/// Where the catalog stands with Jellyfin.
/// - [refreshing]: a sign-in or a refresh talks to Jellyfin now. A restore
///   from storage is not a refresh.
/// - [reach]: what the last request said about Jellyfin.
/// - [message]: the text to show about the last operation, or null.
typedef CatalogStatus = ({
  bool refreshing,
  CatalogReach reach,
  String? message,
});

/// The signed-in account and what it may read: its session, whether access
/// is blocked, its Jellyfin book libraries, and the ids of the selected
/// ones. Two accounts are equal when these values are equal, so a refresh of
/// the same account does not change it.
class CatalogAccount {
  const CatalogAccount({
    this.session,
    this.accessBlocked = false,
    this.libraries = const [],
    this.selected = const {},
  });
  final JellyfinSession? session;
  final bool accessBlocked;
  final List<BookLibrary> libraries;
  final Set<String> selected;

  @override
  bool operator ==(Object other) =>
      other is CatalogAccount &&
      _sameSession(session, other.session) &&
      accessBlocked == other.accessBlocked &&
      listEquals(_names(libraries), _names(other.libraries)) &&
      setEquals(selected, other.selected);

  @override
  int get hashCode => Object.hash(
    session?.scope.key,
    accessBlocked,
    Object.hashAll(_names(libraries)),
    Object.hashAllUnordered(selected),
  );

  static bool _sameSession(JellyfinSession? left, JellyfinSession? right) =>
      identical(left, right) ||
      (left != null &&
          right != null &&
          left.scope.key == right.scope.key &&
          left.token == right.token &&
          left.username == right.username &&
          left.canDownload == right.canDownload);

  static List<String> _names(List<BookLibrary> libraries) => [
    for (final library in libraries) ...[library.id, library.name],
  ];
}

/// What the catalog is doing.
enum _Work { idle, restore, refresh }

/// The catalog state that one isolate hop builds: the cache, the text that
/// saves it, and the library of its books.
typedef _Built = ({CatalogCache cache, String text, CatalogLibrary library});

/// The smallest saved catalog text, in characters, and the fewest entries
/// that the catalog builds in another isolate. A smaller catalog builds on
/// the UI isolate. Measured in AOT on an M-series Mac: a hop costs about
/// 35 µs plus the copy of its input, and a short entry builds in about 5 µs,
/// but an entry with a long description and many chapters takes about
/// 85 µs. So these limits do not mark where a hop starts to pay: that is
/// one or two entries. They are a compromise: widget tests run in fake time,
/// in which a hop never completes, and every test library is below them.
/// A library of real size is far above them.
const _hopText = 16 * 1024;
const _hopEntries = 16;

/// Decodes the saved catalog [saved] and builds its library.
_Built _restoreCatalog(({AccountScope scope, String text}) saved) {
  final cache = CatalogCache.decode(saved.scope, saved.text);
  return (cache: cache, text: saved.text, library: _libraryOf(cache));
}

/// A change to the saved catalog [text] of [scope]: it gets [edits] and
/// [accessBlocked], and keeps its entries.
typedef _Revision = ({
  AccountScope scope,
  String text,
  CatalogEdits edits,
  bool accessBlocked,
});

/// Decodes the saved catalog of [revision], applies the revision, and saves
/// and builds the result. The saved text crosses to the worker as one block
/// copy, so a correction or a denial copies no entries.
_Built _reviseCatalog(_Revision revision) {
  final saved = CatalogCache.decode(revision.scope, revision.text);
  return _saveCatalog(
    CatalogCache(
      scope: saved.scope,
      libraries: saved.libraries,
      selected: saved.selected,
      entries: saved.entries,
      edits: revision.edits,
      completedAt: saved.completedAt,
      accessBlocked: revision.accessBlocked,
    ),
  );
}

/// Adds the content digest to [cache], encodes it and builds its library.
_Built _saveCatalog(CatalogCache cache) {
  final sealed = cache.withContent();
  return (cache: sealed, text: sealed.encode(), library: _libraryOf(sealed));
}

CatalogLibrary _libraryOf(CatalogCache cache) {
  final List<Book> books;
  try {
    books = buildBooks(cache.entries, edits: cache.edits);
  } catch (_) {
    throw const FormatException('The catalog books could not be built.');
  }
  return CatalogLibrary.build(books);
}

/// The one owner of the signed-in account, its saved catalog and its books.
///
/// It notifies through itself for every change, and through three narrow
/// signals for one kind of change each: [libraryNotifier], [accountNotifier]
/// and [statusNotifier]. Each signal holds the state that the last
/// notification read, so it notifies only when its own value changed.
///
/// The widget tickets of the conformance epic move from the broad
/// notification and these members to the signals:
/// - [books] and the top-level [shelf], [search] and [possibleMatches]:
///   [libraryNotifier] and its [CatalogLibrary.shelf],
///   [CatalogLibrary.search], [CatalogLibrary.series],
///   [CatalogLibrary.seriesOf], [CatalogLibrary.book] and
///   [CatalogLibrary.matches].
/// - [session], [accessBlocked], [libraries] and the selection in [cache]:
///   [accountNotifier].
/// - [busy] and [message]: [statusNotifier]. [busy] also covers a restore.
/// [readingOrder] stays: [CatalogLibrary] series are in reading order.
///
/// Invariants, which [checkInvariants] proves:
/// - A signed-out catalog holds no account data.
/// - The cache belongs to the active account, and each cached item belongs
///   to a selected book library.
/// - The saved text is present exactly when the cache is, and it encodes the
///   cache.
/// - Each source belongs to exactly one edition, and a text edition has one
///   source.
/// - The library view matches its books.
/// - While no operation runs, [libraryNotifier] holds the visible library.
class CatalogController extends ChangeNotifier {
  CatalogController({
    required this._credentials,
    required this._store,
    JellyfinClientFactory? clientFactory,
    CatalogHop? hop,
  }) : _clientFactory =
           clientFactory ??
           ((server, deviceId) => JellyfinClient(server, deviceId: deviceId)),
       _hop = hop ?? compute;
  final CredentialStore _credentials;
  final CatalogStore _store;
  final JellyfinClientFactory _clientFactory;
  final CatalogHop _hop;
  JellyfinClient? _active;
  JellyfinSession? _session;
  CatalogCache? _cache;

  /// The text that saves [_cache], or null without a cache. A revision sends
  /// it to the worker instead of the entries.
  String? _text;
  List<BookLibrary> _libraries = [];

  /// The library of [_cache], or the empty library without a cache.
  CatalogLibrary _built = CatalogLibrary.empty;
  _Work _work = _Work.idle;
  bool _verified = false;
  bool _accessBlocked = false;

  /// What the last request said about Jellyfin. Access that is blocked is
  /// [_accessBlocked], so this is never [CatalogReach.accessRevoked].
  CatalogReach _reach = CatalogReach.unknown;
  bool _disposed = false;
  String? _message;
  int _generation = 0;
  int _accountGeneration = 0;
  Future<void>? _credentialWrites;
  Future<void>? _cacheWrites;
  late final _librarySignal = ValueNotifier(_visible);
  late final _accountSignal = ValueNotifier(_account);
  late final _statusSignal = ValueNotifier(_status);

  /// The visible library: the books of the signed-in account, with their
  /// shelves and indexes. It is empty while signed out or while access is
  /// blocked. It notifies only when the books change. A refresh that brings
  /// the same entries and corrections keeps the same library, the same book
  /// objects, and notifies nothing.
  ValueListenable<CatalogLibrary> get libraryNotifier => _librarySignal;

  /// The signed-in account and what it may read.
  ValueListenable<CatalogAccount> get accountNotifier => _accountSignal;

  /// Whether a refresh runs, what the last request said about Jellyfin, and
  /// the message to show. A shelf shows only downloaded books while
  /// [CatalogStatus.reach] is [CatalogReach.unreachable].
  ValueListenable<CatalogStatus> get statusNotifier => _statusSignal;

  JellyfinSession? get session => _session;
  CatalogCache? get cache => _cache;

  /// The visible books. A change replaces the list, so callers can compare
  /// lists by identity to see whether the books changed.
  List<Book> get books => _visible.books;
  List<BookLibrary> get libraries => List.unmodifiable(_libraries);

  /// Whether a restore, a sign-in or a refresh runs.
  bool get busy => _work != _Work.idle;
  bool get verified => _verified;
  bool get accessBlocked => _accessBlocked;
  String? get message => _message;

  CatalogLibrary get _visible =>
      _session == null || _accessBlocked ? CatalogLibrary.empty : _built;

  CatalogAccount get _account => CatalogAccount(
    session: _session,
    accessBlocked: _accessBlocked,
    libraries: _libraries,
    selected: _cache?.selected ?? const {},
  );

  CatalogStatus get _status => (
    refreshing: _work == _Work.refresh,
    reach: _accessBlocked ? CatalogReach.accessRevoked : _reach,
    message: _message,
  );

  void checkInvariants() {
    if (_session == null &&
        (_cache != null ||
            _built.books.isNotEmpty ||
            _libraries.isNotEmpty ||
            _verified)) {
      throw StateError('A signed-out catalog must contain no account data.');
    }
    if (_cache != null && _cache!.scope.key != _session?.scope.key) {
      throw StateError('The cache must belong to the active account.');
    }
    if ((_cache == null) != (_text == null) ||
        (_cache != null &&
            CatalogCache.decode(_cache!.scope, _text!).content !=
                _cache!.content)) {
      throw StateError('The saved text must encode the cache.');
    }
    if (_cache != null &&
        _cache!.entries.any(
          (entry) => !_cache!.selected.contains(entry.libraryId),
        )) {
      throw StateError(
        'Every cached item must belong to a selected book library.',
      );
    }
    final sources = <String>{};
    for (final book in _built.books) {
      for (final edition in book.editions) {
        if (edition.kind == EditionKind.text && edition.files.length != 1) {
          throw StateError('A text edition must have one source.');
        }
        for (final file in edition.files) {
          if (!sources.add(file.key)) {
            throw StateError(
              'Every source must belong to exactly one edition.',
            );
          }
        }
      }
    }
    _built.checkInvariants();
    if (_work == _Work.idle &&
        !_disposed &&
        !identical(_librarySignal.value, _visible)) {
      throw StateError('The library signal must hold the visible library.');
    }
  }

  /// Builds a catalog with [work] in another isolate, or here when [small]
  /// (see [_hopEntries]).
  Future<_Built> _build<M>(
    _Built Function(M) work,
    M input, {
    required bool small,
  }) async => small ? work(input) : _hop(work, input);

  /// Builds [revision] of the saved catalog with [_reviseCatalog], in
  /// another isolate unless the text is small (see [_hopText]).
  Future<_Built> _revise(_Revision revision) =>
      _build(_reviseCatalog, revision, small: revision.text.length < _hopText);

  /// Adopts [built] as the cache. The library changes only when the books
  /// can differ: a cache with the content of the current one has the same
  /// books, so the current library, and its book objects, stay.
  void _adopt(_Built built) {
    assert(_session?.scope.key == built.cache.scope.key);
    final previous = _cache;
    _cache = built.cache;
    _text = built.text;
    _accessBlocked = built.cache.accessBlocked;
    if (previous == null ||
        built.cache.content == null ||
        built.cache.content != previous.content) {
      _built = built.library;
    }
  }

  int _begin({_Work work = _Work.refresh}) {
    _active?.close();
    _active = null;
    _work = work;
    _verified = false;
    _message = null;
    return ++_generation;
  }

  bool _current(int generation) => !_disposed && generation == _generation;

  /// Publishes the state to the narrow signals, then notifies the broad
  /// listeners. A signal whose value did not change does not notify.
  void _notify() {
    if (_disposed) return;
    _librarySignal.value = _visible;
    _accountSignal.value = _account;
    _statusSignal.value = _status;
    notifyListeners();
  }

  Future<void> _writeCredentials(JellyfinSession? value) {
    final next = (_credentialWrites ?? Future<void>.value()).then(
      (_) => _credentials.write(value),
    );
    _credentialWrites = next.catchError((Object _) {});
    return next;
  }

  void _clearVisible() {
    ++_accountGeneration;
    _session = null;
    _cache = null;
    _text = null;
    _built = CatalogLibrary.empty;
    _libraries = [];
    _verified = false;
    _accessBlocked = false;
    _reach = CatalogReach.unknown;
  }

  /// The saved catalog of [scope], decoded and built, or null when none is
  /// saved.
  Future<_Built?> _readSaved(AccountScope scope) async {
    final text = await _store.read(scope);
    if (text == null) return null;
    return _build(_restoreCatalog, (
      scope: scope,
      text: text,
    ), small: text.length < _hopText);
  }

  Future<void> restore() async {
    final generation = _begin(work: _Work.restore);
    _clearVisible();
    _notify();
    try {
      await _credentialWrites;
      final restored = await _credentials.read();
      if (!_current(generation)) return;
      if (restored != null) {
        _session = restored;
        final saved = await _readSaved(restored.scope);
        if (!_current(generation)) return;
        if (saved != null) {
          _adopt(saved);
          _libraries = saved.cache.libraries;
        }
      }
    } catch (_) {
      if (_current(generation)) {
        _message =
            'Saved account data could not be read. Sign in again if needed.';
      }
    } finally {
      if (_current(generation)) {
        _work = _Work.idle;
        _notify();
      }
    }
  }

  Future<void> connect(String server, String username, String password) async {
    final generation = _begin();
    _clearVisible();
    _notify();
    try {
      await _writeCredentials(null);
      final address = parseServer(server);
      final device = await _credentials.deviceId();
      if (!_current(generation)) return;
      final client = _clientFactory(address, device);
      _active = client;
      final signedIn = await client.signIn(username.trim(), password);
      if (!_current(generation)) return;
      _reach = CatalogReach.reached;
      if (signedIn.scope.server != address) {
        throw const CatalogFailure(CatalogFailureKind.unauthorized);
      }
      await _writeCredentials(signedIn);
      if (!_current(generation)) return;
      _session = signedIn;
      _Built? saved;
      try {
        saved = await _readSaved(signedIn.scope);
      } catch (_) {
        if (_current(generation)) {
          _message =
              'Saved books could not be read. Refresh your book libraries.';
        }
      }
      if (!_current(generation)) return;
      if (saved != null) _adopt(saved);
      final views = await client.libraries(signedIn);
      if (!_current(generation)) return;
      _libraries = views;
      if (_cache != null &&
          !views
              .map((library) => library.id)
              .toSet()
              .containsAll(_cache!.selected)) {
        throw const CatalogFailure(CatalogFailureKind.invalidSelection);
      }
      _verified = true;
    } catch (error) {
      if (_current(generation)) {
        if (error is CatalogFailure) {
          await _failure(error, generation);
        } else {
          _clearVisible();
          _message = 'The account could not be saved in secure storage. Sign in again.';
        }
      }
    } finally {
      if (_current(generation)) {
        _work = _Work.idle;
        _active?.close();
        _active = null;
        _notify();
      }
    }
  }

  Future<void> refresh({Set<String>? selected}) async {
    final currentSession = _session;
    if (currentSession == null) return;
    final generation = _begin();
    _notify();
    try {
      final device = await _credentials.deviceId();
      if (!_current(generation)) return;
      final client = _clientFactory(currentSession.scope.server, device);
      _active = client;
      final validated = await client.validate(currentSession);
      if (!_current(generation)) return;
      _reach = CatalogReach.reached;
      final views = await client.libraries(validated);
      if (!_current(generation)) return;
      _libraries = views;
      final selection = Set<String>.from(
        selected ?? _cache?.selected ?? const <String>{},
      );
      if (!views.map((library) => library.id).toSet().containsAll(selection)) {
        throw const CatalogFailure(CatalogFailureKind.invalidSelection);
      }
      final entries = selection.isEmpty
          ? <CatalogEntry>[]
          : await client.catalog(validated, selection);
      if (!_current(generation)) return;
      final write = (_cacheWrites ?? Future<void>.value()).then((_) async {
        if (!_current(generation)) return;
        final built = await _build(
          _saveCatalog,
          CatalogCache(
            scope: validated.scope,
            libraries: views,
            selected: selection,
            entries: entries,
            edits: _cache?.edits,
            completedAt: DateTime.now().toUtc(),
          ),
          small: entries.length < _hopEntries,
        );
        if (!_current(generation)) return;
        await _store.write(validated.scope, built.text);
        if (!_current(generation)) return;
        _session = validated;
        _adopt(built);
        _verified = true;
      });
      _cacheWrites = write.catchError((Object _) {});
      await write;
    } catch (error) {
      if (_current(generation)) {
        if (error is CatalogFailure) {
          await _failure(error, generation);
        } else {
          _message = 'The refreshed catalog was not saved. Your previous saved books are unchanged.';
        }
      }
    } finally {
      if (_current(generation)) {
        _work = _Work.idle;
        _active?.close();
        _active = null;
        _notify();
      }
    }
  }

  Future<void> _failure(CatalogFailure failure, int generation) async {
    _verified = false;
    _message = failure.message;
    _reach = switch (failure.kind) {
      CatalogFailureKind.unavailable => CatalogReach.unreachable,
      // The request did not reach Jellyfin, so it says nothing new.
      CatalogFailureKind.cancelled ||
      CatalogFailureKind.invalidServer => _reach,
      // Jellyfin answered. An expired sign-in is set below, with sign-out.
      _ => CatalogReach.reached,
    };
    if (failure.kind == CatalogFailureKind.unauthorized) {
      _clearVisible();
      _reach = CatalogReach.signInExpired;
      try {
        await _writeCredentials(null);
      } catch (_) {
        if (_current(generation)) _message = 'Secure sign-out could not be saved. Retry sign-out before leaving this device.';
      }
    } else if (failure.kind == CatalogFailureKind.forbidden ||
        failure.kind == CatalogFailureKind.invalidSelection) {
      _accessBlocked = true;
      final scope = _session?.scope;
      if (scope == null) return;
      final write = (_cacheWrites ?? Future<void>.value()).then((_) async {
        if (!_current(generation)) return;
        final previous = _cache;
        final denied = previous == null
            ? _saveCatalog(
                CatalogCache(
                  scope: scope,
                  libraries: _libraries,
                  accessBlocked: true,
                ),
              )
            : await _revise((
                scope: scope,
                text: _text!,
                edits: previous.edits,
                accessBlocked: true,
              ));
        if (!_current(generation)) return;
        await _store.write(scope, denied.text);
        if (_current(generation)) _adopt(denied);
      });
      _cacheWrites = write.catchError((Object _) {});
      try {
        await write;
      } catch (_) {
        // Without a saved denial, prevent automatic restoration of this account.
        await _writeCredentials(null);
        if (_current(generation)) {
          _message = 'Access is blocked and the saved account was signed out. Sign in again to resolve access.';
        }
      }
    }
  }

  Future<void> signOut() async {
    _begin();
    _clearVisible();
    _work = _Work.idle;
    _notify();
    final generation = _generation;
    try {
      await _writeCredentials(null);
    } catch (_) {
      if (_current(generation)) {
        _message = 'Secure sign-out could not be saved. Retry sign-out before leaving this device.';
        _notify();
      }
    }
  }

  void cancel() {
    _active?.close();
    _active = null;
    ++_generation;
    _work = _Work.idle;
    _verified = false;
    _message = 'Refresh cancelled.';
    _notify();
  }

  Book _book(String id) =>
      _visible.book(id) ??
      (throw ArgumentError.value(
        id,
        'bookId',
        'Book is not in the active catalog.',
      ));

  Future<void> _edit(CatalogEdits Function(CatalogEdits) change) {
    if (_session == null || _cache == null || _accessBlocked) {
      throw StateError('Sign in and load a book catalog before correcting it.');
    }
    final accountGeneration = _accountGeneration;
    bool currentAccount() =>
        !_disposed && accountGeneration == _accountGeneration;
    final write = (_cacheWrites ?? Future<void>.value()).then((_) async {
      if (!currentAccount()) return;
      final previous = _cache!;
      try {
        final built = await _revise((
          scope: previous.scope,
          text: _text!,
          edits: change(previous.edits),
          accessBlocked: false,
        ));
        if (!currentAccount()) return;
        await _store.write(previous.scope, built.text);
        if (!currentAccount()) return;
        _adopt(built);
        _message = null;
        _notify();
      } catch (_) {
        if (currentAccount()) {
          _message = 'Your correction was not saved. Try again.';
          _notify();
        }
      }
    });
    _cacheWrites = write.catchError((Object _) {});
    return write;
  }

  Future<void> linkBooks(String sourceBookId, String targetBookId) {
    final source = _book(sourceBookId);
    final target = _book(targetBookId);
    if (sourceBookId == targetBookId) {
      throw ArgumentError('Choose a different book.');
    }
    return _edit(
      (edits) => CatalogEdits(
        bookLinks: {
          ...edits.bookLinks.map(
            (key, value) =>
                MapEntry(key, value == sourceBookId ? targetBookId : value),
          ),
          for (final edition in source.editions)
            for (final member in edition.memberIds) member: targetBookId,
        },
        recordingLinks: edits.recordingLinks,
        details: {
          ...edits.details,
          targetBookId: BookDetails(
            title: target.title,
            author: target.author,
            series: target.series,
            seriesOrder: target.seriesOrder,
          ),
        },
        fileOrders: edits.fileOrders,
      ),
    );
  }

  Future<void> combineAudio(String bookId, List<String> editionIds) {
    final book = _book(bookId);
    final editions = [
      for (final id in editionIds)
        book.editions.firstWhere(
          (edition) => edition.id == id,
          orElse: () => throw ArgumentError('Edition is not in this book.'),
        ),
    ];
    if (editions.length < 2 ||
        editions.any((edition) => edition.kind != EditionKind.audio) ||
        editions
                .expand((edition) => edition.files)
                .map((file) => file.itemId)
                .toSet()
                .length !=
            editions.expand((edition) => edition.files).length) {
      throw ArgumentError(
        'Choose at least two audio editions with different source items.',
      );
    }
    final target = editions.first.id;
    return _edit(
      (edits) => CatalogEdits(
        bookLinks: edits.bookLinks,
        recordingLinks: {
          ...edits.recordingLinks,
          for (final edition in editions)
            for (final member in edition.memberIds) member: target,
        },
        details: edits.details,
        fileOrders: edits.fileOrders,
      ),
    );
  }

  Future<void> separateEdition(String editionId) {
    final edition = books
        .expand((book) => book.editions)
        .firstWhere(
          (edition) => edition.memberIds.contains(editionId),
          orElse: () => throw ArgumentError(
            'Source edition is not in the active catalog.',
          ),
        );
    return _edit((edits) {
      final links = Map<String, String>.from(edits.recordingLinks)
        ..remove(editionId);
      final remaining = edition.memberIds
          .where((id) => id != editionId)
          .toList();
      if (remaining.isNotEmpty) {
        for (final member in remaining) {
          links[member] = remaining.first;
        }
      }
      final orders = Map<String, List<String>>.from(edits.fileOrders);
      if (remaining.isNotEmpty && orders.containsKey(edition.id)) {
        orders[remaining.first] = orders[edition.id]!
            .where((key) => key != editionId)
            .toList();
      }
      return CatalogEdits(
        bookLinks: {...edits.bookLinks, editionId: 'book:edition:$editionId'},
        recordingLinks: links,
        details: edits.details,
        fileOrders: orders,
      );
    });
  }

  Future<void> correctBook(String bookId, BookDetails details) {
    _book(bookId);
    if (details.title.trim().isEmpty ||
        (details.seriesOrder != null &&
            (!details.seriesOrder!.isFinite ||
                details.series == null ||
                details.series!.trim().isEmpty))) {
      throw ArgumentError(
        'Enter a title and a series name for a finite series order.',
      );
    }
    return _edit(
      (edits) => CatalogEdits(
        bookLinks: edits.bookLinks,
        recordingLinks: edits.recordingLinks,
        details: {...edits.details, bookId: details},
        fileOrders: edits.fileOrders,
      ),
    );
  }

  Future<void> orderFiles(String editionId, List<String> sourceKeys) {
    final edition = books
        .expand((book) => book.editions)
        .firstWhere(
          (edition) => edition.id == editionId,
          orElse: () =>
              throw ArgumentError('Edition is not in the active catalog.'),
        );
    if (sourceKeys.length != edition.files.length ||
        sourceKeys.toSet().length != sourceKeys.length ||
        !sourceKeys.toSet().containsAll(
          edition.files.map((file) => file.key),
        )) {
      throw ArgumentError('File order must include every file exactly once.');
    }
    return _edit(
      (edits) => CatalogEdits(
        bookLinks: edits.bookLinks,
        recordingLinks: edits.recordingLinks,
        details: edits.details,
        fileOrders: {
          ...edits.fileOrders,
          editionId: List.unmodifiable(sourceKeys),
        },
      ),
    );
  }

  Future<void> resetCorrections() => _edit((_) => CatalogEdits());

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _active?.close();
    _librarySignal.dispose();
    _accountSignal.dispose();
    _statusSignal.dispose();
    super.dispose();
  }
}
