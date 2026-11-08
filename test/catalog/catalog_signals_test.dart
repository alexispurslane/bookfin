import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

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

/// Answers with one book library, `books`, whose catalog holds [items], and
/// with no collections. A catalog request gets the items of its start index
/// and limit. A page reports [pageTotal] items, or the count of [items].
class _PageTransport implements JsonTransport {
  _PageTransport(this.items, {this.pageTotal});
  final List<Map<String, dynamic>> items;
  final int? pageTotal;
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
      'Items': items
          .skip(int.parse(uri.queryParameters['startIndex']!))
          .take(int.parse(uri.queryParameters['limit']!))
          .toList(),
      'TotalRecordCount': items.length,
      'StartIndex': int.parse(uri.queryParameters['startIndex']!),
    },
    _ => {'Items': <Object>[]},
  };
  @override
  Future<Uint8List> fetchBody(
    Uri uri, {
    required String method,
    required Map<String, String> headers,
    Map<String, dynamic>? body,
  }) async => utf8.encode(
    jsonEncode({
      ...await send(uri, method: method, headers: headers, body: body),
      'TotalRecordCount': ?pageTotal,
    }),
  );
  @override
  void close() {}
}

/// A client whose catalog pages come from Jellyfin's JSON, so the catalog
/// builds its entries from responses, as with a real server.
class _PagedClient extends FixtureClient {
  _PagedClient(super.server, List<Map<String, dynamic>> items, {int? pageTotal})
    : _pages = JellyfinClient(
        server,
        deviceId: 'test',
        transport: _PageTransport(items, pageTotal: pageTotal),
      );
  final JellyfinClient _pages;
  @override
  Future<CatalogPages> catalog(JellyfinSession session, Set<String> selected) =>
      _pages.catalog(session, selected);
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
      await controller.refresh(byUser: true);
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

  group('what a refresh tells the person', () {
    String? message() => controller.statusNotifier.value.message;

    test(
      'a refresh that cannot reach Jellyfin leaves the telling to the reach',
      () async {
        await connectAndSelect();
        client.failure = const CatalogFailure(CatalogFailureKind.unavailable);
        await controller.refresh();
        expect(message(), isNull);
        await controller.refresh(byUser: true);
        expect(message(), isNull);
        expect(controller.statusNotifier.value.reach, CatalogReach.unreachable);
      },
    );

    test('a background refresh that Jellyfin answers with an incomplete catalog says nothing', () async {
      await connectAndSelect();
      client.failure = const CatalogFailure(CatalogFailureKind.incomplete);
      await controller.refresh();
      expect(message(), isNull);
    });

    test(
      'a background refresh whose catalog cannot be saved says nothing',
      () async {
        await connectAndSelect();
        store.failWrites = true;
        client.entries = [entry('two')];
        await controller.refresh();
        expect(message(), isNull);
      },
    );

    test('a refresh that the person asked for reports a catalog that cannot be saved', () async {
      await connectAndSelect();
      store.failWrites = true;
      client.entries = [entry('two')];
      await controller.refresh(byUser: true);
      expect(message(), contains('not saved'));
    });

    test('a background refresh still reports an expired sign-in and revoked access', () async {
      await connectAndSelect();
      client.failure = const CatalogFailure(CatalogFailureKind.forbidden);
      await controller.refresh();
      expect(message(), 'This account does not have access.');
      client.failure = const CatalogFailure(CatalogFailureKind.unauthorized);
      await controller.refresh();
      expect(message(), contains('expired'));
    });

    test('a sign-in that cannot reach Jellyfin asks to check the address and the connection', () async {
      client.pendingSignIn = Completer();
      final signingIn = controller.connect(
        'https://books.example',
        'alice',
        'password',
      );
      await pumpEventQueue();
      client.pendingSignIn!.completeError(
        const CatalogFailure(CatalogFailureKind.unavailable),
      );
      await signingIn;
      expect(controller.session, isNull);
      expect(
        message(),
        'Cannot reach Jellyfin. Check the server address and your connection.',
      );
    });
  });

