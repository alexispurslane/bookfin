import 'dart:convert';
import 'dart:typed_data';

import 'package:bookfin/catalog/jellyfin.dart';
import 'package:bookfin/catalog/transport.dart';
import 'package:bookfin/sync/journal.dart';
import 'package:bookfin/sync/transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'phone.dart';

class BatchApi implements JsonTransport {
  final objects = <String, Map<String, dynamic>>{};
  final putSizes = <int>[];
  final putBytes = <int>[];
  int singlePuts = 0;
  int pages = 0;
  Object? version = '0.2.0.0';
  Exception? discoveryFailure;
  String? malformed;
  String? reject;
  String? responseFault;
  bool interruptBatch = false;

  Map<String, dynamic> put(String id, String payload) => objects.putIfAbsent(
    id,
    () => {
      'Id': id,
      'Payload': payload,
      'Sequence': objects.length + 1,
      'Deleted': false,
    },
  );

  @override
  Future<Map<String, dynamic>> send(
    Uri uri, {
    required String method,
    required Map<String, String> headers,
    Map<String, dynamic>? body,
  }) async {
    if (uri.path == '/System/Info/Public') return {'Id': 'server'};
    expect(headers['Authorization'], contains('Token="test"'));
    if (uri.path == '/Users/Me') return {'Id': 'alice'};
    if (method == 'PUT' && uri.path == '/BookfinStorage/v2/objects') {
      final items = (body!['Objects'] as List).cast<Map>();
      putSizes.add(items.length);
      putBytes.add(utf8.encode(jsonEncode(body)).length);
      final results = <Map<String, dynamic>>[
        for (final item in items)
          if (item['Id'] == reject)
            {'Id': item['Id'], 'Status': 409}
          else
            {
              'Id': item['Id'],
              'Status': 201,
              'Object': {
                ...put(item['Id'] as String, item['Payload'] as String),
                if (item['Id'] == malformed) 'Payload': 'wrong',
              },
            },
      ];
      if (interruptBatch) {
        throw const CatalogFailure(CatalogFailureKind.unavailable);
      }
      if (responseFault == 'missing') results.removeAt(1);
      if (responseFault == 'duplicate') results.add(results.first);
      if (responseFault == 'unexpected') {
        results.add({'Id': 'foreign', 'Status': 201});
      }
      return {'Results': results.reversed.toList()};
    }
    if (method == 'PUT') {
      singlePuts++;
      return put(uri.pathSegments.last, body!['Payload'] as String);
    }
    if (uri.pathSegments.length == 4) {
      return objects[uri.pathSegments.last] ??
          (throw const CatalogFailure(
            CatalogFailureKind.unavailable,
            status: 404,
          ));
    }
    if (discoveryFailure case final failure?) throw failure;
    pages++;
    final after = int.parse(uri.queryParameters['after']!);
    final limit = int.parse(uri.queryParameters['limit']!);
    final available = objects.values
        .where((o) => (o['Sequence'] as int) > after)
        .toList();
    final page = <Map<String, dynamic>>[];
    var bytes = 0;
    for (final object in available.take(limit)) {
      final size = utf8.encode(object['Payload'] as String).length;
      if (bytes + size > 1048576) break;
      page.add(object);
      bytes += size;
    }
    return {
      'Objects': page,
      'Cursor': page.isEmpty ? after : page.last['Sequence'],
      'HasMore': available.length > page.length,
      if (version != null) 'PluginVersion': version,
    };
  }

