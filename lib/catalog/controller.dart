import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../foundation/hop.dart';
import 'jellyfin.dart';
import 'model.dart';
import 'shelf.dart';
import 'store.dart';

typedef JellyfinClientFactory = JellyfinClient Function(
  Uri server,
  String deviceId,
);

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

  /// Jellyfin rejected the credential. The local account stays usable.
  signInExpired,

  /// Jellyfin denies this account access to its book libraries, so the
  /// library is empty. A saved denial survives a restart.
  accessRevoked,
}

/// Where the catalog stands with Jellyfin.
/// - [refreshing]: a sign-in or a refresh talks to Jellyfin now. A restore
///   from storage is not a refresh.
/// - [reach]: what the last request said about Jellyfin.
/// - [message]: the text to show about the last operation, or null. A
///   signed-in catalog that cannot reach Jellyfin sets none, because [reach]
///   says it, and the shelf and the status line show it from there.
/// - [verified]: the last sign-in or refresh succeeded. A new one, a
///   cancel, a failure or a sign-out clears it, and a correction keeps it.
///   It is its own field, because a refresh can reach Jellyfin and still
///   fail: Jellyfin sends an incomplete catalog, or the catalog cannot be
///   saved.
typedef CatalogStatus = ({
  bool refreshing,
  CatalogReach reach,
  String? message,
  bool verified,
});

/// The local account and what it may read: its retained session, whether access
/// is blocked, its Jellyfin book libraries, and the ids of the ones that the
/// user hid. Every other book library shows. Two accounts are equal when
/// these values are equal, so a refresh of the same account does not change
/// it.
///
/// [restoring] says that a restore from storage runs, so the account is not
/// fully known yet. Without a [session], the saved credentials are still
/// being read, so the person may be signed in. With one, the saved catalog
/// is still being read, so the libraries, the hidden ones and the blocked
/// access are not known yet.
class CatalogAccount {
  const CatalogAccount({
    this.session,
    this.accessBlocked = false,
    this.needsSignIn = false,
    this.libraries = const [],
    this.hidden = const {},
    this.restoring = false,
  });
  final JellyfinSession? session;
  final bool restoring;
  final bool accessBlocked;

  /// Snapshot of credential rejection for this narrow account signal.
  final bool needsSignIn;
  final List<BookLibrary> libraries;
  final Set<String> hidden;

  @override
  bool operator ==(Object other) =>
      other is CatalogAccount &&
      _sameSession(session, other.session) &&
      restoring == other.restoring &&
      accessBlocked == other.accessBlocked &&
      needsSignIn == other.needsSignIn &&
      listEquals(_libraryNames(libraries), _libraryNames(other.libraries)) &&
      setEquals(hidden, other.hidden);

  @override
  int get hashCode => Object.hash(
    session?.scope.key,
    session?.credentialIdentity,
    restoring,
    accessBlocked,
    needsSignIn,
    Object.hashAll(_libraryNames(libraries)),
    Object.hashAllUnordered(hidden),
  );

  static bool _sameSession(JellyfinSession? left, JellyfinSession? right) =>
      identical(left, right) ||
      (left != null &&
          right != null &&
          left.scope.key == right.scope.key &&
          left.credentialIdentity == right.credentialIdentity &&
          left.username == right.username &&
          left.canDownload == right.canDownload);
}

List<String> _libraryNames(List<BookLibrary> libraries) => [
  for (final library in libraries) ...[library.id, library.name],
];

/// What the catalog is doing.
enum _Work { idle, restore, signIn, refresh }

/// A refresh that runs: its [generation], the [hidden] libraries that it
/// was asked to save, or null to keep the saved ones, when it is [done],
/// and whether a caller asked for its outcome. A refresh asked for while it
/// runs joins it, so [reported] can turn true while it runs.
class _Refreshing {
  _Refreshing(
    this.generation,
    this.hidden, {
    required this.reported,
    required this.verifiedBefore,
  });
  final bool verifiedBefore;
  final int generation;
  final Set<String>? hidden;
  bool reported;
  late final Future<void> done;
}

/// The catalog state that one isolate hop builds: the cache, the text that
/// saves it, and the library of its books. A null library reuses the current
/// books, whose content digest must match.
typedef _Built = ({CatalogCache cache, String text, CatalogLibrary? library});

/// Account identity captured before asynchronous work starts. A request-bound
/// operation also expires on cancellation; corrections and notice reconciliation
/// belong to the account and may finish while a newer refresh runs.
typedef _AccountOperation = ({AccountScope scope, int account, int? request});

/// The smallest saved catalog text, in characters, and the fewest entries
/// that the catalog builds in another isolate. A smaller catalog builds on
/// the UI isolate. A refresh counts the items that Jellyfin's pages hold,
/// because their body size depends on Jellyfin's fields. Measured in AOT on
/// an M-series Mac, as time on the calling isolate: a hop costs about 15 µs,
/// an empty catalog (about 370 characters) builds in 7 to 14 µs, and a
/// catalog of one short entry (about 740 characters) in 19 to 36 µs. So a
/// hop pays from the first entry, and only an empty catalog builds here.
const _hopText = 512;
const _hopEntries = 1;