  group('a refresh asked for while another runs', () {
    String? message() => controller.statusNotifier.value.message;
    const incomplete = CatalogFailure(CatalogFailureKind.incomplete);

    test('joins a background refresh and reports its failure after Jellyfin answered', () async {
      await connectAndSelect();
      client.pendingCatalog = Completer();
      final background = controller.refresh();
      await pumpEventQueue();
      final asked = controller.refresh(byUser: true);
      client.pendingCatalog!.completeError(incomplete);
      await Future.wait([background, asked]);
      expect(message(), incomplete.message);
      expect(controller.statusNotifier.value.reach, CatalogReach.reached);
      expect(controller.statusNotifier.value.verified, isFalse);
      expect(controller.books, hasLength(1));
    });

    test('starts no second request to Jellyfin', () async {
      await connectAndSelect();
      final before = client.catalogReads;
      client.pendingCatalog = Completer();
      final background = controller.refresh();
      await pumpEventQueue();
      var askedEnded = false;
      final asked = controller
          .refresh(byUser: true)
          .whenComplete(() => askedEnded = true);
      await pumpEventQueue();
      expect(askedEnded, isFalse);
      client.pendingCatalog!.complete([entry('two', title: 'The River')]);
      await Future.wait([background, asked]);
      expect(client.catalogReads, before + 1);
      expect(controller.books.single.title, 'The River');
      expect(controller.statusNotifier.value.verified, isTrue);
    });

    test('a background refresh that joins one the person asked for keeps it reported', () async {
      await connectAndSelect();
      client.pendingCatalog = Completer();
      final asked = controller.refresh(byUser: true);
      await pumpEventQueue();
      final background = controller.refresh();
      client.pendingCatalog!.completeError(incomplete);
      await Future.wait([asked, background]);
      expect(message(), incomplete.message);
    });

    test('a background refresh that nobody asked about stays silent', () async {
      await connectAndSelect();
      client.pendingCatalog = Completer();
      final first = controller.refresh();
      await pumpEventQueue();
      final second = controller.refresh();
      client.pendingCatalog!.completeError(incomplete);
      await Future.wait([first, second]);
      expect(message(), isNull);
    });

    test('a refresh of another selection replaces the running one', () async {
      client.views = [
        const BookLibrary('books', 'Books'),
        const BookLibrary('more', 'More'),
      ];
      await connectAndSelect();
      final before = client.catalogReads;
      final pending = client.pendingCatalog = Completer();
      final background = controller.refresh();
      await pumpEventQueue();
      client.pendingCatalog = null;
      await controller.refresh(selected: {'books', 'more'}, byUser: true);
      pending.complete([entry('late', title: 'Late')]);
      await background;
      expect(controller.books.single.title, isNot('Late'));
      expect(client.catalogReads, before + 2);
      expect(controller.accountNotifier.value.selected, {'books', 'more'});
      expect(controller.statusNotifier.value.verified, isTrue);
    });

    test('a refresh asked for during a restore runs after it, from the restored catalog', () async {
      await connectAndSelect();
      final restarted = newController();
      addTearDown(restarted.dispose);
      store.readGate = Completer();
      final restoring = restarted.restore();
      await pumpEventQueue();
      client.failure = incomplete;
      final asked = restarted.refresh(byUser: true);
      store.readGate!.complete();
      await Future.wait([restoring, asked]);
      expect(restarted.statusNotifier.value.message, incomplete.message);
      expect(restarted.books, hasLength(1));
    });
  });

