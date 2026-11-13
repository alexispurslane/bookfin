import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:bookfin/catalog/jellyfin.dart';
import 'package:bookfin/catalog/controller.dart';
import 'package:bookfin/foundation/hop.dart';
import 'package:bookfin/catalog/transport.dart';
import 'package:flutter_test/flutter_test.dart';

import 'controller_test.dart'
    show account, FixtureClient, MemoryCredentials, MemoryCatalogStore;
import 'model_test.dart' show entry;

typedef _Page = ({int total, Map<String, String?> items});
typedef _Members = ({String name, List<_Page> pages});

// A page may be stored on the UI isolate, but only a worker may traverse it.
// Moving either reduction back to the UI isolate therefore fails behaviorally.
class _WorkerItems extends MapBase<String, String?> {
  _WorkerItems(this.ui, this.valuesById);
  final SendPort ui;
  final Map<String, String?> valuesById;
  void check() {
    if (Isolate.current.controlPort == ui) {
      throw StateError('Collection items were traversed on the UI isolate');
    }
  }

  @override
  Iterable<String> get keys {
    check();
    return valuesById.keys;
  }

  @override
  String? operator [](Object? key) {
    check();
    return valuesById[key];
  }

  @override
  void operator []=(String key, String? value) =>
      throw UnsupportedError('read only');
  @override
  void clear() => throw UnsupportedError('read only');
  @override
  String? remove(Object? key) => throw UnsupportedError('read only');
}

// Only the production callback, payload and ports cross this boundary. In
// particular the test's transport, account and gates never enter the worker.
Future<(R, bool, M)> _run<M, R>(
  FutureOr<R> Function(M) work,
  M input,
  SendPort ui,
  SendPort? waiting,
  Object? failure,
) => Isolate.run(() async {
  if (waiting != null) {
    final release = ReceivePort();
    waiting.send(release.sendPort);
    await release.first;
    release.close();
  }
  if (failure != null) throw failure;
  var result = await work(input);
  if (result case final _Page page) {
    result = (total: page.total, items: _WorkerItems(ui, page.items)) as R;
  }
  return (result, Isolate.current.controlPort != ui, input);
});

enum _Stage { page, discovery, membership }

class _Workers {
  _Stage? hold;
  final entered = Completer<void>();
  SendPort? release;
  final calls = <({Object? input, Object? output, bool away})>[];
  Object? failure;

  Future<R> call<M, R>(FutureOr<R> Function(M) work, M input) async {
    final stage = switch (input) {
      List<List<_Page>>() => _Stage.discovery,
      List<_Members>() => _Stage.membership,
      _ => _Stage.page,
    };
    final ready = stage == hold ? ReceivePort() : null;
    ready?.listen((port) {
      release = port as SendPort;
      entered.complete();
      ready.close();
    });
    final (output, away, crossed) = await _run(
      work,
      input,
      Isolate.current.controlPort,
      ready?.sendPort,
      failure,
    );
    calls.add((input: crossed, output: output, away: away));
    return output;
  }
}

class _Transport implements JsonTransport {
  int collectionSends = 0;
  int collectionBodies = 0;
  final collectionByteLengths = <int>[];
  final starts = <String, List<int>>{};
  Object? failure;
  String? rawCollectionBody;
  int children = 601;
  bool sparse = false;
  bool closed = false;
  String series = 'Series';
  List<Map<String, dynamic>> books = [];

  Map<String, dynamic> response(Uri uri) {
    if (closed) throw const CatalogFailure(CatalogFailureKind.cancelled);
    if (uri.path.endsWith('UserViews')) {
      return {
        'Items': [
          {'Id': 'books', 'Name': 'Books', 'CollectionType': 'books'},
          {'Id': 'ebooks', 'Name': 'Ebooks', 'CollectionType': 'books'},
        ],
      };
    }
    final q = uri.queryParameters;
    final parent = q['parentId']!;
    final discovery = q['includeItemTypes'] == 'BoxSet';
    final membership = parent == 'set';
    final start = int.parse(q['startIndex']!);
    if (discovery || membership) {
      if (failure case final error?) throw error;
      starts
          .putIfAbsent(discovery ? 'discovery-$parent' : parent, () => [])
          .add(start);
    }
    final items = discovery
        ? <Map<String, dynamic>>[
            {'Id': 'set', 'Name': series},
          ]
        : membership
        ? [
            for (var i = start; i < min(start + 200, children); i++)
              if (!sparse || i == children - 1)
                {'Id': 'book-$i', 'Type': 'Book'},
          ]
        : books;
    return {
      'Items': items,
      'TotalRecordCount': discovery
          ? 1
          : membership
          ? children
          : books.length,
      'StartIndex': start,
    };
  }