/// Decodes the saved catalog [saved] and builds its library.
_Built _restoreCatalog(
  ({AccountScope scope, String text, CatalogChoices choices}) saved,
) {
  final cache = CatalogCache.decode(saved.scope, saved.text);
  return (
    cache: cache,
    text: saved.text,
    library: _libraryOf(cache.entries, saved.choices),
  );
}

/// A change to the saved catalog [text] of [scope]: it keeps [choices] and
/// [accessBlocked], and keeps its entries.
typedef _Revision = ({
  AccountScope scope,
  String text,
  CatalogChoices choices,
  bool accessBlocked,
});

/// Decodes the saved catalog of [revision], applies the revision, and saves
/// and builds the result. The saved text crosses to the worker as one block
/// copy, so an access change copies no entries.
_Built _reviseCatalog(_Revision revision) {
  final saved = CatalogCache.decode(revision.scope, revision.text);
  return _saveCatalog(
    CatalogCache(
      scope: saved.scope,
      libraries: saved.libraries,
      entries: saved.entries,
      included: saved.included,
      completedAt: saved.completedAt,
      accessBlocked: revision.accessBlocked,
    ),
    revision.choices,
  );
}

/// A refresh's answer from Jellyfin for [scope]: its book [libraries], the
/// [hidden] ones, and the catalog [pages] of the others, not yet decoded.
/// The catalog applies [choices]. If its digest matches [previousContent], the
/// books need no build. [canKeepSavedCatalog] also requires unchanged account
/// metadata and storage known to hold the current cache.
typedef _Refresh = ({
  AccountScope scope,
  List<BookLibrary> libraries,
  Set<String> hidden,
  CatalogPages pages,
  CatalogChoices choices,
  Set<String> previousHidden,
  Set<String> previousIncluded,
  String? previousText,
  DateTime completedAt,
  String? previousContent,
  bool canKeepSavedCatalog,
});

/// Decodes and checks the pages of [refresh], builds its entries, and saves
/// and builds only changed content. An unchanged catalog that can keep its
/// saved snapshot returns null: there is nothing to adopt or write. The pages
/// cross to the worker as block copies, so a refresh copies no entries.
/// Throws a [CatalogFailure] when the pages are not one complete catalog.
_Built? _refreshCatalog(_Refresh refresh) {
  final entries = catalogEntries(refresh.pages);
  final included = refresh.libraries.map((library) => library.id).toSet()
    ..removeAll(refresh.hidden);
  // Retain known hidden entries. Hiding a library changes only choices; its
  // server data remains disposable and can be refreshed when shown again.
  if (refresh.hidden.isNotEmpty && refresh.previousText != null) {
    final previous = CatalogCache.decode(refresh.scope, refresh.previousText!);
    final libraries = refresh.libraries.map((library) => library.id).toSet();
    included.addAll(
      previous.included.where(
        (id) => refresh.hidden.contains(id) && libraries.contains(id),
      ),
    );
    entries.addAll(
      previous.entries.where(
        (entry) =>
            refresh.hidden.contains(entry.libraryId) &&
            libraries.contains(entry.libraryId),
      ),
    );
  }
  final cache = CatalogCache(
    scope: refresh.scope,
    libraries: refresh.libraries,
    entries: entries,
    included: included,
    completedAt: refresh.completedAt,
  ).withContent();
  final unchanged = cache.content == refresh.previousContent;
  final visibilityChanged = entries.any(
    (entry) =>
        refresh.previousHidden.contains(entry.libraryId) !=
        refresh.hidden.contains(entry.libraryId),
  );
  final keep =
      unchanged &&
      refresh.canKeepSavedCatalog &&
      setEquals(included, refresh.previousIncluded);
  if (keep && !visibilityChanged) return null;
  return (
    cache: keep
        ? CatalogCache.decode(refresh.scope, refresh.previousText!)
        : cache,
    text: keep ? refresh.previousText! : cache.encode(),
    library: unchanged && !visibilityChanged
        ? null
        : _libraryOf(entries, refresh.choices),
  );
}

_Built _saveCatalog(CatalogCache cache, CatalogChoices choices) {
  final sealed = cache.withContent();
  return (
    cache: sealed,
    text: sealed.encode(),
    library: _libraryOf(sealed.entries, choices),
  );
}

CatalogLibrary _libraryOf(List<CatalogEntry> entries, CatalogChoices choices) {
  final List<Book> books;
  try {
    books = buildBooks([
      for (final entry in entries)
        if (!choices.hidden.contains(entry.libraryId)) entry,
    ], edits: choices.edits);
  } on Exception {
    throw const FormatException('The catalog books could not be built.');
  } on TypeError {
    throw const FormatException('The catalog books could not be built.');
  }
  return CatalogLibrary.build(books);
}

CatalogLibrary _correctCatalog(
  ({List<CatalogEntry> entries, CatalogChoices choices}) input,
) => _libraryOf(input.entries, input.choices);