  group('whether the last sign-in or refresh succeeded', () {
    bool verified() => controller.statusNotifier.value.verified;

    test('a sign-in that Jellyfin accepts succeeded', () async {
      await controller.connect('https://books.example', 'alice', 'password');
      expect(verified(), isTrue);
    });

    test(
      'a refresh has not succeeded while it runs, and has when it ends',
      () async {
        await connectAndSelect();
        client.pendingCatalog = Completer();
        final refreshing = controller.refresh();
        expect(verified(), isFalse);
        client.pendingCatalog!.complete([entry('one')]);
        await refreshing;
        expect(verified(), isTrue);
      },
    );

    test('a restore from storage has not reached Jellyfin, so it has not succeeded', () async {
      await connectAndSelect();
      final restarted = newController();
      addTearDown(restarted.dispose);
      await restarted.restore();
      expect(restarted.books, hasLength(1));
      expect(restarted.statusNotifier.value.verified, isFalse);
    });

    test('a refresh that cannot reach Jellyfin did not succeed', () async {
      await connectAndSelect();
      client.failure = const CatalogFailure(CatalogFailureKind.unavailable);
      await controller.refresh();
      expect(verified(), isFalse);
    });

    test('an expired sign-in did not succeed', () async {
      await connectAndSelect();
      client.failure = const CatalogFailure(CatalogFailureKind.unauthorized);
      await controller.refresh();
      expect(verified(), isFalse);
    });

    test('revoked access did not succeed', () async {
      await connectAndSelect();
      client.failure = const CatalogFailure(CatalogFailureKind.forbidden);
      await controller.refresh();
      expect(verified(), isFalse);
    });

    test('signing out forgets the last success', () async {
      await connectAndSelect();
      await controller.signOut();
      expect(verified(), isFalse);
    });

    test('a cancelled refresh did not succeed', () async {
      await connectAndSelect();
      client.pendingCatalog = Completer();
      final refreshing = controller.refresh();
      controller.cancel();
      client.pendingCatalog!.complete([entry('one')]);
      await refreshing;
      expect(verified(), isFalse);
    });

    test('a correction after a refresh keeps the refresh a success', () async {
      await connectAndSelect();
      await controller.correctBook(
        'book:one',
        const BookDetails(title: 'Corrected', author: 'Writer'),
      );
      expect(controller.books.single.title, 'Corrected');
      expect(verified(), isTrue);
    });

    test(
      'a correction that cannot be saved keeps the refresh a success',
      () async {
        await connectAndSelect();
        store.failWrites = true;
        await controller.correctBook(
          'book:one',
          const BookDetails(title: 'Corrected', author: 'Writer'),
        );
        expect(controller.statusNotifier.value.message, contains('correction'));
        expect(verified(), isTrue);
      },
    );

    // In the next two, Jellyfin answered, the refresh ended, and it still
    // failed. So the reach and the refresh state cannot tell a success.
    test('a refresh that Jellyfin answers with an incomplete catalog reached Jellyfin and did not succeed', () async {
      await connectAndSelect();
      client.failure = const CatalogFailure(CatalogFailureKind.incomplete);
      await controller.refresh();
      final status = controller.statusNotifier.value;
      expect((status.refreshing, status.reach), (false, CatalogReach.reached));
      expect(status.verified, isFalse);
    });

    test('a refresh whose catalog cannot be saved reached Jellyfin and did not succeed', () async {
      await connectAndSelect();
      store.failWrites = true;
      await controller.refresh();
      final status = controller.statusNotifier.value;
      expect((status.refreshing, status.reach), (false, CatalogReach.reached));
      expect(status.verified, isFalse);
      expect(controller.books, hasLength(1));
    });

    test(
      'the status and the catalog agree on success at every status notice',
      () async {
        final seen = <(bool, bool)>[];
        // A notifier reports an error that its listener throws instead of
        // failing the test, so the listener keeps the broken invariants.
        final broken = <Object>[];
        controller.statusNotifier.addListener(() {
          seen.add((verified(), controller.verified));
          try {
            controller.checkInvariants();
          } on StateError catch (error) {
            broken.add(error);
          }
        });
        await connectAndSelect();
        await controller.correctBook(
          'book:one',
          const BookDetails(title: 'Corrected', author: 'Writer'),
        );
        client.failure = const CatalogFailure(CatalogFailureKind.unavailable);
        await controller.refresh();
        client.failure = null;
        await controller.refresh();
        client.failure = const CatalogFailure(CatalogFailureKind.forbidden);
        await controller.refresh();
        await controller.signOut();
        client.failure = null;
        await controller.connect('https://books.example', 'alice', 'password');
        client.failure = const CatalogFailure(CatalogFailureKind.unauthorized);
        await controller.refresh();
        expect(
          seen,
          everyElement(predicate<(bool, bool)>((s) => s.$1 == s.$2)),
        );
        expect(seen.map((s) => s.$1), containsAllInOrder([true, false, true]));
        expect(broken, isEmpty);
      },
    );
  });

