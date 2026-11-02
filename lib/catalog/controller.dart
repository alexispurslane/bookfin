import 'package:flutter/foundation.dart';

import 'jellyfin.dart';
import 'model.dart';
import 'store.dart';

typedef JellyfinClientFactory = JellyfinClient Function(
  Uri server,
  String deviceId,
);

class CatalogController extends ChangeNotifier {
  CatalogController({
    required this._credentials,
    required this._store,
    JellyfinClientFactory? clientFactory,
  }) : _clientFactory =
           clientFactory ??
           ((server, deviceId) => JellyfinClient(server, deviceId: deviceId));
  final CredentialStore _credentials;
  final CatalogStore _store;
  final JellyfinClientFactory _clientFactory;
  JellyfinClient? _active;
  JellyfinSession? _session;
  CatalogCache? _cache;
  List<BookLibrary> _libraries = [];
  List<Book> _books = [];
  bool _busy = false;
  bool _verified = false;
  bool _accessBlocked = false;
  bool _disposed = false;
  String? _message;
  int _generation = 0;
  int _accountGeneration = 0;
  Future<void>? _credentialWrites;
  Future<void>? _cacheWrites;

  JellyfinSession? get session => _session;
  CatalogCache? get cache => _cache;
  List<Book> get books =>
      _session == null || _accessBlocked ? const [] : _books;
  List<BookLibrary> get libraries => List.unmodifiable(_libraries);
  bool get busy => _busy;
  bool get verified => _verified;
  bool get accessBlocked => _accessBlocked;
  String? get message => _message;

  void checkInvariants() {
    if (_session == null &&
        (_cache != null ||
            _books.isNotEmpty ||
            _libraries.isNotEmpty ||
            _verified)) {
      throw StateError('A signed-out catalog must contain no account data.');
    }
    if (_cache != null && _cache!.scope.key != _session?.scope.key) {
      throw StateError('The cache must belong to the active account.');
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
    for (final book in _books) {
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
  }

  int _begin() {
    _active?.close();
    _active = null;
    _busy = true;
    _verified = false;
    _message = null;
    return ++_generation;
  }

  bool _current(int generation) => !_disposed && generation == _generation;
  void _notify() {
    if (!_disposed) notifyListeners();
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
    _books = [];
    _libraries = [];
    _verified = false;
    _accessBlocked = false;
  }

  void _publish(CatalogCache value) {
    assert(_session?.scope.key == value.scope.key);
    _cache = value;
    _accessBlocked = value.accessBlocked;
    _books = buildBooks(value.entries, edits: value.edits);
  }

  Future<void> restore() async {
    final generation = _begin();
    _clearVisible();
    _notify();
    try {
      await _credentialWrites;
      final restored = await _credentials.read();
      if (!_current(generation)) return;
      if (restored != null) {
        _session = restored;
        final saved = await _store.read(restored.scope);
        if (!_current(generation)) return;
        if (saved != null && saved.scope.key == restored.scope.key) {
          _publish(saved);
          _libraries = saved.libraries;
        }
      }
    } catch (_) {
      if (_current(generation)) {
        _message =
            'Saved account data could not be read. Sign in again if needed.';
      }
    } finally {
      if (_current(generation)) {
        _busy = false;
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
      if (signedIn.scope.server != address) {
        throw const CatalogFailure(CatalogFailureKind.unauthorized);
      }
      await _writeCredentials(signedIn);
      if (!_current(generation)) return;
      _session = signedIn;
      CatalogCache? saved;
      try {
        saved = await _store.read(signedIn.scope);
      } catch (_) {
        if (_current(generation)) {
          _message =
              'Saved books could not be read. Refresh your book libraries.';
        }
      }
      if (!_current(generation)) return;
      if (saved != null && saved.scope.key == signedIn.scope.key) {
        _publish(saved);
      }
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
        _busy = false;
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
        final next = CatalogCache(
          scope: validated.scope,
          libraries: views,
          selected: Set.unmodifiable(selection),
          entries: List.unmodifiable(entries),
          edits: _cache?.edits,
          completedAt: DateTime.now().toUtc(),
        );
        buildBooks(next.entries, edits: next.edits);
        await _store.write(validated.scope, next);
        if (!_current(generation)) return;
        _session = validated;
        _publish(next);
        _verified = true;
        _accessBlocked = false;
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
        _busy = false;
        _active?.close();
        _active = null;
        _notify();
      }
    }
  }

  Future<void> _failure(CatalogFailure failure, int generation) async {
    _verified = false;
    _message = failure.message;
    if (failure.kind == CatalogFailureKind.unauthorized) {
      _clearVisible();
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
        final denied = CatalogCache(
          scope: scope,
          libraries: previous?.libraries ?? _libraries,
          selected: previous?.selected ?? const {},
          entries: previous?.entries ?? const [],
          edits: previous?.edits,
          completedAt: previous?.completedAt,
          accessBlocked: true,
        );
        await _store.write(scope, denied);
        if (_current(generation)) _cache = denied;
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
    _busy = false;
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
    _busy = false;
    _verified = false;
    _message = 'Refresh cancelled.';
    _notify();
  }

  Book _book(String id) => books.firstWhere(
    (book) => book.id == id,
    orElse: () => throw ArgumentError.value(
      id,
      'bookId',
      'Book is not in the active catalog.',
    ),
  );

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
      final next = CatalogCache(
        scope: previous.scope,
        libraries: previous.libraries,
        selected: previous.selected,
        entries: previous.entries,
        edits: change(previous.edits),
        completedAt: previous.completedAt,
      );
      final rebuilt = buildBooks(next.entries, edits: next.edits);
      try {
        await _store.write(next.scope, next);
        if (!currentAccount()) return;
        _cache = next;
        _books = rebuilt;
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
    super.dispose();
  }
}
