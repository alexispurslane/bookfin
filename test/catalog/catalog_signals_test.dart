import 'dart:async';
import 'dart:isolate';

import 'package:bookfin/catalog/controller.dart';
import 'package:bookfin/catalog/jellyfin.dart';
import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/catalog/store.dart';
import 'package:bookfin/catalog/transport.dart';
import 'package:flutter_test/flutter_test.dart';

import 'controller_test.dart'
    show FixtureClient, MemoryCatalogStore, MemoryCredentials, account;
import 'model_test.dart' show entry;

/// Runs [work] in a new isolate and reports, through [reports], the name of
/// that isolate and how many times it built books. A top-level function, so
/// the closure that crosses to the isolate holds only these three values.
Future<R> _recordingHop<M, R>(SendPort reports, R Function(M) work, M input) =>
    Isolate.run(() {
      final before = booksBuilt;
      final result = work(input);
      reports.send((Isolate.current.debugName, booksBuilt - before));
      return result;
    }, debugName: 'catalog worker');

/// A library large enough that the catalog builds it in another isolate.
List<CatalogEntry> _largeLibrary({String prefix = 'Book'}) => [
  for (var index = 0; index < 40; index++)
    entry('item$index', title: '$prefix $index', source: 'source$index'),
];

/// Whether [input], the value that a hop copies into its worker, holds
/// catalog entries. A record shows its fields only through its text, so a
/// record that names an entry or a cache counts as holding entries.
bool _carriesEntries(Object? input) => switch (input) {
  CatalogCache(:final entries) => entries.isNotEmpty,
  CatalogEntry() => true,
  Iterable() => input.any(_carriesEntries),
  Record() => '$input'.contains(RegExp('CatalogEntry|CatalogCache')),
  _ => false,
};

/// Answers with one book library, `books`, whose one catalog page holds
/// [items], and with no collections.
class _PageTransport implements JsonTransport {
  _PageTransport(this.items);
  final List<Map<String, dynamic>> items;
  @override
  Future<Map<String, dynamic>> send(
    Uri uri, {
    required String method,
    required Map<String, String> headers,
    Map<String, dynamic>? body,
  }) async => switch (uri.pathSegments.last) {
    'UserViews' => {
      'Items': [
        {'Id': 'books', 'Name': 'Books', 'CollectionType': 'books'},
      ],
    },
    _ when uri.queryParameters['parentId'] == 'books' => {
      'Items': items,
      'TotalRecordCount': items.length,
      'StartIndex': 0,
    },
    _ => {'Items': <Object>[]},
  };
  @override
  void close() {}
}

/// A client whose catalog pages come from Jellyfin's JSON, so the catalog
/// builds its entries from responses, as with a real server.
class _PagedClient extends FixtureClient {
  _PagedClient(super.server, List<Map<String, dynamic>> items)
    : _pages = JellyfinClient(
        server,
        deviceId: 'test',
        transport: _PageTransport(items),
      );
  final JellyfinClient _pages;
  @override
  Future<List<CatalogEntry>> catalog(
    JellyfinSession session,
    Set<String> selected,
  ) => _pages.catalog(session, selected);
}

