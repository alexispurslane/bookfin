import 'dart:async';

import 'package:bookfin/catalog/controller.dart';
import 'package:bookfin/catalog/jellyfin.dart';
import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/catalog/store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'model_test.dart' show entry;

JellyfinSession account(
  String user, {
  String server = 'https://books.example',
}) => JellyfinSession(
  scope: AccountScope(
    server: Uri.parse(server),
    serverId: 'server',
    userId: user,
  ),
  token: 'token-$user',
  username: user,
  canDownload: false,
);

class MemoryCredentials implements CredentialStore {
  JellyfinSession? value;
  bool failWrites = false;
  @override
  Future<JellyfinSession?> read() async => value;
  @override
  Future<void> write(JellyfinSession? session) async {
    if (failWrites) throw StateError('vault failure');
    value = session;
  }

  @override
  Future<String> deviceId() async => 'test-device';
}

class MemoryCatalogStore implements CatalogStore {
  final values = <String, CatalogCache>{};
  bool failWrites = false;
  bool failReads = false;
  Completer<void>? gate;
  @override
  Future<CatalogCache?> read(AccountScope scope) async {
    if (failReads) throw StateError('unreadable cache');
    return values[scope.key];
  }

  @override
  Future<void> write(AccountScope scope, CatalogCache cache) async {
    await gate?.future;
    if (failWrites) throw StateError('disk failure');
    values[scope.key] = cache;
  }
}

class FixtureClient extends JellyfinClient {
  FixtureClient(super.server) : super(deviceId: 'test');
  List<CatalogEntry> entries = [entry('one')];
  List<BookLibrary> views = [const BookLibrary('books', 'Books')];
  CatalogFailure? failure;
  Completer<List<CatalogEntry>>? pendingCatalog;
  Completer<JellyfinSession>? pendingSignIn;
  @override
  Future<JellyfinSession> signIn(String username, String password) async =>
      pendingSignIn?.future ?? account(username, server: server.toString());
  @override
  Future<JellyfinSession> validate(JellyfinSession session) async {
    if (failure != null) throw failure!;
    return session;
  }

  @override
  Future<List<BookLibrary>> libraries(JellyfinSession session) async {
    if (failure != null) throw failure!;
    return views;
  }

  @override
  Future<List<CatalogEntry>> catalog(
    JellyfinSession session,
    Set<String> selected,
  ) async {
    if (failure != null) throw failure!;
    return pendingCatalog?.future ?? entries;
  }
}