CatalogLibrary? _changeVisibility(
  ({
    List<CatalogEntry> entries,
    CatalogChoices choices,
    Set<String> previousHidden,
  })
  input,
) =>
    input.entries.any(
      (entry) =>
          input.choices.hidden.contains(entry.libraryId) !=
          input.previousHidden.contains(entry.libraryId),
    )
    ? _libraryOf(input.entries, input.choices)
    : null;

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
/// - [session], [accessBlocked], [libraries] and the hidden libraries in
///   the account: [accountNotifier].
/// - [busy], [verified] and [message]: [statusNotifier]. [busy] also
///   covers a restore.
/// [readingOrder] stays: [CatalogLibrary] series are in reading order.
///
/// Invariants, which [checkInvariants] proves:
/// - A signed-out catalog holds no account data.
/// - A verified catalog reached Jellyfin, and its access is not blocked.
///   So the status never says [CatalogReach.accessRevoked] and verified.
/// - The cache belongs to the active account, and each cached item belongs
///   to a completely fetched book library. Choices filter the visible books.
/// - A restored cache has choices, and known saved choices require a value.
/// - The saved text is present exactly when the cache is, and it encodes the
///   cache.
/// - Known saved content requires a cache. A signed-out catalog retains no
///   successful refresh time from its former account.
/// - Each source belongs to exactly one edition, and a text edition has one
///   source.
/// - The library view matches its books, built from the current cache and choices.
/// - While no operation runs, [libraryNotifier] holds the visible library.
class CatalogController extends ChangeNotifier {
  CatalogController({
    required this._credentials,
    required this._store,
    JellyfinClientFactory? clientFactory,
    IsolateHop? hop,
  }) : _clientFactory =
           clientFactory ??
           ((server, deviceId) => JellyfinClient(server, deviceId: deviceId)),
       _hop = hop ?? compute;
  final CredentialStore _credentials;
  final CatalogStore _store;
  final JellyfinClientFactory _clientFactory;
  final IsolateHop _hop;
  JellyfinClient? _active;
  JellyfinSession? _session;
  CatalogCache? _cache;
  CatalogChoices? _choices;
  bool _choicesStored = false;

  /// The text that saves [_cache], or null without a cache. A revision sends
  /// it to the worker instead of the entries.
  String? _text;

  /// Whether storage is known to hold [_text]. A cancelled write can still
  /// finish, and a failed write can leave its outcome unknown. The next
  /// refresh must save again in either case, even if its content is unchanged.
  bool _cacheStored = false;

  /// The latest successful refresh in this account session, including an
  /// unchanged response. Until then, the saved snapshot's completedAt is
  /// the last known success. Corrections never move this time. Launch always
  /// refreshes, so unchanged successes need no separate persistent metadata.
  DateTime? _lastSuccessfulRefresh;
  List<BookLibrary> _libraries = [];

  /// The library built from [_cache] and [_choices], or empty without a cache.
  CatalogLibrary _built = CatalogLibrary.empty;
  _Work _work = _Work.idle;

  /// The last restore, which runs while [_work] is [_Work.restore].
  Future<void>? _restoring;

  /// The last refresh, which runs while its generation is current and
  /// [_work] is [_Work.refresh].
  _Refreshing? _refreshing;
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
  String? get message => _message ?? _choices?.notice;

  CatalogLibrary get _visible =>
      _session == null || _accessBlocked ? CatalogLibrary.empty : _built;

  CatalogAccount get _account => CatalogAccount(
    session: _session,
    restoring: _work == _Work.restore,
    accessBlocked: _accessBlocked,
    needsSignIn: _session?.needsSignIn ?? false,
    libraries: _libraries,
    hidden: _choices?.hidden ?? const {},
  );

  CatalogStatus get _status => (
    refreshing: _work == _Work.refresh || _work == _Work.signIn,
    reach: _accessBlocked
        ? CatalogReach.accessRevoked
        : _session?.needsSignIn == true
        ? CatalogReach.signInExpired
        : _reach,
    message: _message ?? _choices?.notice,
    verified: _verified,
  );