void main() {
  late MemoryCredentials credentials;
  late MemoryCatalogStore store;
  late FixtureClient client;
  late CatalogController controller;
  late ReceivePort reports;
  late List<(String?, int)> builds;

  /// Whether each hop copied entries into its worker, in hop order.
  late List<bool> crossings;

  CatalogController newController() => CatalogController(
    credentials: credentials,
    store: store,
    clientFactory: (server, device) => client,
    hop: <M, R>(R Function(M) work, M input) {
      crossings.add(_carriesEntries(input));
      return _recordingHop(reports.sendPort, work, input);
    },
  );

  /// Waits until the worker reports of earlier hops have arrived.
  Future<void> settleReports() => Future<void>.delayed(Duration.zero);

  setUp(() {
    credentials = MemoryCredentials();
    store = MemoryCatalogStore();
    client = FixtureClient(Uri.parse('https://books.example'));
    builds = [];
    crossings = [];
    reports = ReceivePort()
      ..listen((report) => builds.add(report as (String?, int)));
    controller = newController();
  });
  tearDown(() {
    controller.dispose();
    client.close();
    reports.close();
  });

  Future<void> connectAndSelect() async {
    await controller.connect('https://books.example', 'alice', 'password');
    await controller.refresh(selected: {'books'});
  }

  group('the library signal', () {
    test(
      'a refresh that changes no book notifies status and not library',
      () async {
        client.entries = _largeLibrary();
        await connectAndSelect();
        final published = controller.libraryNotifier.value;
        var libraryNotices = 0, statusNotices = 0;
        controller.libraryNotifier.addListener(() => libraryNotices++);
        controller.statusNotifier.addListener(() => statusNotices++);
        await controller.refresh();
        expect(statusNotices, greaterThan(0));
        expect(libraryNotices, 0);
        expect(controller.libraryNotifier.value, same(published));
        expect(controller.books, same(published.books));
        controller.checkInvariants();
      },
    );

    test('a refresh that changes a book publishes the new books', () async {
      await connectAndSelect();
      var libraryNotices = 0;
      controller.libraryNotifier.addListener(() => libraryNotices++);
      client.entries = [entry('one', title: 'The River')];
      await controller.refresh();
      expect(libraryNotices, 1);
      expect(controller.libraryNotifier.value.books.single.title, 'The River');
      expect(controller.books, same(controller.libraryNotifier.value.books));
      controller.checkInvariants();
    });

    test('a correction publishes the corrected books', () async {
      await connectAndSelect();
      var libraryNotices = 0;
      controller.libraryNotifier.addListener(() => libraryNotices++);
      await controller.correctBook(
        'book:one',
        const BookDetails(title: 'Corrected', author: 'Writer'),
      );
      expect(libraryNotices, 1);
      expect(controller.libraryNotifier.value.books.single.title, 'Corrected');
    });

    test('signing out and losing access publish the empty library', () async {
      await connectAndSelect();
      client.failure = const CatalogFailure(CatalogFailureKind.forbidden);
      await controller.refresh();
      expect(controller.libraryNotifier.value.books, isEmpty);
      client.failure = null;
      await controller.refresh();
      expect(controller.libraryNotifier.value.books, hasLength(1));
      await controller.signOut();
      expect(controller.libraryNotifier.value.books, isEmpty);
      controller.checkInvariants();
    });
  });

  group('the account signal', () {
    test('changes on sign-in and sign-out, and not on a refresh of the same account', () async {
      final accounts = <CatalogAccount>[];
      controller.accountNotifier.addListener(
        () => accounts.add(controller.accountNotifier.value),
      );
      await connectAndSelect();
      final signedIn = accounts.length;
      expect(controller.accountNotifier.value.session!.username, 'alice');
      expect(controller.accountNotifier.value.selected, {'books'});
      expect(controller.accountNotifier.value.libraries.single.id, 'books');
      await controller.refresh();
      expect(accounts, hasLength(signedIn));
      await controller.signOut();
      expect(accounts.last.session, isNull);
    });

    test('says when access is blocked', () async {
      await connectAndSelect();
      client.failure = const CatalogFailure(CatalogFailureKind.forbidden);
      await controller.refresh();
      expect(controller.accountNotifier.value.accessBlocked, isTrue);
    });
  });

  group('the status signal', () {
    test('is refreshing while a refresh runs, and only then', () async {
      await connectAndSelect();
      expect(controller.statusNotifier.value.refreshing, isFalse);
      client.pendingCatalog = Completer();
      final refreshing = controller.refresh();
      expect(controller.statusNotifier.value.refreshing, isTrue);
      client.pendingCatalog!.complete([entry('one')]);
      await refreshing;
      expect(controller.statusNotifier.value.refreshing, isFalse);
    });

    test('a restore from storage is not a refresh', () async {
      await connectAndSelect();
      final refreshing = <bool>[];
      final restarted = newController();
      addTearDown(restarted.dispose);
      restarted.statusNotifier.addListener(
        () => refreshing.add(restarted.statusNotifier.value.refreshing),
      );
      await restarted.restore();
      expect(refreshing, everyElement(isFalse));
      expect(restarted.statusNotifier.value.reach, CatalogReach.unknown);
    });

    test(
      'a refresh that reaches Jellyfin reports that Jellyfin is reachable',
      () async {
        await connectAndSelect();
        expect(controller.statusNotifier.value.reach, CatalogReach.reached);
      },
    );

    test('a refresh that cannot reach Jellyfin reports it, and a later successful refresh clears it', () async {
      await connectAndSelect();
      client.failure = const CatalogFailure(CatalogFailureKind.unavailable);
      await controller.refresh();
      expect(controller.statusNotifier.value.reach, CatalogReach.unreachable);
      expect(controller.books, hasLength(1));
      client.failure = null;
      await controller.refresh();
      expect(controller.statusNotifier.value.reach, CatalogReach.reached);
    });

    test('Jellyfin stays unreachable while a retry runs', () async {
      await connectAndSelect();
      client.failure = const CatalogFailure(CatalogFailureKind.unavailable);
      await controller.refresh();
      client.failure = null;
      client.pendingCatalog = Completer();
      final retry = controller.refresh();
      expect(controller.statusNotifier.value.refreshing, isTrue);
      expect(controller.statusNotifier.value.reach, CatalogReach.unreachable);
      client.pendingCatalog!.complete([entry('one')]);
      await retry;
      expect(controller.statusNotifier.value.reach, CatalogReach.reached);
    });

    test('a cancelled retry leaves Jellyfin unreachable', () async {
      await connectAndSelect();
      client.failure = const CatalogFailure(CatalogFailureKind.unavailable);
      await controller.refresh();
      client.failure = null;
      client.pendingCatalog = Completer();
      final retry = controller.refresh();
      controller.cancel();
      client.pendingCatalog!.complete([entry('one')]);
      await retry;
      expect(controller.statusNotifier.value.reach, CatalogReach.unreachable);
    });

    test(
      'an expired sign-in is reported as expired, not as unreachable',
      () async {
        await connectAndSelect();
        client.failure = const CatalogFailure(CatalogFailureKind.unauthorized);
        await controller.refresh();
        final status = controller.statusNotifier.value;
        expect(status.reach, CatalogReach.signInExpired);
        expect(status.message, contains('expired'));
        expect(controller.accountNotifier.value.session, isNull);
      },
    );

    test('revoked access is reported as revoked, not as unreachable', () async {
      await connectAndSelect();
      client.failure = const CatalogFailure(CatalogFailureKind.forbidden);
      await controller.refresh();
      final status = controller.statusNotifier.value;
      expect(status.reach, CatalogReach.accessRevoked);
      expect(status.message, 'This account does not have access.');
    });

    test('a saved denial is revoked access after a restart', () async {
      await connectAndSelect();
      client.failure = const CatalogFailure(CatalogFailureKind.forbidden);
      await controller.refresh();
      final restarted = newController();
      addTearDown(restarted.dispose);
      await restarted.restore();
      expect(restarted.statusNotifier.value.reach, CatalogReach.accessRevoked);
    });

    test('a refresh that Jellyfin answers with an incomplete catalog still reaches Jellyfin', () async {
      await connectAndSelect();
      client.failure = const CatalogFailure(CatalogFailureKind.unavailable);
      await controller.refresh();
      client.failure = const CatalogFailure(CatalogFailureKind.incomplete);
      await controller.refresh();
      expect(controller.statusNotifier.value.reach, CatalogReach.reached);
      expect(controller.statusNotifier.value.message, contains('incomplete'));
    });

    test('a sign-in that cannot reach Jellyfin reports it', () async {
      client.failure = const CatalogFailure(CatalogFailureKind.unavailable);
      await controller.connect('https://books.example', 'alice', 'password');
      expect(controller.statusNotifier.value.reach, CatalogReach.unreachable);
    });

    test('signing out forgets that Jellyfin was unreachable', () async {
      await connectAndSelect();
      client.failure = const CatalogFailure(CatalogFailureKind.unavailable);
      await controller.refresh();
      await controller.signOut();
      expect(controller.statusNotifier.value.reach, CatalogReach.unknown);
    });
  });

  group('the build of the books', () {
    test('a restore builds the books once, in another isolate', () async {
      client.entries = _largeLibrary();
      await connectAndSelect();
      final restarted = newController();
      addTearDown(restarted.dispose);
      await settleReports();
      builds.clear();
      final here = booksBuilt;
      await restarted.restore();
      await settleReports();
      expect(booksBuilt, here);
      expect(builds, [('catalog worker', 1)]);
      expect(restarted.books, hasLength(40));
      restarted.checkInvariants();
    });

    test('a refresh builds the books once, in another isolate', () async {
      await connectAndSelect();
      client.entries = _largeLibrary();
      await settleReports();
      builds.clear();
      final here = booksBuilt;
      await controller.refresh();
      await settleReports();
      expect(booksBuilt, here);
      expect(builds, [('catalog worker', 1)]);
      expect(controller.books, hasLength(40));
    });

    test('a correction builds the books once, in another isolate', () async {
      client.entries = _largeLibrary();
      await connectAndSelect();
      await settleReports();
      builds.clear();
      final here = booksBuilt;
      await controller.correctBook(
        'book:item1',
        const BookDetails(title: 'Corrected', author: 'Writer'),
      );
      await settleReports();
      expect(booksBuilt, here);
      expect(builds, [('catalog worker', 1)]);
      expect(controller.books.map((book) => book.title), contains('Corrected'));
    });

    test(
      'a small library builds here, because a hop costs more than its build',
      () async {
        await connectAndSelect();
        await settleReports();
        expect(builds, isEmpty);
        expect(controller.books, hasLength(1));
      },
    );
  });

  group('what crosses to the worker', () {
    test(
      'a refresh hands the worker Jellyfin\'s responses, not built entries',
      () async {
        client = _PagedClient(Uri.parse('https://books.example'), [
          for (final value in _largeLibrary()) {...value.json},
        ]);
        controller.dispose();
        controller = newController();
        await connectAndSelect();
        await settleReports();
        expect(crossings, [false]);
        expect(builds, [('catalog worker', 1)]);
        expect(controller.books, hasLength(40));
      },
      skip:
          'ta-7oe6: the transport returns decoded maps on the UI isolate, so '
          'the entries cross until it hands the worker page bytes.',
    );

    test(
      'a correction hands the worker the saved text, not the entries',
      () async {
        client.entries = _largeLibrary();
        await connectAndSelect();
        crossings.clear();
        await controller.correctBook(
          'book:item1',
          const BookDetails(title: 'Corrected', author: 'Writer'),
        );
        expect(crossings, [false]);
        expect(
          controller.books.map((book) => book.title),
          contains('Corrected'),
        );
        final saved = CatalogCache.decode(
          account('alice').scope,
          store.values[account('alice').scope.key]!,
        );
        expect(saved.entries, hasLength(40));
        expect(saved.edits.details['book:item1']!.title, 'Corrected');
        controller.checkInvariants();
      },
    );

    test(
      'a saved denial hands the worker the saved text, not the entries',
      () async {
        client.entries = _largeLibrary();
        await connectAndSelect();
        crossings.clear();
        client.failure = const CatalogFailure(CatalogFailureKind.forbidden);
        await controller.refresh();
        expect(crossings, [false]);
        expect(
          controller.statusNotifier.value.reach,
          CatalogReach.accessRevoked,
        );
        final saved = CatalogCache.decode(
          account('alice').scope,
          store.values[account('alice').scope.key]!,
        );
        expect(saved.accessBlocked, isTrue);
        expect(saved.entries, hasLength(40));
        controller.checkInvariants();
      },
    );

    test('corrections in a row each start from the last saved one', () async {
      client.entries = _largeLibrary();
      await connectAndSelect();
      await Future.wait([
        controller.correctBook(
          'book:item1',
          const BookDetails(title: 'First', author: 'Writer'),
        ),
        controller.correctBook(
          'book:item2',
          const BookDetails(title: 'Second', author: 'Writer'),
        ),
      ]);
      expect(
        controller.books.map((book) => book.title),
        containsAll(['First', 'Second']),
      );
      final restarted = newController();
      addTearDown(restarted.dispose);
      await restarted.restore();
      expect(
        restarted.books.map((book) => book.title),
        containsAll(['First', 'Second']),
      );
    });

    test(
      'access that returns after a saved denial brings the books back',
      () async {
        client.entries = _largeLibrary();
        await connectAndSelect();
        client.failure = const CatalogFailure(CatalogFailureKind.forbidden);
        await controller.refresh();
        expect(controller.books, isEmpty);
        client.failure = null;
        await controller.refresh();
        expect(controller.books, hasLength(40));
        expect(controller.statusNotifier.value.reach, CatalogReach.reached);
        controller.checkInvariants();
      },
    );
  });

  group('a corrupt saved catalog', () {
    for (final (size, text) in [
      ('small', '{"version": 1, "entries": ['),
      ('large', '{"version": 1, "entries": [${'"x", ' * 10000}'),
    ]) {
      test(
        'a $size corrupt catalog gives the same message and keeps the account signed in',
        () async {
          credentials.value = account('alice');
          store.values[account('alice').scope.key] = text;
          await controller.restore();
          expect(controller.session!.scope.userId, 'alice');
          expect(controller.books, isEmpty);
          expect(
            controller.message,
            'Saved account data could not be read. Sign in again if needed.',
          );
          expect(store.values[account('alice').scope.key], text);
        },
      );
    }

    test('a corrupt catalog at sign-in keeps the sign-in', () async {
      store.values[account('alice').scope.key] = 'not a catalog';
      await controller.connect('https://books.example', 'alice', 'password');
      expect(controller.session!.scope.userId, 'alice');
      expect(controller.books, isEmpty);
    });
  });
}