  bool isCollection(Uri uri) =>
      uri.queryParameters['includeItemTypes'] == 'BoxSet' ||
      uri.queryParameters['parentId'] == 'set';

  @override
  Future<Map<String, dynamic>> send(
    Uri uri, {
    required String method,
    required Map<String, String> headers,
    Map<String, dynamic>? body,
  }) async {
    if (isCollection(uri)) collectionSends++;
    return response(uri);
  }

  @override
  Future<Uint8List> fetchBody(
    Uri uri, {
    required String method,
    required Map<String, String> headers,
    Map<String, dynamic>? body,
  }) async {
    final bytes = utf8.encode(
      isCollection(uri) && rawCollectionBody != null
          ? rawCollectionBody!
          : jsonEncode(response(uri)),
    );
    if (isCollection(uri)) {
      collectionBodies++;
      collectionByteLengths.add(bytes.length);
    }
    return bytes;
  }

  @override
  void close() => closed = true;
}

// Sign-in/policy are deterministic here; catalog and cancellation use the real
// client, including the pending native worker. The controller owns adoption.
class _CatalogClient extends FixtureClient {
  _CatalogClient(this.user, _Transport transport, IsolateHop? hop)
    : pages = JellyfinClient(
        account(user).scope.server,
        deviceId: 'controller-test',
        transport: transport,
        hop: hop,
      ),
      super(account(user).scope.server);
  final String user;
  final JellyfinClient pages;
  @override
  Future<JellyfinSession> signIn(String username, String password) async =>
      account(user);
  @override
  Future<CatalogPages> catalog(JellyfinSession session, Set<String> shown) =>
      pages.catalog(session, shown);
  @override
  void close() {
    pages.close();
    super.close();
  }
}