void main() {
  late MemoryCredentials credentials;
  late MemoryCatalogStore store;
  late FixtureClient client;
  late CatalogController controller;
  setUp(() {
    credentials = MemoryCredentials();
    store = MemoryCatalogStore();
    client = FixtureClient(Uri.parse('https://books.example'));
    controller = CatalogController(
      credentials: credentials,
      store: store,
      clientFactory: (server, device) => client,
    );
  });
  tearDown(() {
    controller.dispose();
    client.close();
  });
  Future<void> connectAndSelect() async {
    await controller.connect('https://books.example', 'alice', 'password');
    await controller.refresh(selected: {'books'});
  }

  test(
    'a complete selected catalog is available after a fresh offline restart',
    () async {
      await connectAndSelect();
      expect(controller.books.map((book) => book.title), ['The Orchard']);
      final restarted = CatalogController(
        credentials: credentials,
        store: store,
        clientFactory: (server, device) => client,
      );
      await restarted.restore();
      expect(restarted.books.single.editions.single.files.single.itemId, 'one');
      expect(restarted.verified, isFalse);
      restarted.dispose();
    },
  );

  test(
    'sign-out clears visible books and token but preserves the account cache',
    () async {
      await connectAndSelect();
      final signingOut = controller.signOut();
      expect(controller.books, isEmpty);
      expect(controller.session, isNull);
      await signingOut;
      expect(credentials.value, isNull);
      expect(store.values[account('alice').scope.key]!.entries, hasLength(1));
    },
  );

  test(
    'another user never sees the previous account books or corrections',
    () async {
      await connectAndSelect();
      await controller.correctBook(
        controller.books.single.id,
        const BookDetails(title: 'Private correction', author: 'Alice'),
      );
      await controller.signOut();
      await controller.connect('https://books.example', 'bob', 'password');
      expect(controller.books, isEmpty);
      await controller.refresh(selected: {'books'});
      expect(controller.books.single.title, 'The Orchard');
      expect(controller.cache!.edits.details, isEmpty);
    },
  );

  test(
    'the same user name on a different server never restores another catalog',
    () async {
      await connectAndSelect();
      await controller.signOut();
      final other = account('alice', server: 'https://other.example');
      credentials.value = other;
      await controller.restore();
      expect(
        controller.session!.scope.server,
        Uri.parse('https://other.example'),
      );
      expect(controller.books, isEmpty);
    },
  );

  test(
    'a failed refresh retains the last complete persisted catalog',
    () async {
      await connectAndSelect();
      final saved = store.values[account('alice').scope.key];
      client.failure = const CatalogFailure(CatalogFailureKind.incomplete);
      await controller.refresh();
      expect(controller.books, hasLength(1));
      expect(store.values[account('alice').scope.key], same(saved));
      expect(controller.message, contains('incomplete'));
    },
  );

  test('a stale refresh cannot repopulate a signed-out account', () async {
    await connectAndSelect();
    client.pendingCatalog = Completer();
    final refreshing = controller.refresh();
    await Future<void>.delayed(Duration.zero);
    await controller.signOut();
    client.pendingCatalog!.complete([entry('private')]);
    await refreshing;
    expect(controller.books, isEmpty);
    expect(credentials.value, isNull);
  });

  test(
    'cancelled refresh keeps cached books and ignores its late response',
    () async {
      await connectAndSelect();
      client.pendingCatalog = Completer();
      final refreshing = controller.refresh();
      await Future<void>.delayed(Duration.zero);
      controller.cancel();
      client.pendingCatalog!.complete([entry('replacement')]);
      await refreshing;
      expect(
        controller.books.single.editions.single.files.single.itemId,
        'one',
      );
      expect(controller.busy, isFalse);
    },
  );

  test('a delayed sign-in cannot overwrite sign-out token deletion', () async {
    client.pendingSignIn = Completer();
    final signingIn = controller.connect(
      'https://books.example',
      'alice',
      'password',
    );
    await Future<void>.delayed(Duration.zero);
    await controller.signOut();
    client.pendingSignIn!.complete(account('alice'));
    await signingIn;
    expect(controller.session, isNull);
    expect(credentials.value, isNull);
  });

  test('revoked authorization hides cached books without deleting the complete cache', () async {
    await connectAndSelect();
    client.failure = const CatalogFailure(CatalogFailureKind.unauthorized);
    await controller.refresh();
    expect(controller.books, isEmpty);
    expect(credentials.value, isNull);
    expect(store.values, isNotEmpty);
  });

  test(
    'forbidden catalog access hides books but does not destroy offline records',
    () async {
      await connectAndSelect();
      client.failure = const CatalogFailure(CatalogFailureKind.forbidden);
      await controller.refresh();
      expect(controller.books, isEmpty);
      expect(controller.accessBlocked, isTrue);
      expect(store.values, isNotEmpty);
    },
  );

  test(
    'confirmed links, file groups, and series corrections survive a restart',
    () async {
      client.entries = [
        entry('one'),
        entry('two', track: 2),
        entry('ebook', type: 'Book', container: 'epub'),
      ];
      await connectAndSelect();
      await controller.linkBooks('book:two', 'book:one');
      await controller.linkBooks('book:ebook', 'book:one');
      expect(controller.books.single.editions, hasLength(3));
      await controller.combineAudio('book:one', ['one:source', 'two:source']);
      await controller.correctBook(
        'book:one',
        const BookDetails(
          title: 'Orchard',
          author: 'Writer',
          series: 'Garden',
          seriesOrder: 1.5,
        ),
      );
      await controller.orderFiles('one:source', ['two:source', 'one:source']);
      await controller.restore();
      final book = controller.books.single;
      expect(book.seriesOrder, 1.5);
      expect(
        book.editions
            .where((edition) => edition.kind == EditionKind.audio)
            .single
            .files
            .first
            .itemId,
        'two',
      );
      expect(
        book.editions.where((edition) => edition.kind == EditionKind.text),
        hasLength(1),
      );
      await controller.separateEdition('two:source');
      expect(controller.books, hasLength(2));
      controller.checkInvariants();
    },
  );

  test(
    'a failed correction save leaves the previous visible correction intact',
    () async {
      await connectAndSelect();
      store.failWrites = true;
      await controller.correctBook(
        'book:one',
        const BookDetails(title: 'Not saved', author: 'Writer'),
      );
      expect(controller.books.single.title, 'The Orchard');
      expect(controller.message, contains('not saved'));
    },
  );

  test('a vault failure never leaves a signed-in session that only appears durable', () async {
    credentials.failWrites = true;
    await controller.connect('https://books.example', 'alice', 'password');
    expect(controller.session, isNull);
    expect(controller.message, contains('secure'));
  });

  test(
    'refresh cancellation does not discard a correction already being saved',
    () async {
      await connectAndSelect();
      store.gate = Completer();
      final correcting = controller.correctBook(
        'book:one',
        const BookDetails(title: 'Keep this correction', author: 'Writer'),
      );
      await Future<void>.delayed(Duration.zero);
      controller.cancel();
      store.gate!.complete();
      await correcting;
      expect(controller.books.single.title, 'Keep this correction');
    },
  );

  test('overlapping correction saves retain both decisions', () async {
    client.entries = [entry('one'), entry('two')];
    await connectAndSelect();
    store.gate = Completer();
    final first = controller.correctBook(
      'book:one',
      const BookDetails(title: 'First correction', author: 'Writer'),
    );
    final second = controller.correctBook(
      'book:two',
      const BookDetails(title: 'Second correction', author: 'Writer'),
    );
    store.gate!.complete();
    await Future.wait([first, second]);
    expect(
      controller.books.map((book) => book.title),
      containsAll(['First correction', 'Second correction']),
    );
  });

  test(
    'a new sign-in never exposes libraries whose access has been removed',
    () async {
      await connectAndSelect();
      await controller.signOut();
      client.views = [];
      await controller.connect('https://books.example', 'alice', 'password');
      expect(controller.books, isEmpty);
      expect(controller.accessBlocked, isTrue);
      expect(store.values, isNotEmpty);
    },
  );

  test(
    'an unreadable catalog does not discard successful secure sign-in',
    () async {
      store.failReads = true;
      await controller.connect('https://books.example', 'alice', 'password');
      expect(controller.session!.scope.userId, 'alice');
      expect(controller.libraries.single.id, 'books');
      expect(controller.books, isEmpty);
      expect(credentials.value!.scope.userId, 'alice');
    },
  );

  test(
    'an invalid account switch cannot restore the old token on restart',
    () async {
      await connectAndSelect();
      await controller.connect('http://untrusted.example', 'bob', 'password');
      expect(controller.session, isNull);
      expect(controller.books, isEmpty);
      expect(credentials.value, isNull);
      expect(store.values, isNotEmpty);
    },
  );

  test(
    'separating the first file preserves the chosen order of remaining files',
    () async {
      client.entries = [
        entry('one'),
        entry('two', track: 2),
        entry('three', track: 3),
      ];
      await connectAndSelect();
      await controller.linkBooks('book:two', 'book:one');
      await controller.linkBooks('book:three', 'book:one');
      await controller.combineAudio('book:one', [
        'one:source',
        'two:source',
        'three:source',
      ]);
      await controller.orderFiles('one:source', [
        'three:source',
        'one:source',
        'two:source',
      ]);
      await controller.separateEdition('one:source');
      expect(
        controller.books
            .firstWhere((book) => book.id == 'book:one')
            .editions
            .single
            .files
            .map((file) => file.itemId),
        ['three', 'two'],
      );
    },
  );
}
