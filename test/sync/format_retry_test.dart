import 'dart:convert';
import 'dart:io';

import 'package:bookfin/catalog/jellyfin.dart';
import 'package:bookfin/catalog/transport.dart';
import 'package:bookfin/playback/database.dart';
import 'package:bookfin/playback/store.dart';
import 'package:bookfin/sync/journal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fixture.dart';

const _evidence =
    'tool/evidence/reader/formats/20261103/android-corrected/downloads-removed.json';

Future<Map<String, dynamic>> _capture() async =>
    jsonDecode(await File(_evidence).readAsString()) as Map<String, dynamic>;

class _UnconfirmedUpload implements JsonTransport {
  final JsonTransport delegate = createTransport();
  final attempts = <({String identity, String payload})>[];
  bool interrupt = true;

  @override
  Future<Map<String, dynamic>> send(
    Uri uri, {
    required String method,
    required Map<String, String> headers,
    Map<String, dynamic>? body,
  }) async {
    if (method == 'PUT') {
      attempts.add((
        identity: uri.pathSegments.last,
        payload: body!['Payload'] as String,
      ));
    }
    final response = await delegate.send(
      uri,
      method: method,
      headers: headers,
      body: body,
    );
    if (method == 'PUT' && interrupt) {
      interrupt = false;
      return {...response, 'Payload': 'unconfirmed'};
    }
    return response;
  }

  @override
  void close() => delegate.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  sqfliteFfiInit();

  test(
    'the first pending Android quote uploads without changing its payload',
    () async {
      final fixture = await SyncFixture.open();
      addTearDown(fixture.close);
      final capture = await _capture();
      final rows = capture['tables']['record_actions'] as List;
      final row = rows.firstWhere((row) => row['payload']['sequence'] == 10);
      final payload = jsonEncode(row['payload']);
      expect(payload, contains('“'));
      final response = await fixture.client.uploadPersonalRecord(
        fixture.session,
        row['identity'] as String,
        payload,
      );
      expect(response['Payload'], payload);
      expect(response['Id'], row['identity']);
    },
  );

  test(
    'personal records preserve accented text and supplementary Unicode',
    () async {
      final fixture = await SyncFixture.open();
      addTearDown(fixture.close);
      final payload = jsonEncode({'title': 'Café, “世界”, 📚'});
      final response = await fixture.client.uploadPersonalRecord(
        fixture.session,
        'action.unicode.1',
        payload,
      );
      expect(response['Payload'], payload);
    },
  );

  test('all 28 pending Android actions retry durably without changing identity or another account', () async {
    SharedPreferences.setMockInitialValues({});
    final config = Platform.environment['BOOKFIN_FORMAT_SYNC_FIXTURE'];
    final fixture = config == null ? await SyncFixture.open() : null;
    if (fixture != null) addTearDown(fixture.close);
    final session =
        fixture?.session ??
        JellyfinSession.fromJson(
          jsonDecode(await File(config!).readAsString())
              as Map<String, dynamic>,
        );
    final seedClient = JellyfinClient(
      session.scope.server,
      deviceId: 'seed-nine',
    );
    addTearDown(seedClient.close);
    final capture = await _capture();
    final tables = capture['tables'] as Map<String, dynamic>;
    final rows = (tables['record_actions'] as List)
        .cast<Map<String, dynamic>>();
    final account = session.scope.key;
    final actions = [
      for (final row in rows)
        {...row['payload'] as Map<String, dynamic>, 'account': account},
    ];
    final payloads = {
      for (final action in actions)
        RecordJournal.identity(action): jsonEncode(action),
    };
    final pending = [
      for (final row in rows)
        if (row['pending'] == 1) row['identity'] as String,
    ];
    expect(actions, hasLength(37));
    expect(pending, hasLength(28));
    final accepted =
        actions
            .where(
              (action) => !pending.contains(RecordJournal.identity(action)),
            )
            .toList()
          ..sort(
            (first, second) =>
                (first['sequence'] as int).compareTo(second['sequence'] as int),
          );
    for (final action in accepted) {
      await seedClient.uploadPersonalRecord(
        session,
        RecordJournal.identity(action),
        jsonEncode(action),
      );
    }
    final directory = await Directory.systemTemp.createTemp(
      'bookfin-format-retry-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/records.sqlite';
    var database = await RecordDatabase.open(
      factory: databaseFactoryFfi,
      path: path,
    );
    addTearDown(() => database.close());
    final retainedAccount = (tables['record_accounts'] as List).single as Map;
    final journal = RecordJournal(
      account,
      retainedAccount['replica'] as String,
      {
        'version': 1,
        'replica': retainedAccount['replica'],
        'cursor': retainedAccount['cursor'],
        'actions': actions,
        'pending': pending,
      },
    );
    await database.commit(
      account,
      Map<String, dynamic>.from(retainedAccount['metadata'] as Map),
      journal,
      initialize: true,
    );
    final other = RecordJournal('previous-account', 'previous-installation');
    for (var sequence = 1; sequence <= 7; sequence++) {
      other.change(
        jsonEncode([
          'reading',
          'resumes',
          jsonEncode(['book', 'source', 'revision']),
        ]),
        {
          'edition': 'book',
          'source': 'source',
          'revision': 'revision',
          'anchor': 'passage-$sequence',
        },
      );
    }
    await database.commit(
      'previous-account',
      {'version': 3},
      other,
      initialize: true,
    );
    final previous = await database.read('previous-account');
    final before = await database.load(account);
    await database.close();
    database = await RecordDatabase.open(
      factory: databaseFactoryFfi,
      path: path,
    );
    final transport = _UnconfirmedUpload();
    final client = JellyfinClient(
      session.scope.server,
      deviceId: 'format-retry',
      transport: transport,
    );
    addTearDown(client.close);
    final records = LocalResumeStore(openDatabase: () async => database);
    await expectLater(
      records.synchronize(session, client),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'The server did not confirm the pending personal record.',
        ),
      ),
    );
    expect(await database.load(account), before);
    expect(await database.read('previous-account'), previous);
    expect(transport.attempts.single.identity, endsWith('.10'));
    await database.close();
    database = await RecordDatabase.open(
      factory: databaseFactoryFfi,
      path: path,
    );
    final restarted = LocalResumeStore(openDatabase: () async => database);
    await restarted.synchronize(session, client);
    expect(transport.attempts[1], transport.attempts.first);
    final saved = (await database.load(account))!['sync'] as Map;
    expect(saved['pending'], isEmpty);
    expect(saved['cursor'], 37);
    expect({
      for (final action in saved['actions'] as List)
        RecordJournal.identity(action as Map<String, dynamic>): jsonEncode(
          action,
        ),
    }, payloads);
    expect(await database.read('previous-account'), previous);
    final discovered = <String, String>{};
    var cursor = 0;
    while (true) {
      final page = await seedClient.personalRecordChanges(session, cursor);
      for (final object in page['Objects'] as List) {
        discovered[object['Id'] as String] = object['Payload'] as String;
      }
      cursor = page['Cursor'] as int;
      if (page['HasMore'] == false) break;
    }
    expect(discovered, payloads);
    await restarted.synchronize(session, client);
    expect(transport.attempts, hasLength(29));
    await restarted.checkInvariants();
  });
}