void main() {
  late _Workers workers;
  late _Transport transport;
  late JellyfinClient client;
  late JellyfinSession session;
  setUp(() {
    workers = _Workers();
    transport = _Transport();
    session = account('alice');
    client = JellyfinClient(
      session.scope.server,
      deviceId: 'worker-test',
      transport: transport,
      hop: workers.call,
    );
  });
  tearDown(() => client.close());

  Matcher failsWith(CatalogFailureKind kind) =>
      throwsA(isA<CatalogFailure>().having((f) => f.kind, 'kind', kind));

  test('native workers parse pages and reduce discovery and membership without UI item traversal', () async {
    final result = await client.catalog(session, {'books', 'ebooks'});
    expect(result.collections, {
      for (var i = 0; i < 601; i++) 'book-$i': ['Series'],
    });
    expect(workers.calls, hasLength(8)); // One hop per page and two reductions.
    expect(
      transport.collectionSends,
      0,
      reason: 'Decoded collection maps must not enter the client',
    );
    expect(transport.collectionBodies, 6); // Two discoveries, four child pages.
    expect(workers.calls.every((call) => call.away), isTrue);
    final parses = workers.calls.where((call) => call.output is _Page).toList();
    expect(parses, hasLength(6));
    final bytes = parses.map(
      (call) => (call.input as ({Uint8List bytes, int start, int? total}))
          .bytes
          .length,
    );
    expect(bytes.toList()..sort(), transport.collectionByteLengths..sort());
    final discoveries = workers.calls.where(
      (call) => call.input is List<List<_Page>>,
    );
    expect(discoveries, hasLength(1));
    expect(discoveries.single.output, [(id: 'set', name: 'Series')]);
    final reductions = workers.calls.where(
      (call) => call.input is List<_Members>,
    );
    expect(reductions, hasLength(1));
    final payload = reductions.single.input as List<_Members>;
    expect(payload.single.name, 'Series');
    expect(payload.single.pages, hasLength(4));
    expect(reductions.single.output, result.collections);
    expect(transport.starts['set'], [0, 200, 400, 600]);
  });

  test('programming errors do not become missing optional series', () async {
    transport.failure = StateError('broken collection transport');
    await expectLater(client.catalog(session, {'books'}), throwsStateError);
  });

  test('native worker errors do not become missing optional series', () async {
    workers.failure = AssertionError('broken worker invariant');
    await expectLater(
      client.catalog(session, {'books'}),
      throwsA(isA<AssertionError>()),
    );
  });

  for (final body in [
    '{broken',
    '[]',
    '{"TotalRecordCount":1,"Items":[7]}',
    '{"TotalRecordCount":1,"Items":[{"Id":"set","Name":7}]}',
  ]) {
    test('unreadable optional JSON $body keeps a usable catalog', () async {
      transport.rawCollectionBody = body;
      expect((await client.catalog(session, {'books'})).collections, isEmpty);
    });
  }

  for (final stage in _Stage.values) {
    test(
      'closing while $stage is pending rejects its result and starts no further requests',
      () async {
        workers.hold = stage;
        final pending = client.catalog(session, {'books'});
        final assertion = expectLater(
          pending,
          failsWith(CatalogFailureKind.cancelled),
        );
        await workers.entered.future;
        final requests = transport.collectionBodies;
        client.close();
        workers.release!.send(null);
        await assertion;
        expect(transport.collectionBodies, requests);
      },
    );
  }

  test(
    'a rejected credential cannot attach a pending membership result',
    () async {
      workers.hold = _Stage.membership;
      final pending = client.catalog(session, {'books'});
      await workers.entered.future;
      session.rejectCredential();
      workers.release!.send(null);
      expect((await pending).collections, isEmpty);
    },
  );

  test('closing while a worker fails still reports cancellation', () async {
    workers.hold = _Stage.page;
    workers.failure = IsolateSpawnException('worker unavailable');
    final pending = client.catalog(session, {'books'});
    final assertion = expectLater(
      pending,
      failsWith(CatalogFailureKind.cancelled),
    );
    await workers.entered.future;
    client.close();
    workers.release!.send(null);
    await assertion;
  });

  test('an old account worker cannot replace the new account result', () async {
    workers.hold = _Stage.membership;
    final old = client.catalog(session, {'books'});
    final assertion = expectLater(old, failsWith(CatalogFailureKind.cancelled));
    await workers.entered.future;
    client.close();
    final nextTransport = _Transport()..series = 'Bob series';
    final next = JellyfinClient(
      session.scope.server,
      deviceId: 'bob',
      transport: nextTransport,
    );
    addTearDown(next.close);
    final result = await next.catalog(account('bob'), {'books'});
    workers.release!.send(null);
    await assertion;
    expect(result.collections['book-600'], ['Bob series']);
  });

  test('account replacement adopts and saves only the new account while old membership is pending', () async {
    workers.hold = _Stage.membership;
    var user = 'alice';
    final saved = MemoryCatalogStore();
    final credentials = MemoryCredentials()..value = account(user);
    final controller = CatalogController(
      credentials: credentials,
      store: saved,
      clientFactory: (_, _) => _CatalogClient(
        user,
        _Transport()
          ..series = '$user series'
          ..books = [entry('book-600', title: '$user book').json],
        user == 'alice' ? workers.call : null,
      ),
    );
    addTearDown(controller.dispose);
    await controller.restore();
    final oldRefresh = controller.refresh();
    await workers.entered.future;
    await controller.signOut();
    user = 'bob';
    expect(
      await controller.connect(
        account(user).scope.server.toString(),
        user,
        'fixture',
      ),
      isTrue,
    );
    final bobSaved = saved.values[account('bob').scope.key];
    expect(bobSaved, isNotNull);
    workers.release!.send(null);
    await oldRefresh;
    expect(controller.session?.scope.userId, 'bob');
    expect(controller.libraryNotifier.value.books.single.series, 'bob series');
    expect(saved.values[account('bob').scope.key], bobSaved);
    expect(saved.values[account('alice').scope.key], isNull);
  });

  test('empty shown libraries start no collection workers', () async {
    expect((await client.catalog(session, {})).collections, isEmpty);
    expect(workers.calls, isEmpty);
    expect(transport.collectionBodies, 0);
  });

  test(
    'sparse pages keep late direct membership through native workers',
    () async {
      transport.sparse = true;
      final result = await client.catalog(session, {'books'});
      expect(result.collections, {
        'book-600': ['Series'],
      });
      expect(transport.starts['set'], [0, 200, 400, 600]);
    },
  );
}