  group('a sign-in over a saved denial', () {
    /// Signs in, selects the book library, corrects its book, has Jellyfin
    /// deny access, and signs out, so the account's saved catalog holds the
    /// denial and the correction.
    Future<void> deniedThenSignedOut() async {
      await connectAndSelect();
      await controller.correctBook(
        'book:one',
        const BookDetails(title: 'Corrected', author: 'Writer'),
      );
      client.failure = const CatalogFailure(CatalogFailureKind.forbidden);
      await controller.refresh();
      await controller.signOut();
      client.failure = null;
    }

    Future<void> signInAgain() =>
        controller.connect('https://books.example', 'alice', 'password');

    test('a sign-in that lists the selected libraries ends the denial, so the saved books appear at once', () async {
      await deniedThenSignedOut();
      await signInAgain();
      final status = controller.statusNotifier.value;
      expect(status.reach, CatalogReach.reached);
      expect(status.verified, isTrue);
      expect(controller.accountNotifier.value.accessBlocked, isFalse);
      expect(controller.libraryNotifier.value.books.single.title, 'Corrected');
      controller.checkInvariants();
    });

    test('the status never says that access is revoked and that the sign-in succeeded', () async {
      await deniedThenSignedOut();
      final seen = <CatalogStatus>[];
      controller.statusNotifier.addListener(
        () => seen.add(controller.statusNotifier.value),
      );
      await signInAgain();
      expect(
        seen.where(
          (status) =>
              status.verified && status.reach == CatalogReach.accessRevoked,
        ),
        isEmpty,
      );
    });

    test('after a sign-in ends the denial, a restart shows the library with its corrections', () async {
      await deniedThenSignedOut();
      await signInAgain();
      final restarted = newController();
      addTearDown(restarted.dispose);
      await restarted.restore();
      expect(restarted.accountNotifier.value.accessBlocked, isFalse);
      expect(
        restarted.statusNotifier.value.reach,
        isNot(CatalogReach.accessRevoked),
      );
      expect(restarted.libraryNotifier.value.books.single.title, 'Corrected');
      restarted.checkInvariants();
    });

    test('a sign-in whose end of the denial cannot be saved did not succeed and keeps the saved denial', () async {
      await deniedThenSignedOut();
      final saved = Map.of(store.values);
      store.failWrites = true;
      await signInAgain();
      final status = controller.statusNotifier.value;
      expect(status.verified, isFalse);
      expect(status.reach, CatalogReach.accessRevoked);
      expect(status.message, isNotNull);
      expect(store.values, saved);
      controller.checkInvariants();
      store.failWrites = false;
      await controller.refresh();
      expect(controller.libraryNotifier.value.books.single.title, 'Corrected');
    });

    test(
      'a sign-in whose libraries lack the selection keeps the denial',
      () async {
        await deniedThenSignedOut();
        client.views = [const BookLibrary('other', 'Other')];
        await signInAgain();
        final status = controller.statusNotifier.value;
        expect(status.reach, CatalogReach.accessRevoked);
        expect(status.verified, isFalse);
        expect(controller.libraryNotifier.value.books, isEmpty);
      },
    );
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
    );

    test('a catalog that the worker finds incomplete is reported to a person who asked, and the saved books stay', () async {
      client.entries = _largeLibrary(prefix: 'Saved');
      await connectAndSelect();
      final saved = store.values[account('alice').scope.key];
      client = _PagedClient(Uri.parse('https://books.example'), [
        for (final value in _largeLibrary()) {...value.json},
      ], pageTotal: 41);
      crossings.clear();
      builds.clear();
      await controller.refresh(byUser: true);
      await settleReports();
      expect(crossings, [false]);
      expect(builds, isEmpty);
      final status = controller.statusNotifier.value;
      expect(
        status.message,
        const CatalogFailure(CatalogFailureKind.incomplete).message,
      );
      expect(status.reach, CatalogReach.reached);
      expect(status.verified, isFalse);
      expect(controller.books.first.title, startsWith('Saved'));
      expect(store.values[account('alice').scope.key], saved);
      controller.checkInvariants();
    });

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