  @override
  Future<Uint8List> fetchBody(
    Uri uri, {
    required String method,
    required Map<String, String> headers,
    Map<String, dynamic>? body,
  }) => throw UnimplementedError();
  @override
  void close() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late BatchApi api;
  late JellyfinClient client;
  late JellyfinSession session;
  late Phone phone;
  late String account;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    api = BatchApi();
    final origin = Uri.parse('http://localhost');
    session = JellyfinSession(
      scope: AccountScope(server: origin, serverId: 'server', userId: 'alice'),
      token: 'test',
      username: 'Alice',
      canDownload: true,
    );
    account = session.scope.key;
    client = JellyfinClient(origin, deviceId: 'batch-test', transport: api);
    addTearDown(client.close);
    phone = await Phone.open('batch-api');
  });

  Future<List<Map<String, dynamic>>> seed(
    int count, {
    int titleLength = 0,
  }) async {
    final journal = RecordJournal(account, 'writer');
    for (var i = 1; i <= count; i++) {
      journal.change(
        jsonEncode([
          'audio',
          'resumes',
          jsonEncode(['book', 'source', 'v1']),
        ]),
        {
          'edition': 'book',
          'source': 'source',
          'revision': 'v1',
          'milliseconds': i,
          if (titleLength > 0) 'bookTitle': 'é' * titleLength,
        },
      );
    }
    await phone.database.write(
      account,
      jsonEncode({'version': 3, 'sync': journal.encode()}),
    );
    await phone.store.read(account);
    return journal.uploads;
  }

  test('thousands of retained actions use bounded batches and complete discovery in one exchange', () async {
    final actions = await seed(2400);
    final sql = await phone.separateConnection();
    await sql.execute('CREATE TABLE commits (cursor INTEGER)');
    await sql.execute(
      'CREATE TRIGGER count_commit AFTER UPDATE ON record_accounts BEGIN INSERT INTO commits VALUES (NEW.cursor); END',
    );
    final clock = Stopwatch()..start();
    await RecordTransport(phone.store).synchronize(session, client);
    final uploadMilliseconds = clock.elapsedMilliseconds;
    final acknowledgments = await sql.query('commits', where: 'cursor = 0');
    expect(api.singlePuts, 0);
    expect(api.putSizes.length, lessThanOrEqualTo(12));
    expect(api.putSizes.every((n) => n > 0 && n <= 256), isTrue);
    expect(acknowledgments.length, api.putSizes.length);
    expect(await phone.store.pendingUploads(account), isEmpty);
    expect(
      api.objects.keys,
      unorderedEquals(actions.map(RecordJournal.identity)),
    );
    final receiver = await Phone.open('batch-receiver');
    final before = api.pages;
    clock.reset();
    await RecordTransport(receiver.store).synchronize(session, client);
    final receiveMilliseconds = clock.elapsedMilliseconds;
    expect(api.pages - before, lessThanOrEqualTo(12));
    await receiver.restart();
    final saved = (await receiver.database.load(account))!['sync'] as Map;
    expect(saved['actions'], actions);
    expect(saved['cursor'], 2400);
    expect(
      (await receiver.store.read(
        account,
      ))!['resumes']['book'].single['milliseconds'],
      2400,
    );
    await receiver.store.checkInvariants();
    // ignore: avoid_print
    print(
      'BATCH_WORKLOAD actions=2400 uploadRequests=${api.putSizes.length} acknowledgmentTransactions=${acknowledgments.length} receiveRequests=${api.pages - before} uploadHostMs=$uploadMilliseconds receiveHostMs=$receiveMilliseconds',
    );
  });

  for (final version in <Object?>[null, '0.1.1.0', '0.2.0.0', '0.3.7.0']) {
    test(
      'authenticated discovery selects the supported protocol for version $version',
      () async {
        api.version = version;
        await seed(7);
        await RecordTransport(phone.store).synchronize(session, client);
        final batch = version == '0.2.0.0' || version == '0.3.7.0';
        expect(api.singlePuts, batch ? 0 : 7);
        expect(api.putSizes.isNotEmpty, batch);
        expect(await phone.store.pendingUploads(account), isEmpty);
      },
    );
  }

  for (final failure in [
    const CatalogFailure(CatalogFailureKind.unauthorized),
    const CatalogFailure(CatalogFailureKind.unavailable),
    const CatalogFailure(CatalogFailureKind.invalidResponse),
  ]) {
    test(
      'failed authenticated discovery never enables legacy uploads: ${failure.kind}',
      () async {
        final actions = await seed(3);
        api.discoveryFailure = failure;
        await expectLater(
          RecordTransport(phone.store).synchronize(session, client),
          throwsA(same(failure)),
        );
        expect(api.objects, isEmpty);
        expect(await phone.store.pendingUploads(account), actions);
      },
    );
  }

  for (final version in <Object>['unknown', 2, '0.2', '1.0.0.0']) {
    test(
      'unrecognized plugin version $version cannot silently select a protocol',
      () async {
        final actions = await seed(3);
        api.version = version;
        await expectLater(
          RecordTransport(phone.store).synchronize(session, client),
          throwsFormatException,
        );
        expect(await phone.store.pendingUploads(account), actions);
        expect(api.objects, isEmpty);
      },
    );
  }

  for (final fault in [
    'missing',
    'duplicate',
    'unexpected',
    'mismatched',
    'rejected',
  ]) {
    test(
      'batch $fault confirmation preserves exact pending identities through restart',
      () async {
        final actions = await seed(3);
        final identities = actions.map(RecordJournal.identity).toList();
        if (fault == 'mismatched') {
          api.malformed = identities[1];
        } else if (fault == 'rejected') {
          api.reject = identities[1];
        } else {
          api.responseFault = fault;
        }
        await expectLater(
          RecordTransport(phone.store).synchronize(session, client),
          throwsException,
        );
        await phone.restart();
        expect(
          (await phone.store.pendingUploads(account))
              .map(RecordJournal.identity),
          fault == 'unexpected'
              ? identities
              : fault == 'duplicate'
              ? [identities[0]]
              : [identities[1]],
        );
        api.responseFault = null;
        api.malformed = null;
        api.reject = null;
        await RecordTransport(phone.store).synchronize(session, client);
        expect(await phone.store.pendingUploads(account), isEmpty);
        expect(api.objects, hasLength(3));
        await phone.store.checkInvariants();
      },
    );
  }

  test('an interrupted batch response keeps every action pending for idempotent retry', () async {
    final actions = await seed(3);
    api.interruptBatch = true;
    await expectLater(
      RecordTransport(phone.store).synchronize(session, client),
      throwsException,
    );
    await phone.restart();
    expect(await phone.store.pendingUploads(account), actions);
    api.interruptBatch = false;
    await RecordTransport(phone.store).synchronize(session, client);
    expect(api.objects, hasLength(3));
    expect(await phone.store.pendingUploads(account), isEmpty);
  });

  test('a batch conflict adopts only the verified server copy and keeps the damaged copy aside', () async {
    final actions = await seed(3);
    final damaged = actions.first;
    final original = {
      ...damaged,
      'value': {...damaged['value'] as Map, 'milliseconds': 42},
    };
    final identity = RecordJournal.identity(original);
    api.put(identity, jsonEncode(original));
    api.reject = identity;
    final result = await RecordTransport(phone.store)
        .synchronize(session, client);
    expect(result.replaced, 1);
    await phone.restart();
    final saved = (await phone.database.load(account))!['sync'] as Map;
    expect((saved['actions'] as List).first, original);
    expect(saved['pending'], isEmpty);
    final sql = await phone.separateConnection();
    expect(await sql.query('set_aside_record_actions'), isNotEmpty);
    await phone.store.checkInvariants();
  });

  test('receiving a page rolls back its cursor and actions together before retrying causal gaps in both domains', () async {
    final audio = RecordJournal(account, 'audio-phone');
    final reading = RecordJournal(account, 'reading-phone');
    final audioAddress = jsonEncode([
      'audio',
      'resumes',
      jsonEncode(['book', 'source', 'v1']),
    ]);
    final readingAddress = jsonEncode([
      'reading',
      'resumes',
      jsonEncode(['book', 'ebook', 'v1']),
    ]);
    audio.change(audioAddress, {
      'edition': 'book',
      'source': 'source',
      'revision': 'v1',
      'milliseconds': 10,
    });
    audio.change(audioAddress, null);
    reading.change(readingAddress, {
      'edition': 'book',
      'source': 'ebook',
      'revision': 'v1',
      'anchor': 'one',
    });
    reading.change(readingAddress, {
      'edition': 'book',
      'source': 'ebook',
      'revision': 'v1',
      'anchor': 'two',
    });
    final actions = [
      audio.uploads.last,
      reading.uploads.last,
      audio.uploads.first,
      reading.uploads.first,
    ];
    for (final action in actions) {
      api.put(RecordJournal.identity(action), jsonEncode(action));
    }
    await phone.killDuring(
      'record_accounts',
      () => RecordTransport(phone.store).synchronize(session, client),
    );
    await phone.restart();
    expect(await phone.store.discoveryCursor(account), 0);
    expect(await phone.database.load(account), isNull);
    await RecordTransport(phone.store).synchronize(session, client);
    await phone.restart();
    final saved = (await phone.database.load(account))!['sync'] as Map;
    expect(saved['actions'], actions);
    expect(saved['cursor'], 4);
    expect((await phone.store.read(account))!['resumes'], isEmpty);
    expect(
      (await phone.store.reading.read(account))!['resumes'].single['anchor'],
      'two',
    );
    await phone.store.checkInvariants();
  });

  test(
    'large UTF-8 actions split by bytes before reaching the object count bound',
    () async {
      await seed(45, titleLength: 30000);
      await RecordTransport(phone.store).synchronize(session, client);
      expect(api.singlePuts, 0);
      expect(api.putSizes.length, greaterThan(2));
      expect(api.putBytes.every((size) => size <= 8 * 1024 * 1024), isTrue);
      expect(api.objects, hasLength(45));
      expect(await phone.store.pendingUploads(account), isEmpty);
    },
  );
}