  void checkInvariants() {
    if (_session == null &&
        (_cache != null ||
            _choices != null ||
            _built.books.isNotEmpty ||
            _libraries.isNotEmpty ||
            _lastSuccessfulRefresh != null ||
            _verified)) {
      throw StateError('A signed-out catalog must contain no account data.');
    }
    final status = _status;
    if (status.verified && status.reach != CatalogReach.reached) {
      throw StateError(
        'A verified catalog must have reached Jellyfin with access.',
      );
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
    if ((_choicesStored && _choices == null) ||
        (_cache != null && _choices == null)) {
      throw StateError('A restored cache must have account choices.');
    }
    if (_cacheStored && _cache == null) {
      throw StateError('Known saved content must have a cache.');
    }
    if (_cache case final cache?) {
      final known = cache.libraries.map((library) => library.id).toSet();
      if (!known.containsAll(cache.included) ||
          cache.entries.any(
            (entry) => !cache.included.contains(entry.libraryId),
          )) {
        throw StateError(
          'Every cached item must belong to a completely fetched book library.',
        );
      }
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
    if (_cache != null && _choices != null) {
      // This full derivation runs only in the on-demand checker. Compare the
      // fields that choices can change, including grouping and file order.
      String chosenBooks(List<Book> books) => jsonEncode([
        for (final book in books)
          [
            book.id,
            book.title,
            book.author,
            book.series,
            book.seriesOrder,
            for (final edition in book.editions)
              [
                edition.id,
                edition.memberIds,
                for (final file in edition.files) file.key,
              ],
          ],
      ]);
      if (chosenBooks(_built.books) !=
          chosenBooks(_libraryOf(_cache!.entries, _choices!).books)) {
        throw StateError(
          'The library must be built from the current choices and cache.',
        );
      }
    }
    if (_work == _Work.idle &&
        !_disposed &&
        !identical(_librarySignal.value, _visible)) {
      throw StateError('The library signal must hold the visible library.');
    }
  }

  /// Builds a catalog with [work] in another isolate, or here when [small]
  /// (see [_hopEntries]).
  Future<R> _build<M, R>(
    R Function(M) work,
    M input, {
    required bool small,
  }) async => small ? work(input) : _hop(work, input);

  /// Builds [revision] of the saved catalog with [_reviseCatalog], in
  /// another isolate unless the text is small (see [_hopText]).
  Future<_Built> _revise(_Revision revision) =>
      _build(_reviseCatalog, revision, small: revision.text.length < _hopText);

  /// Adopts the prepared server snapshot and its derived library. A null
  /// library preserves the current books; the worker has checked that both
  /// server content and applied visibility permit that reuse.
  void _adopt(_AccountOperation operation, _Built built) {
    if (!_owns(operation)) return;
    assert(_session?.scope.key == built.cache.scope.key);
    _cache = built.cache;
    _text = built.text;
    _cacheStored = true;
    _accessBlocked = built.cache.accessBlocked;
    if (built.library case final library?) _built = library;
  }

  _AccountOperation _operation({int? request}) =>
      (scope: _session!.scope, account: _accountGeneration, request: request);

  bool _owns(_AccountOperation operation) =>
      !_disposed &&
      operation.account == _accountGeneration &&
      operation.scope.key == _session?.scope.key &&
      (operation.request == null || operation.request == _generation);

  /// Installs choices and their derived view together, only for the account
  /// and request that started the work. A supplied library was prepared from
  /// the current cache; otherwise this owner rebuilds changed choices itself.
  /// Notice-only reconciliation preserves the existing storage certainty.
  Future<void> _adoptChoices(
    _AccountOperation operation,
    CatalogChoices choices, {
    CatalogLibrary? library,
    bool stored = true,
  }) async {
    if (!_owns(operation)) return;
    final cache = _cache;
    assert(cache == null || cache.scope.key == operation.scope.key);
    if (library == null && cache != null) {
      if (!identical(choices.edits, _choices?.edits)) {
        library = await _build(_correctCatalog, (
          entries: cache.entries,
          choices: choices,
        ), small: cache.entries.isEmpty);
      } else if (!setEquals(choices.hidden, _choices?.hidden)) {
        library = await _build(_changeVisibility, (
          entries: cache.entries,
          choices: choices,
          previousHidden: _choices!.hidden,
        ), small: cache.entries.isEmpty);
      }
    }
    if (!_owns(operation)) return;
    _choices = choices;
    _choicesStored = stored;
    if (library != null) _built = library;
  }

  /// Reconciles storage's recovery notice after background migration. It joins
  /// account writes, so a notice cannot replace newer corrections or books.
  /// Only the small choice record is read; the server catalog is untouched.
  Future<void> reconcileChoices() {
    if (_session == null || _disposed) return Future<void>.value();
    final operation = _operation();
    final next = (_cacheWrites ?? Future<void>.value()).then((_) async {
      await _reconcileChoiceNotice(operation);
      if (_owns(operation)) _notify();
    });
    _cacheWrites = next.catchError((Object _) {});
    return next;
  }

  Future<void> _reconcileChoiceNotice(_AccountOperation operation) async {
    if (!_owns(operation)) return;
    final saved = await _store.readChoices(operation.scope);
    if (!_owns(operation)) return;
    final current = _choices;
    if (current == null) {
      await _adoptChoices(operation, saved);
    } else if (saved.retainedUnreadable && !current.retainedUnreadable) {
      await _adoptChoices(
        operation,
        CatalogChoices(
          edits: current.edits,
          hidden: current.hidden,
          retainedUnreadable: true,
        ),
        stored: _choicesStored,
      );
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

  /// Serializes storage and adoption together. Later credential changes
  /// see the account that a successful replacement made authoritative.
  Future<void> _changeCredentials(Future<void> Function() change) {
    final next = (_credentialWrites ?? Future<void>.value()).then(
      (_) => change(),
    );
    _credentialWrites = next.catchError((Object _) {});
    return next;
  }

  Future<void> _writeCredentials(JellyfinSession? value) =>
      _changeCredentials(() => _credentials.write(value));

  /// Writes catalog text and records whether storage still matches the
  /// active cache, even if the operation that requested the write ended.
  /// Callers serialize these writes through [_cacheWrites].
  Future<void> _writeCatalog(AccountScope scope, String text) async {
    final operation = _operation();
    assert(operation.scope.key == scope.key);
    try {
      await _store.write(scope, text);
      await _reconcileChoiceNotice(operation);
      if (_owns(operation)) {
        _cacheStored = identical(text, _text);
      }
    } on AssertionError {
      rethrow;
    } catch (_) {
      if (_owns(operation)) _cacheStored = false;
      rethrow;
    }
  }

  Future<void> _writeChoices(AccountScope scope, CatalogChoices choices) async {
    final operation = _operation();
    assert(operation.scope.key == scope.key);
    try {
      await _store.writeChoices(scope, choices);
      if (_owns(operation)) {
        _choicesStored = identical(choices, _choices);
      }
    } on AssertionError {
      rethrow;
    } catch (_) {
      if (_owns(operation)) _choicesStored = false;
      rethrow;
    }
  }

  /// Changes the local account's credential subscription. An obsolete
  /// credential can still be rejected, but it cannot change this account.
  void _setSession(JellyfinSession? session) {
    _session?.credentialChanges.removeListener(_credentialRejected);
    _session = session;
    session?.credentialChanges.addListener(_credentialRejected);
  }

  void _credentialRejected() {
    final session = _session;
    if (_disposed || session == null || !session.needsSignIn) return;
    // Retire a refresh that uses this credential. Local restoration and
    // authentication of a replacement credential must finish independently.
    final generation = _work == _Work.refresh
        ? _begin(work: _Work.idle)
        : _generation;
    _verified = false;
    _reach = CatalogReach.signInExpired;
    _message = const CatalogFailure(CatalogFailureKind.unauthorized).message;
    _notify();
    unawaited(
      _changeCredentials(() async {
        if (_session?.credentialIdentity != session.credentialIdentity) return;
        await _credentials.write(session);
      }).catchError((Object error) {
        if (_current(generation)) {
          _message = 'Sign in again. The expired sign-in could not be saved on this device.';
          _notify();
        }
      }, test: (error) => error is! AssertionError),
    );
  }

  void _clearVisible() {
    ++_accountGeneration;
    _setSession(null);
    _cache = null;
    _choices = null;
    _choicesStored = false;
    _text = null;
    _cacheStored = false;
    _lastSuccessfulRefresh = null;
    _built = CatalogLibrary.empty;
    _libraries = [];
    _verified = false;
    _accessBlocked = false;
    _reach = CatalogReach.unknown;
  }

  /// The saved catalog of [operation], decoded and built, or null when none is
  /// saved. Choices load independently even when the server cache is absent.
  Future<_Built?> _readSaved(_AccountOperation operation) async {
    // An earlier account operation can still be finishing its disk write.
    await _cacheWrites;
    if (!_owns(operation)) return null;
    final scope = operation.scope;
    final choices = await _store.readChoices(scope);
    await _adoptChoices(operation, choices);
    if (!_owns(operation)) return null;
    final text = await _store.read(scope);
    if (text == null) return null;
    return _build(_restoreCatalog, (
      scope: scope,
      text: text,
      choices: choices,
    ), small: text.length < _hopText);
  }

  Future<void> restore() => _restoring = _restore();

  Future<void> _restore() async {
    final generation = _begin(work: _Work.restore);
    _clearVisible();
    _notify();
    try {
      await _credentialWrites;
      final restored = await _credentials.read();
      if (!_current(generation)) return;
      if (restored != null) {
        // The account shows at once, and its saved library when it is built.
        _setSession(restored);
        _notify();
        final operation = _operation(request: generation);
        final saved = await _readSaved(operation);
        if (!_current(generation)) return;
        if (saved != null) {
          _adopt(operation, saved);
          _libraries = saved.cache.libraries;
        }
      }
    } on AssertionError {
      rethrow;
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

  /// Signs in to Jellyfin, then reads the account's catalog, as [refresh]
  /// does: every book library that the user did not hide. A new account
  /// hides none, so it shows every book library. A saved catalog that
  /// cannot be read stays as it is until the user asks for a refresh.
  /// Returns true when sign-in succeeded and the catalog could be read.
  /// A failed or cancelled attempt retains the current local account.
  Future<bool> connect(String server, String username, String password) async {
    final signedIn = await _signIn(server, username, password);
    if (signedIn && !_disposed) await refresh(byUser: true);
    return signedIn;
  }

  /// Signs in, and returns whether the catalog can be read now: the
  /// sign-in succeeded, and a saved catalog of the account was readable or
  /// absent. A refresh replaces the saved catalog, so a saved catalog that
  /// cannot be read waits for the user to ask for a refresh.
  Future<bool> _signIn(String server, String username, String password) async {
    // Finish any cancelled credential write before authenticating another
    // candidate. The local account remains authoritative until success.
    if (_work == _Work.signIn) cancel();
    final generation = _begin(work: _Work.signIn);
    var accepted = false;
    _notify();
    try {
      await _credentialWrites;
      final address = parseServer(server);
      final device = await _credentials.deviceId();
      if (!_current(generation)) return false;
      final client = _clientFactory(address, device);
      _active = client;
      final signedIn = await client.signIn(username.trim(), password);
      if (!_current(generation)) return false;
      if (signedIn.scope.server != address) {
        throw const CatalogFailure(CatalogFailureKind.unauthorized);
      }
      final sameAccount = _session?.scope.key == signedIn.scope.key;
      await _changeCredentials(() async {
        if (!_current(generation)) return;
        await _credentials.write(signedIn);
        if (!_current(generation)) return;
        if (!sameAccount) _clearVisible();
        _setSession(signedIn);
        accepted = true;
      });
      if (!_current(generation)) return false;
      _reach = CatalogReach.reached;
      _notify();
      final operation = _operation(request: generation);
      _Built? saved;
      var readable = true;
      try {
        if (!sameAccount || _cache == null) {
          saved = await _readSaved(operation);
        }
      } on AssertionError {
        rethrow;
      } catch (_) {
        readable = false;
        if (_current(generation)) {
          _message =
              'Saved books could not be read. Refresh your book libraries.';
        }
      }
      if (!_current(generation)) return false;
      if (saved != null) _adopt(operation, saved);
      final views = await client.libraries(signedIn);
      if (!_current(generation)) return false;
      _libraries = views;
      try {
        await _saveAccess(blocked: false, generation: generation);
      } on AssertionError {
        rethrow;
      } catch (_) {
        if (_current(generation)) {
          _message = 'Access is back, but your saved books could not be updated. Refresh your book libraries.';
        }
        return false;
      }
      if (!_current(generation)) return false;
      _verified = true;
      return readable;
    } on AssertionError {
      rethrow;
    } catch (error) {
      if (_current(generation)) {
        if (error is CatalogFailure) {
          if (accepted) {
            await _failure(error, generation, report: true);
          } else {
            _message = error.message;
          }
        } else {
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
    return false;
  }

  /// Refreshes after a return from hidden when the last success is older
  /// than one hour or unknown, or the last request could not reach Jellyfin.
  /// An active sign-in, restore or refresh keeps running. Launch and manual
  /// refreshes use [refresh] directly and never wait for staleness.
  Future<void> resume() {
    if (busy || _session == null || _session!.needsSignIn) {
      return Future<void>.value();
    }
    final completedAt = _lastSuccessfulRefresh ?? _cache?.completedAt;
    final age = completedAt == null
        ? null
        : DateTime.now().toUtc().difference(completedAt);
    if (_reach == CatalogReach.unreachable ||
        age == null ||
        age > const Duration(hours: 1)) {
      return refresh();
    }
    return Future<void>.value();
  }

  /// Saves a library choice and reports whether the selector can close.
  /// A changed choice succeeds locally when its shown libraries are complete.
  /// An unchanged selection still requests a refresh. A superseding operation,
  /// failed save, or failed fetch of a missing library returns false.
  Future<bool> setHiddenLibraries(Set<String> hidden) async {
    final changed = !setEquals(hidden, _choices?.hidden);
    final saving = refresh(hidden: hidden, byUser: true);
    final generation = _generation;
    await saving;
    if (!_current(generation) ||
        busy ||
        _choices == null ||
        !_choicesStored ||
        _accessBlocked) {
      return false;
    }
    final requested = {...hidden}
      ..retainAll(_libraries.map((library) => library.id));
    if (!setEquals(requested, _choices!.hidden)) return false;
    final complete =
        _cache?.included.containsAll(
          _libraries
              .where((library) => !requested.contains(library.id))
              .map((library) => library.id),
        ) ??
        false;
    return _verified || (changed && complete);
  }

  /// Reads the account's book libraries from Jellyfin, and the catalog of
  /// each one that shows, then saves and shows them. The future ends when
  /// the refresh ends.
  ///
  /// A library shows unless it is [hidden], or, without [hidden], unless
  /// the user hid it before. So a library that Jellyfin adds later shows by
  /// default. A hidden library that Jellyfin no longer lists leaves the
  /// hidden set, so it shows if it comes back.
  ///
  /// [byUser] says that the person asked for this refresh, for example with
  /// pull to refresh, Retry or Save libraries. A refresh reports a failure
  /// after Jellyfin answered, such as an incomplete catalog or one that
  /// cannot be saved, only when a caller asked for it. A background refresh,
  /// at launch or on app resume, keeps those silent. Every refresh reports
  /// an expired sign-in and revoked access. A refresh that cannot reach
  /// Jellyfin says so through [CatalogStatus.reach].
  ///
  /// One refresh runs at a time. A refresh while another runs, with the
  /// same hidden libraries or with none given, joins it and sends no second
  /// request. With [byUser], it asks for the outcome of the running
  /// refresh. A library choice replaces the running request. It only writes
  /// choices when the selected libraries are already cached; showing a library
  /// whose data is missing fetches it. A refresh during a restore starts after
  /// the restore, from the restored catalog.
  Future<void> refresh({Set<String>? hidden, bool byUser = false}) {
    if (_work == _Work.restore) {
      return _restoring!.then((_) => refresh(hidden: hidden, byUser: byUser));
    }
    if (_work == _Work.signIn || _session?.needsSignIn == true) {
      return Future<void>.value();
    }
    final running = _refreshing;
    if (running != null &&
        _work == _Work.refresh &&
        running.generation == _generation &&
        (hidden == null || setEquals(hidden, running.hidden))) {
      running.reported |= byUser;
      return running.done;
    }
    if (_session == null) return Future<void>.value();
    final verifiedBefore = _verified;
    final refreshing = _refreshing = _Refreshing(
      _begin(),
      hidden,
      reported: byUser,
      verifiedBefore: verifiedBefore,
    );
    return refreshing.done = _refresh(refreshing);
  }

  Future<void> _refresh(_Refreshing refreshing) async {
    final currentSession = _session!;
    final generation = refreshing.generation;
    final operation = _operation(request: generation);
    _notify();
    try {
      if (_choices == null) {
        await _reconcileChoiceNotice(operation);
        if (!_owns(operation)) return;
      }
      if (refreshing.hidden != null &&
          !setEquals(refreshing.hidden, _choices?.hidden) &&
          _cache != null &&
          _choices != null &&
          !_accessBlocked) {
        if (await _selectLibraries(refreshing)) return;
        if (!_current(generation)) return;
      }
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
      final hidden = {...?(refreshing.hidden ?? _choices?.hidden)}
        ..retainAll(views.map((library) => library.id));
      final shown = {
        for (final library in views)
          if (!hidden.contains(library.id)) library.id,
      };
      final pages = shown.isEmpty
          ? const CatalogPages()
          : await client.catalog(validated, shown);
      if (!_current(generation)) return;
      final write = (_cacheWrites ?? Future<void>.value()).then((_) async {
        if (!_current(generation)) return;
        // Network reads remain independent of pending writes. Reconcile the
        // small recovery notice when this response reaches ordered adoption.
        await _reconcileChoiceNotice(operation);
        if (!_owns(operation)) return;
        final previous = _cache;
        final choices = _choices!.change(hidden: hidden);
        final built = await _build(_refreshCatalog, (
          scope: validated.scope,
          libraries: views,
          hidden: hidden,
          pages: pages,
          choices: choices,
          previousHidden: _choices!.hidden,
          previousIncluded: previous?.included ?? const {},
          previousText: _text,
          completedAt: DateTime.now().toUtc(),
          previousContent: previous?.scope.key == validated.scope.key
              ? previous?.content
              : null,
          canKeepSavedCatalog:
              _cacheStored &&
              previous != null &&
              previous.scope.key == validated.scope.key &&
              !previous.accessBlocked &&
              listEquals(
                _libraryNames(previous.libraries),
                _libraryNames(views),
              ),
        ), small: pages.items < _hopEntries && (_text?.length ?? 0) < _hopText);
        if (!_current(generation)) return;
        if (!_choicesStored || !setEquals(_choices!.hidden, choices.hidden)) {
          await _writeChoices(validated.scope, choices);
          if (!_current(generation)) return;
          await _adoptChoices(operation, choices);
          if (!_owns(operation)) return;
        }
        if (built != null) {
          if (!_cacheStored || !identical(built.text, _text)) {
            await _writeCatalog(validated.scope, built.text);
          }
          if (!_current(generation)) return;
          _adopt(operation, built);
        }
        _setSession(validated);
        _accessBlocked = false;
        _lastSuccessfulRefresh = DateTime.now().toUtc();
        _verified = true;
      });
      _cacheWrites = write.catchError((Object _) {});
      await write;
    } on AssertionError {
      rethrow;
    } catch (error) {
      if (_current(generation)) {
        if (error is CatalogFailure) {
          await _failure(error, generation, report: refreshing.reported);
        } else if (refreshing.reported) {
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

  /// Saves a library choice using known entries. Only showing a library whose
  /// complete data is absent needs a server refresh. The same write queue as
  /// corrections and refresh adoption prevents older work from winning.
  Future<bool> _selectLibraries(_Refreshing refreshing) async {
    var complete = false;
    final scope = _session!.scope;
    final generation = refreshing.generation;
    final operation = _operation(request: generation);
    final write = (_cacheWrites ?? Future<void>.value()).then((_) async {
      if (!_current(generation)) return;
      final cache = _cache!;
      final hidden = {...refreshing.hidden!}
        ..retainAll(_libraries.map((library) => library.id));
      final choices = _choices!.change(hidden: hidden);
      final changed = !setEquals(choices.hidden, _choices!.hidden);
      CatalogLibrary? library;
      if (changed && cache.entries.isNotEmpty) {
        library = await _build(_changeVisibility, (
          entries: cache.entries,
          choices: choices,
          previousHidden: _choices!.hidden,
        ), small: false);
      }
      if (!_current(generation)) return;
      if (changed || !_choicesStored) {
        await _writeChoices(scope, choices);
        if (!_current(generation)) return;
        // The visibility worker returns null only when no cached entry changes
        // visibility. That result explicitly permits reusing the current view.
        await _adoptChoices(operation, choices, library: library ?? _built);
      }
      if (!_owns(operation)) return;
      complete = cache.included.containsAll(
        _libraries
            .where((library) => !hidden.contains(library.id))
            .map((library) => library.id),
      );
      if (complete) _verified = refreshing.verifiedBefore;
    });
    _cacheWrites = write.catchError((Object _) {});
    await write;
    return complete;
  }

  /// Records [failure] of the sign-in or refresh of [generation]. It always
  /// tells an expired sign-in and blocked access. It tells a failure after
  /// Jellyfin answered only when [report] is true. It leaves a signed-in
  /// catalog that cannot reach Jellyfin to [CatalogStatus.reach].
  Future<void> _failure(
    CatalogFailure failure,
    int generation, {
    required bool report,
  }) async {
    _verified = false;
    _message = switch (failure.kind) {
      CatalogFailureKind.unavailable when _session != null => null,
      CatalogFailureKind.unauthorized ||
      CatalogFailureKind.forbidden => failure.message,
      _ => report ? failure.message : null,
    };
    _reach = switch (failure.kind) {
      CatalogFailureKind.unavailable => CatalogReach.unreachable,
      // The request did not reach Jellyfin, so it says nothing new.
      CatalogFailureKind.cancelled ||
      CatalogFailureKind.invalidServer => _reach,
      // Jellyfin answered. A rejected credential is retired below.
      _ => CatalogReach.reached,
    };
    if (failure.kind == CatalogFailureKind.unauthorized) {
      if (_session case final session?) {
        session.rejectCredential();
        await _credentialWrites;
      } else {
        _reach = CatalogReach.signInExpired;
      }
    } else if (failure.kind == CatalogFailureKind.forbidden) {
      _accessBlocked = true;
      if (_session == null) return;
      try {
        await _saveAccess(blocked: true, generation: generation);
      } on AssertionError {
        rethrow;
      } catch (_) {
        // Without a saved denial, prevent automatic restoration of this account.
        await _writeCredentials(null);
        if (_current(generation)) {
          _message = 'Access is blocked and the saved account was signed out. Sign in again to resolve access.';
        }
      }
    }
  }

  /// Saves Jellyfin's latest answer about access, [blocked], in the saved
  /// catalog after the writes before it, and adopts the result. A denial
  /// and a sign-in that lists the book libraries both answer it; a
  /// refresh saves a whole new catalog, which is not blocked. The catalog
  /// keeps its entries and corrections. Without a saved catalog, an allowed
  /// account needs none, and a blocked one gets an empty one. Throws when
  /// the catalog cannot be saved, and then adopts nothing.
  Future<void> _saveAccess({required bool blocked, required int generation}) {
    final scope = _session!.scope;
    final operation = _operation(request: generation);
    final write = (_cacheWrites ?? Future<void>.value()).then((_) async {
      if (!_current(generation)) return;
      final previous = _cache;
      if ((previous?.accessBlocked ?? false) == blocked) return;
      final saved = previous == null
          ? _saveCatalog(
              CatalogCache(
                scope: scope,
                libraries: _libraries,
                accessBlocked: true,
              ),
              _choices ?? CatalogChoices(),
            )
          : await _revise((
              scope: scope,
              text: _text!,
              choices: _choices!,
              accessBlocked: blocked,
            ));
      if (!_current(generation)) return;
      await _writeCatalog(scope, saved.text);
      _adopt(operation, saved);
    });
    _cacheWrites = write.catchError((Object _) {});
    return write;
  }

  Future<void> signOut() async {
    _begin();
    _clearVisible();
    _work = _Work.idle;
    _notify();
    final generation = _generation;
    try {
      await _writeCredentials(null);
    } on AssertionError {
      rethrow;
    } catch (_) {
      if (_current(generation)) {
        _message = 'Secure sign-out could not be saved. Retry sign-out before leaving this device.';
        _notify();
      }
    }
  }

  void cancel() {
    if (_work == _Work.signIn) {
      // A secure write already in flight cannot be cancelled. Queue the
      // still-current account after it, so cancellation is durable too.
      unawaited(
        _writeCredentials(
          _session,
        ).catchError((Object _) {}, test: (error) => error is! AssertionError),
      );
    }
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
    if (_session == null ||
        _cache == null ||
        _choices == null ||
        _accessBlocked) {
      throw StateError('Sign in and load a book catalog before correcting it.');
    }
    final operation = _operation();
    final write = (_cacheWrites ?? Future<void>.value()).then((_) async {
      if (!_owns(operation)) return;
      final previous = _cache!;
      try {
        final choices = _choices!.change(edits: change(_choices!.edits));
        // The entries are already decoded. Only rebuilding the derived books
        // needs the worker; no catalog decode, digest, encode or write occurs.
        final library = await _build(_correctCatalog, (
          entries: previous.entries,
          choices: choices,
        ), small: previous.entries.isEmpty);
        if (!_owns(operation)) return;
        await _writeChoices(previous.scope, choices);
        if (!_owns(operation)) return;
        await _adoptChoices(operation, choices, library: library);
        if (!_owns(operation)) return;
        _message = null;
        _notify();
      } on AssertionError {
        rethrow;
      } catch (_) {
        if (_owns(operation)) {
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
    _session?.credentialChanges.removeListener(_credentialRejected);
    ++_generation;
    _active?.close();
    _librarySignal.dispose();
    _accountSignal.dispose();
    _statusSignal.dispose();
    super.dispose();
  }
}
