import 'dart:async';
import 'dart:convert';

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
  Completer<void>? writeGate;
  Completer<void>? writeStarted;

  /// Holds each read until it completes, when a test sets it.
  Completer<void>? readGate;
  @override
  Future<JellyfinSession?> read() async {
    await readGate?.future;
    return value;
  }

  @override
  Future<void> write(JellyfinSession? session) async {
    if (writeStarted?.isCompleted == false) writeStarted!.complete();
    await writeGate?.future;
    if (failWrites) throw StateError('vault failure');
    value = session;
  }

  @override
  Future<String> deviceId() async => 'test-device';
}

class MemoryCatalogStore implements CatalogStore {
  final choices = <String, CatalogChoices>{};
  @override
  Future<CatalogChoices> readChoices(AccountScope scope) async {
    if (choices[scope.key] case final saved?) return saved;
    final text = values[scope.key];
    if (text != null) {
      try {
        final json = jsonDecode(text) as Map<String, dynamic>;
        if (json['version'] == 1 || json['version'] == 2) {
          return choices[scope.key] = CatalogChoices(
            edits: CatalogEdits.fromJson(json['edits'] as Map<String, dynamic>),
            hidden: json['version'] == 1
                ? {}
                : Set<String>.from(json['hidden'] as List),
          );
        }
      } on Exception {
        /* The real store retains malformed data. */
      }
    }
    return choices[scope.key] = CatalogChoices();
  }

  @override
  Future<void> writeChoices(AccountScope scope, CatalogChoices value) async {
    if (writeStarted case final started? when !started.isCompleted) {
      started.complete();
    }
    await gate?.future;
    if (failWrites) throw StateError('disk failure');
    choices[scope.key] = value;
  }

  /// The saved catalog text of each account, by account scope key.
  final values = <String, String>{};
  bool failWrites = false;
  bool failReads = false;
  Completer<void>? gate;

  /// Reports that a write reached storage, before [gate] lets it complete.
  Completer<void>? writeStarted;

  /// Holds each read until it completes, when a test sets it.
  Completer<void>? readGate;
  @override
  Future<String?> read(AccountScope scope) async {
    await readGate?.future;
    if (failReads) throw StateError('unreadable cache');
    return values[scope.key];
  }

  @override
  Future<void> write(AccountScope scope, String text) async {
    if (writeStarted case final started? when !started.isCompleted) {
      started.complete();
    }
    await gate?.future;
    if (failWrites) throw StateError('disk failure');
    values[scope.key] = text;
  }
}

class FixtureClient extends JellyfinClient {
  FixtureClient(super.server) : super(deviceId: 'test');
  List<CatalogEntry> entries = [entry('one')];
  List<BookLibrary> views = [const BookLibrary('books', 'Books')];
  CatalogFailure? failure;
  Completer<List<CatalogEntry>>? pendingCatalog;

  /// How many catalog reads reached this client.
  int catalogReads = 0;
  int validations = 0;
  Completer<JellyfinSession>? pendingSignIn;
  @override
  Future<JellyfinSession> signIn(String username, String password) async =>
      pendingSignIn?.future ?? account(username, server: server.toString());
  @override
  Future<JellyfinSession> validate(JellyfinSession session) async {
    validations++;
    if (failure != null) throw failure!;
    return session;
  }

  @override
  Future<List<BookLibrary>> libraries(JellyfinSession session) async {
    if (failure != null) throw failure!;
    return views;
  }

  /// The pages of the entries of the [shown] libraries.
  @override
  Future<CatalogPages> catalog(
    JellyfinSession session,
    Set<String> shown,
  ) async {
    catalogReads++;
    if (failure != null) throw failure!;
    final List<CatalogEntry> all = await pendingCatalog?.future ?? entries;
    return pagesOf([
      for (final each in all)
        if (shown.contains(each.libraryId)) each,
    ]);
  }
}

