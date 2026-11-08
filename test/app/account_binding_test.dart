import 'dart:async';

import 'package:bookfin/app/account_binding.dart';
import 'package:bookfin/catalog/controller.dart';
import 'package:bookfin/catalog/jellyfin.dart';
import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/downloads/downloads.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:bookfin/playback/store.dart';
import 'package:bookfin/reader/session.dart';
import 'package:bookfin/sync/coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

import '../catalog/controller_test.dart'
    show FixtureClient, MemoryCatalogStore, MemoryCredentials;
import '../catalog/model_test.dart' show entry;
import '../playback/playback_test.dart' show MemoryResume, TestEngine;

/// One call to a source's bind: who, the account, and the books.
typedef _Bind = ({String source, String? account, List<Book> books});

/// Records each source's binds in one log, in the order they start. A test
/// can hold Downloads' binds open with [downloadsGate].
class _Log {
  final binds = <_Bind>[];
  final events = <String>[];
  Completer<void>? downloadsGate;

  Future<void> bind(
    String source,
    JellyfinSession? session,
    List<Book> books,
  ) async {
    binds.add((source: source, account: session?.scope.key, books: books));
    events.add('$source started');
    if (source == 'downloads') await downloadsGate?.future;
    events.add('$source finished');
  }

  List<String> sources() => [for (final bind in binds) bind.source];
}

class _Downloads extends Downloads {
  _Downloads(this.log) : super(MediaPolicy());
  final _Log log;
  @override
  bool get supported => true;
  @override
  Future<void> bind(JellyfinSession? session, List<Book> books) =>
      log.bind('downloads', session, books);
  @override
  EditionDownload status(Edition edition) => const EditionDownload();
  @override
  Future<void> request(Edition edition) async {}
  @override
  Future<void> cancel(Edition edition) async {}
  @override
  Future<void> remove(Edition edition) async {}
  @override
  Future<Uri?> localFile(SourceFile source) async => null;
  @override
  Future<void> get idle async {}
  @override
  void checkInvariants() {}
}

class _Playback extends Playback {
  _Playback(this.log, Downloads downloads)
    : super(downloads: downloads, engine: TestEngine(), store: MemoryResume());
  final _Log log;
  @override
  Future<void> bind(JellyfinSession? session, List<Book> books) =>
      log.bind('playback', session, books);
}

class _Reader extends ReaderSession {
  _Reader(this.log, Downloads downloads)
    : super(
        downloads: downloads,
        store: MemoryResume(),
        load: (_) => throw UnimplementedError(),
      );
  final _Log log;
  @override
  Future<void> bind(JellyfinSession? account, List<Book> books) =>
      log.bind('reader', account, books);
}

/// Records each bind and each sync request, and contacts no server.
class _Sync extends RecordSync {
  _Sync() : super(records: LocalResumeStore());

  /// `bind <account>` and `synchronize`, in the order they came.
  final calls = <String>[];
  @override
  void bind(JellyfinSession? session) =>
      calls.add('bind ${session?.scope.key}');
  @override
  Future<void> synchronize() async => calls.add('synchronize');
}

/// Like the real client, it answers each validation with a new session
/// object that equals the one it checked. A test can hold validation open
/// with [validateGate].
class _Client extends FixtureClient {
  _Client(super.server);
  Completer<void>? validateGate;
  @override
  Future<JellyfinSession> validate(JellyfinSession session) async {
    await validateGate?.future;
    final checked = await super.validate(session);
    return JellyfinSession(
      scope: checked.scope,
      token: checked.token,
      username: checked.username,
      canDownload: checked.canDownload,
    );
  }
}

