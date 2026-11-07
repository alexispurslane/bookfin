import 'dart:async';

import 'package:bookfin/app/account_binding.dart';
import 'package:bookfin/catalog/controller.dart';
import 'package:bookfin/catalog/jellyfin.dart';
import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/downloads/downloads.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:bookfin/reader/session.dart';
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

void main() {
  late FixtureClient client;
  late CatalogController catalog;
  late _Log log;
  late _Downloads downloads;
  late _Playback playback;
  late _Reader reader;
  AccountBinding? binding;

  setUp(() async {
    client = FixtureClient(Uri.parse('https://books.example'))
      ..entries = [entry('frost', title: 'First Frost')];
    catalog = CatalogController(
      credentials: MemoryCredentials(),
      store: MemoryCatalogStore(),
      clientFactory: (_, _) => client,
    );
    await catalog.connect('https://books.example', 'alice', 'password');
    await catalog.refresh(selected: {'books'});
    log = _Log();
    downloads = _Downloads(log);
    playback = _Playback(log, downloads);
    reader = _Reader(log, downloads);
  });
  tearDown(() async {
    binding?.dispose();
    binding = null;
    await playback.close();
    reader.dispose();
    downloads.dispose();
    catalog.dispose();
    client.close();
  });

  AccountBinding bind() => binding = AccountBinding(
    catalog: catalog,
    downloads: downloads,
    playback: playback,
    reader: reader,
  );

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

  test('a disposed binding binds nothing more', () async {
    bind().dispose();
    binding = null;
    await pumpEventQueue();
    log.binds.clear();
    await catalog.signOut();
    await pumpEventQueue();
    expect(log.binds, isEmpty);
  });
}