/// The catalog pages that Jellyfin sends for [entries]: the entries of each
/// library, in pages of [catalogPageSize].
CatalogPages pagesOf(List<CatalogEntry> entries) {
  final byLibrary = <String, List<CatalogEntry>>{};
  for (final each in entries) {
    byLibrary.putIfAbsent(each.libraryId, () => []).add(each);
  }
  return CatalogPages(
    libraries: [
      for (final MapEntry(key: id, value: items) in byLibrary.entries)
        (
          libraryId: id,
          total: items.length,
          pages: [
            for (var start = 0; start < items.length; start += catalogPageSize)
              utf8.encode(
                jsonEncode({
                  'Items': [
                    for (final item in items.skip(start).take(catalogPageSize))
                      item.json,
                  ],
                  'TotalRecordCount': items.length,
                  'StartIndex': start,
                }),
              ),
          ],
        ),
    ],
  );
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
  Future<void> signIn() =>
      controller.connect('https://books.example', 'alice', 'password');

  test(
    'known denial survives an offline restart until access succeeds',
    () async {
      await signIn();
      client.failure = const CatalogFailure(CatalogFailureKind.forbidden);
      await controller.refresh();
      final restarted = CatalogController(
        credentials: credentials,
        store: store,
        clientFactory: (server, device) => client,
      );
      addTearDown(restarted.dispose);
      await restarted.restore();
      expect(restarted.books, isEmpty);
      expect(restarted.accessBlocked, isTrue);
      client.failure = const CatalogFailure(CatalogFailureKind.unavailable);
      await restarted.refresh();
      expect(restarted.books, isEmpty);
      client.failure = null;
      await restarted.refresh();
      expect(restarted.books, hasLength(1));
    },
  );

  test(
    'refresh preserves a recording after its anchor file disappears',
    () async {
      client.entries = [
        entry('one'),
        entry('two', track: 2),
        entry('three', track: 3),
      ];
      await signIn();
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
      client.entries = [entry('two', track: 2), entry('three', track: 3)];
      await controller.refresh();
      expect(controller.books.single.editions, hasLength(1));
      expect(
        controller.books.single.editions.single.files.map(
          (file) => file.itemId,
        ),
        ['three', 'two'],
      );
    },
  );

  test(
    'linking into a separated book preserves chosen target details',
    () async {
      client.entries = [
        entry('apple', title: 'Apple'),
        entry('zebra', title: 'Zebra'),
      ];
      await signIn();
      await controller.separateEdition('zebra:source');
      final target = controller.books
          .firstWhere((book) => book.title == 'Zebra')
          .id;
      await controller.linkBooks('book:apple', target);
      expect(controller.books.single.title, 'Zebra');
      client.entries = client.entries.reversed.toList();
      await controller.refresh();
      expect(controller.books.single.title, 'Zebra');
    },
  );

  test(
    'a complete selected catalog is available after a fresh offline restart',
    () async {
      await signIn();
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
      await signIn();
      final signingOut = controller.signOut();
      expect(controller.books, isEmpty);
      expect(controller.session, isNull);
      await signingOut;
      expect(credentials.value, isNull);
      final scope = account('alice').scope;
      expect(
        CatalogCache.decode(scope, store.values[scope.key]!).entries,
        hasLength(1),
      );
    },
  );

  test(
    'another user never sees the previous account books or corrections',
    () async {
      await signIn();
      await controller.correctBook(
        controller.books.single.id,
        const BookDetails(title: 'Private correction', author: 'Alice'),
      );
      await controller.signOut();
      await controller.connect('https://books.example', 'bob', 'password');
      expect(controller.books.single.title, 'The Orchard');
      expect(
        (await store.readChoices(account('bob').scope)).edits.details,
        isEmpty,
      );
    },
  );

  test(
    'the same user name on a different server never restores another catalog',
    () async {
      await signIn();
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
      await signIn();
      final saved = store.values[account('alice').scope.key];
      client.failure = const CatalogFailure(CatalogFailureKind.incomplete);
      await controller.refresh(byUser: true);
      expect(controller.books, hasLength(1));
      expect(store.values[account('alice').scope.key], same(saved));
      expect(controller.message, contains('incomplete'));
    },
  );

  test('a stale refresh cannot repopulate a signed-out account', () async {
    await signIn();
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
      await signIn();
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

  test(
    'a rejected credential retains the local account and complete catalog',
    () async {
      await signIn();
      client.failure = const CatalogFailure(CatalogFailureKind.unauthorized);
      await controller.refresh();
      expect(controller.books, isNotEmpty);
      expect(credentials.value?.token, 'token-alice');
      expect(store.values, isNotEmpty);
    },
  );

  test(
    'a rejected credential stays suspended after restart and resume',
    () async {
      await signIn();
      client.failure = const CatalogFailure(CatalogFailureKind.unauthorized);
      await controller.refresh();
      final validations = client.validations;
      final restarted = CatalogController(
        credentials: credentials,
        store: store,
        clientFactory: (_, _) => client,
      );
      addTearDown(restarted.dispose);
      await restarted.restore();
      expect(restarted.books, isNotEmpty);
      expect(restarted.statusNotifier.value.reach, CatalogReach.signInExpired);
      await restarted.refresh();
      await restarted.resume();
      expect(client.validations, validations);
      restarted.checkInvariants();
    },
  );

  test(
    'cancelled replacement sign-in retains the account and ignores its answer',
    () async {
      await signIn();
      final books = controller.books;
      client.pendingSignIn = Completer();
      final connecting = controller.connect(
        'https://books.example',
        'bob',
        'password',
      );
      await pumpEventQueue();
      expect(controller.books, same(books));
      controller.cancel();
      client.pendingSignIn!.complete(account('bob'));
      await connecting;
      expect(controller.session?.scope.userId, 'alice');
      expect(credentials.value?.token, 'token-alice');
      expect(controller.books, same(books));
    },
  );

  test('cancelling an in-flight secure replacement preserves the prior account on restart', () async {
    await signIn();
    credentials.writeGate = Completer();
    credentials.writeStarted = Completer();
    final connecting = controller.connect(
      'https://books.example',
      'bob',
      'password',
    );
    await credentials.writeStarted!.future;
    controller.cancel();
    credentials.writeGate!.complete();
    await connecting;
    await controller.restore();
    expect(controller.session!.scope.userId, 'alice');
    expect(credentials.value!.scope.userId, 'alice');
    expect(controller.books, isNotEmpty);
  });

  test(
    'a rejection during local catalog restore does not cancel the restore',
    () async {
      await signIn();
      store.readGate = Completer();
      final restoring = controller.restore();
      await pumpEventQueue();
      expect(controller.session, isNotNull);
      controller.session!.rejectCredential();
      store.readGate!.complete();
      await restoring;
      expect(controller.books, isNotEmpty);
      expect(controller.session!.needsSignIn, isTrue);
    },
  );

  test(
    'rejection of the old token does not cancel replacement authentication',
    () async {
      await signIn();
      final previous = controller.session!;
      client.pendingSignIn = Completer();
      final connecting = controller.connect(
        'https://books.example',
        'alice',
        'password',
      );
      await pumpEventQueue();
      previous.rejectCredential();
      client.pendingSignIn!.complete(
        JellyfinSession(
          scope: previous.scope,
          token: 'renewed',
          username: 'alice',
          canDownload: true,
        ),
      );
      await connecting;
      expect(controller.session!.token, 'renewed');
      expect(controller.verified, isTrue);
      expect(credentials.value!.token, 'renewed');
    },
  );

  test(
    'obsolete credential rejection cannot change its replacement account',
    () async {
      await signIn();
      final obsolete = controller.session!;
      await controller.connect('https://books.example', 'bob', 'password');
      obsolete.rejectCredential();
      await pumpEventQueue();
      expect(controller.session!.scope.userId, 'bob');
      expect(controller.verified, isTrue);
      expect(credentials.value!.scope.userId, 'bob');
      expect(controller.books, isNotEmpty);
      controller.checkInvariants();
    },
  );

  test('failed replacement sign-in preserves the rejected account', () async {
    await signIn();
    client.failure = const CatalogFailure(CatalogFailureKind.unauthorized);
    await controller.refresh();
    client.pendingSignIn = Completer();
    final connecting = controller.connect(
      'https://books.example',
      'bob',
      'wrong',
    );
    await pumpEventQueue();
    client.pendingSignIn!.completeError(
      const CatalogFailure(CatalogFailureKind.invalidCredentials),
    );
    await connecting;
    expect(controller.session?.scope.userId, 'alice');
    expect(credentials.value?.token, 'token-alice');
    expect(controller.statusNotifier.value.reach, CatalogReach.signInExpired);
    expect(controller.books, isNotEmpty);
  });

  test(
    'forbidden catalog access hides books but does not destroy offline records',
    () async {
      await signIn();
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
      await signIn();
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
      await signIn();
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
      await signIn();
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
    await signIn();
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

  test('a new sign-in never exposes libraries that the account can no longer '
      'read', () async {
    await signIn();
    await controller.signOut();
    client.views = [];
    await controller.connect('https://books.example', 'alice', 'password');
    expect(controller.books, isEmpty);
    expect(controller.libraries, isEmpty);
    expect(store.values, isNotEmpty);
  });

  test('same-account sign-in keeps an unreadable restored catalog for explicit refresh', () async {
    await signIn();
    final key = controller.session!.scope.key;
    store.values[key] = 'unreadable catalog';
    await controller.restore();
    expect(controller.books, isEmpty);
    await signIn();
    expect(controller.session!.scope.userId, 'alice');
    expect(store.values[key], 'unreadable catalog');
    expect(controller.message, contains('could not be read'));
  });

  test(
    'an unreadable catalog does not discard successful secure sign-in',
    () async {
      store.failReads = true;
      await controller.connect('https://books.example', 'alice', 'password');
      expect(controller.session!.scope.userId, 'alice');
      expect(controller.libraries.single.id, 'books');
      expect(controller.books, isEmpty);
      expect(controller.message, contains('could not be read'));
      expect(credentials.value!.scope.userId, 'alice');
    },
  );

  test('an invalid account switch keeps the current local account', () async {
    await signIn();
    await controller.connect('http://untrusted.example', 'bob', 'password');
    expect(controller.session?.scope.userId, 'alice');
    expect(controller.books, isNotEmpty);
    expect(credentials.value?.token, 'token-alice');
    expect(store.values, isNotEmpty);
  });

  test(
    'separating the first file preserves the chosen order of remaining files',
    () async {
      client.entries = [
        entry('one'),
        entry('two', track: 2),
        entry('three', track: 3),
      ];
      await signIn();
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

  group('a restore at launch', () {
    late CatalogController restarted;
    setUp(() async {
      await signIn();
      restarted = CatalogController(
        credentials: credentials,
        store: store,
        clientFactory: (server, device) => client,
      );
    });
    tearDown(() => restarted.dispose());

    test('says that the account is not known yet until the credentials are '
        'read', () async {
      credentials.readGate = Completer<void>();
      final restoring = restarted.restore();
      await pumpEventQueue();
      expect(restarted.accountNotifier.value.session, isNull);
      expect(restarted.accountNotifier.value.restoring, isTrue);
      credentials.readGate!.complete();
      await restoring;
      expect(restarted.accountNotifier.value.restoring, isFalse);
    });

    test('publishes the saved account as soon as its credentials are read, '
        'while the saved library still loads', () async {
      store.readGate = Completer<void>();
      final restoring = restarted.restore();
      await pumpEventQueue();
      final account = restarted.accountNotifier.value;
      expect(account.session?.username, 'alice');
      expect(account.restoring, isTrue);
      expect(restarted.libraryNotifier.value.books, isEmpty);
      store.readGate!.complete();
      await restoring;
      expect(restarted.accountNotifier.value.restoring, isFalse);
      expect(restarted.accountNotifier.value.hidden, isEmpty);
      expect(restarted.libraryNotifier.value.books, hasLength(1));
      restarted.checkInvariants();
    });

    test('ends as signed out without saved credentials', () async {
      credentials.value = null;
      await restarted.restore();
      expect(restarted.accountNotifier.value.session, isNull);
      expect(restarted.accountNotifier.value.restoring, isFalse);
    });

    test(
      'keeps the saved account when its saved library cannot be read',
      () async {
        store.failReads = true;
        await restarted.restore();
        expect(restarted.accountNotifier.value.session?.username, 'alice');
        expect(restarted.accountNotifier.value.restoring, isFalse);
        expect(restarted.statusNotifier.value.message, isNotNull);
      },
    );
  });
}