void main() {
  late _Client client;
  late MemoryCatalogStore store;
  late CatalogController catalog;
  late _Log log;
  late _Downloads downloads;
  late _Playback playback;
  late _Reader reader;
  late _Sync sync;
  AccountBinding? binding;

  setUp(() async {
    client = _Client(Uri.parse('https://books.example'))
      ..entries = [entry('frost', title: 'First Frost')];
    store = MemoryCatalogStore();
    catalog = CatalogController(
      credentials: MemoryCredentials(),
      store: store,
      clientFactory: (_, _) => client,
    );
    await catalog.connect('https://books.example', 'alice', 'password');
    await catalog.refresh(selected: {'books'});
    log = _Log();
    downloads = _Downloads(log);
    playback = _Playback(log, downloads);
    reader = _Reader(log, downloads);
    sync = _Sync();
  });
  tearDown(() async {
    binding?.dispose();
    binding = null;
    await playback.close();
    reader.dispose();
    sync.dispose();
    downloads.dispose();
    catalog.dispose();
    client.close();
  });

  AccountBinding bind() => binding = AccountBinding(
    catalog: catalog,
    downloads: downloads,
    playback: playback,
    reader: reader,
    sync: sync,
  );

  /// Binds, lets the first binding finish, and forgets what it did.
  Future<void> bound() async {
    bind();
    await pumpEventQueue();
    log.binds.clear();
    log.events.clear();
    sync.calls.clear();
  }

  test('a new book list binds Downloads and the reader at once, and Playback once Downloads is bound', () async {
    log.downloadsGate = Completer();
    bind();
    await pumpEventQueue();
    expect(log.events, [
      'reader started',
      'reader finished',
      'downloads started',
    ]);
    log.downloadsGate!.complete();
    await pumpEventQueue();
    expect(log.events.skip(3), [
      'downloads finished',
      'playback started',
      'playback finished',
    ]);
    for (final bind in log.binds) {
      expect(bind.account, catalog.session!.scope.key);
      expect(bind.books, same(catalog.books));
    }
  });

  test(
    'a binding that a newer book list replaced stops before Playback',
    () async {
      log.downloadsGate = Completer();
      bind();
      await pumpEventQueue();
      final first = catalog.books;
      client.entries = [
        entry('frost', title: 'First Frost'),
        entry('ember', title: 'Ember'),
      ];
      await catalog.refresh();
      await pumpEventQueue();
      log.downloadsGate!.complete();
      await pumpEventQueue();
      final played = [
        for (final bind in log.binds)
          if (bind.source == 'playback') bind.books,
      ];
      expect(played, hasLength(1));
      expect(played.single, isNot(same(first)));
      expect(played.single, same(catalog.books));
    },
  );

  test(
    'an account change unbinds Playback and the reader before it binds again',
    () async {
      bind();
      await pumpEventQueue();
      log.binds.clear();
      await catalog.signOut();
      await pumpEventQueue();
      expect(log.sources().take(2), ['playback', 'reader']);
      expect(log.binds.take(2).map((bind) => bind.account), [null, null]);
      expect(log.sources().skip(2), containsAll(['downloads', 'reader']));
      for (final bind in log.binds) {
        expect(bind.account, isNull);
        expect(bind.books, isEmpty);
      }
    },
  );

  test(
    'a catalog notice that keeps the account and books does not rebind',
    () async {
      bind();
      await pumpEventQueue();
      expect(log.sources(), hasLength(3));
      catalog.cancel();
      await pumpEventQueue();
      expect(catalog.message, 'Refresh cancelled.');
      expect(log.sources(), hasLength(3));
    },
  );

  test('a refreshed library rebinds Downloads with its new books', () async {
    bind();
    await pumpEventQueue();
    client.entries = [
      entry('frost', title: 'First Frost'),
      entry('ember', title: 'Ember'),
    ];
    await catalog.refresh();
    await pumpEventQueue();
    final bound = [
      for (final bind in log.binds)
        if (bind.source == 'downloads') bind,
    ];
    expect(bound, hasLength(2));
    expect(bound.last.books.map((book) => book.title), contains('Ember'));
  });

  test('signing out rebinds Downloads without an account', () async {
    bind();
    await pumpEventQueue();
    await catalog.signOut();
    await pumpEventQueue();
    final bound = [
      for (final bind in log.binds)
        if (bind.source == 'downloads') bind,
    ];
    expect(bound, hasLength(2));
    expect(bound.last.account, isNull);
    expect(bound.last.books, isEmpty);
  });

  test('a refresh that cannot reach Jellyfin keeps the account and its books bound', () async {
    bind();
    await pumpEventQueue();
    log.binds.clear();
    client.failure = const CatalogFailure(CatalogFailureKind.unavailable);
    await catalog.refresh();
    await pumpEventQueue();
    expect(catalog.session, isNotNull);
    expect(catalog.books, isNotEmpty);
    expect([
      for (final bind in log.binds)
        if (bind.account == null) bind.source,
    ], isEmpty);
  });

  test('at launch the saved library is bound before the background refresh ends, and stays bound when that refresh cannot reach Jellyfin', () async {
    final restarted = CatalogController(
      credentials: MemoryCredentials()..value = catalog.session,
      store: store,
      clientFactory: (_, _) => client,
    );
    addTearDown(restarted.dispose);
    await restarted.restore();
    client.validateGate = Completer();
    client.failure = const CatalogFailure(CatalogFailureKind.unavailable);
    final refreshing = restarted.refresh();
    binding = AccountBinding(
      catalog: restarted,
      downloads: downloads,
      playback: playback,
      reader: reader,
      sync: sync,
    );
    await pumpEventQueue();
    expect(restarted.statusNotifier.value.refreshing, isTrue);
    expect(log.binds.map((bind) => bind.source).toSet(), {
      'downloads',
      'playback',
      'reader',
    });
    for (final bind in log.binds) {
      expect(bind.account, restarted.session!.scope.key);
      expect(bind.books, same(restarted.books));
    }
    log.binds.clear();
    client.validateGate!.complete();
    await refreshing;
    await pumpEventQueue();
    expect(restarted.statusNotifier.value.reach, CatalogReach.unreachable);
    expect(log.binds, isEmpty);
  });

  test('a disposed binding binds nothing more', () async {
    bind().dispose();
    binding = null;
    await pumpEventQueue();
    log.binds.clear();
    await catalog.signOut();
    await pumpEventQueue();
    expect(log.binds, isEmpty);
  });
  test(
    'the start of a refresh binds nothing and synchronizes nothing',
    () async {
      await bound();
      client.validateGate = Completer();
      final refreshing = catalog.refresh();
      await pumpEventQueue();
      expect(catalog.statusNotifier.value.refreshing, isTrue);
      expect(log.binds, isEmpty);
      expect(sync.calls, isEmpty);
      client.validateGate!.complete();
      await refreshing;
    },
  );

  test('a new status message binds nothing and synchronizes nothing', () async {
    await bound();
    client.validateGate = Completer();
    final refreshing = catalog.refresh();
    await pumpEventQueue();
    log.binds.clear();
    sync.calls.clear();
    catalog.cancel();
    await pumpEventQueue();
    expect(catalog.statusNotifier.value.message, 'Refresh cancelled.');
    expect(log.binds, isEmpty);
    expect(sync.calls, isEmpty);
    client.validateGate!.complete();
    await refreshing;
  });

  test('a refresh that brings the same books binds nothing and starts no record sync', () async {
    await bound();
    final books = catalog.books;
    await catalog.refresh();
    await pumpEventQueue();
    expect(catalog.verified, isTrue);
    expect(catalog.books, same(books));
    expect(log.binds, isEmpty);
    expect(sync.calls, isEmpty);
  });

  test(
    'new books rebind Downloads and then Playback with the new books',
    () async {
      await bound();
      client.entries = [
        entry('frost', title: 'First Frost'),
        entry('ember', title: 'Ember'),
      ];
      await catalog.refresh();
      await pumpEventQueue();
      expect(log.events.where((event) => event.endsWith('started')), [
        'reader started',
        'downloads started',
        'playback started',
      ]);
      for (final bind in log.binds) {
        expect(bind.account, catalog.session!.scope.key);
        expect(bind.books, same(catalog.books));
      }
      expect(catalog.books.map((book) => book.title), contains('Ember'));
      expect(sync.calls.where((call) => call.startsWith('bind')), isEmpty);
    },
  );

  test('blocked access unbinds Playback and the reader before it binds again without an account', () async {
    await bound();
    client.failure = const CatalogFailure(CatalogFailureKind.forbidden);
    await catalog.refresh();
    await pumpEventQueue();
    expect(catalog.accessBlocked, isTrue);
    expect(log.sources().take(2), ['playback', 'reader']);
    expect(log.sources().skip(2), containsAll(['downloads', 'reader']));
    for (final bind in log.binds) {
      expect(bind.account, isNull);
      expect(bind.books, isEmpty);
    }
    expect(sync.calls, ['bind null']);
  });

  test('a refresh that cannot reach Jellyfin binds nothing and keeps record sync on the account', () async {
    await bound();
    client.failure = const CatalogFailure(CatalogFailureKind.unavailable);
    await catalog.refresh();
    await pumpEventQueue();
    expect(catalog.statusNotifier.value.reach, CatalogReach.unreachable);
    expect(log.binds, isEmpty);
    expect(sync.calls, isEmpty);
  });

  test('signing in binds record sync to the new account, which then syncs on its own schedule', () async {
    await catalog.signOut();
    await bound();
    await catalog.connect('https://books.example', 'bob', 'password');
    await pumpEventQueue();
    final key = catalog.session!.scope.key;
    expect(sync.calls, ['bind $key']);
    final accounts = [for (final bind in log.binds) bind.account];
    expect(accounts.take(2), [null, null]);
    expect(accounts.skip(2), everyElement(key));
  });

  test('a binding that starts after a refresh that succeeded binds record sync and starts no sync of its own', () async {
    bind();
    await pumpEventQueue();
    expect(sync.calls, ['bind ${catalog.session!.scope.key}']);
  });

  test('a correction after a refresh starts no record sync, even when it cannot be saved', () async {
    await bound();
    await catalog.correctBook(
      catalog.books.single.id,
      const BookDetails(title: 'Corrected', author: 'Writer'),
    );
    store.failWrites = true;
    await catalog.correctBook(
      catalog.books.single.id,
      const BookDetails(title: 'Again', author: 'Writer'),
    );
    await pumpEventQueue();
    expect(catalog.statusNotifier.value.message, contains('correction'));
    expect(sync.calls, isEmpty);
  });

  test('a refresh that Jellyfin answers but that fails does not synchronize records', () async {
    await bound();
    client.failure = const CatalogFailure(CatalogFailureKind.incomplete);
    await catalog.refresh();
    client.failure = null;
    store.failWrites = true;
    await catalog.refresh();
    await pumpEventQueue();
    expect(catalog.statusNotifier.value.reach, CatalogReach.reached);
    expect(catalog.session, isNotNull);
    expect(catalog.books, isNotEmpty);
    expect(log.binds, isEmpty);
    expect(sync.calls, isEmpty);
  });

  test('a refresh that succeeds starts no record sync, because record sync keeps its own schedule', () async {
    await bound();
    await catalog.refresh();
    client.failure = const CatalogFailure(CatalogFailureKind.unavailable);
    await catalog.refresh();
    client.failure = null;
    await catalog.refresh();
    await pumpEventQueue();
    expect(sync.calls, isEmpty);
  });
}
