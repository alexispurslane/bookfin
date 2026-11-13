import 'dart:async';
import 'dart:io';

import 'package:bookfin/catalog/jellyfin.dart';
import 'package:bookfin/playback/database.dart';
import 'package:bookfin/playback/store.dart';
import 'package:bookfin/sync/journal.dart';
import 'package:bookfin/sync/transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'incremental_store_test.dart' show listening;

class UploadServer extends JellyfinClient {
  UploadServer() : super(Uri.parse('http://localhost'), deviceId: 'batch-test');
  final objects = <String, Map<String, dynamic>>{};
  final held = <Completer<void>>[];
  final firstUpload = Completer<void>();
  bool hold = false;
  int active = 0;
  int peak = 0;
  int uploads = 0;
  String? reject;
  String? malformed;

  JellyfinSession get session => JellyfinSession(
    scope: AccountScope(server: server, serverId: 'server', userId: 'alice'),
    token: 'test',
    username: 'Alice',
    canDownload: true,
  );

  @override
  Future<JellyfinSession> validate(JellyfinSession session) async => session;

  void release() {
    hold = false;
    for (final gate in held.reversed) {
      if (!gate.isCompleted) gate.complete();
    }
  }

  @override
  Future<Map<String, dynamic>> uploadPersonalRecord(
    JellyfinSession session,
    String identity,
    String payload,
  ) async {
    uploads++;
    active++;
    if (active > peak) peak = active;
    if (!firstUpload.isCompleted) firstUpload.complete();
    try {
      if (hold) {
        final gate = Completer<void>();
        held.add(gate);
        await gate.future;
      }
      if (identity == reject) throw const HttpException('interrupted upload');
      final stored = objects.putIfAbsent(
        identity,
        () => {
          'Id': identity,
          'Payload': payload,
          'Deleted': false,
          'Sequence': objects.length + 1,
        },
      );
      return identity == malformed ? {...stored, 'Payload': 'wrong'} : stored;
    } finally {
      active--;
    }
  }

  @override
  Future<Map<String, dynamic>> personalRecord(
    JellyfinSession session,
    String identity,
  ) async => objects[identity] ?? (throw const HttpException('missing'));

  @override
  Future<Map<String, dynamic>> personalRecordChanges(
    JellyfinSession session,
    int after,
  ) async {
    final page = objects.values
        .where((v) => (v['Sequence'] as int) > after)
        .take(4)
        .toList();
    return {
      'Objects': page,
      'Cursor': page.isEmpty ? after : page.last['Sequence'],
      'HasMore': objects.length > after + page.length,
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late RecordDatabase database;
  late Database sql;
  late LocalResumeStore records;
  late UploadServer server;
  late String account;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final directory = await Directory.systemTemp.createTemp('bookfin-batch-');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/records.sqlite';
    database = await RecordDatabase.open(
      factory: databaseFactoryFfi,
      path: path,
    );
    sql = await databaseFactoryFfi.openDatabase(path);
    addTearDown(database.close);
    records = LocalResumeStore(openDatabase: () async => database);
    server = UploadServer();
    addTearDown(server.close);
    account = server.session.scope.key;
  });

  Future<List<String>> seed(int count) async {
    for (var i = 1; i <= count; i++) {
      await records.write(account, listening(i * 1000));
    }
    return (await records.pendingUploads(account))
        .map(RecordJournal.identity)
        .toList();
  }

  Future<void> audit() async {
    await sql.execute('CREATE TABLE commits (cursor INTEGER)');
    await sql.execute(
      'CREATE TRIGGER count_commit AFTER UPDATE ON record_accounts '
      'BEGIN INSERT INTO commits VALUES (NEW.cursor); END',
    );
  }

  test('legacy uploads overlap within a bound and keep actions saved during upload', () async {
    final initial = await seed(12);
    server.hold = true;
    final exchange = RecordTransport(records)
        .synchronize(server.session, server);
    await server.firstUpload.future;
    await pumpEventQueue();
    try {
      expect(server.active, inInclusiveRange(2, 4));
      expect(server.uploads, lessThan(initial.length));
      await records.write(account, listening(13000));
    } finally {
      server.release();
      await exchange;
    }
    expect(server.peak, lessThanOrEqualTo(4));
    expect(server.objects.keys, unorderedEquals(initial));
    expect(await records.pendingUploads(account), hasLength(1));
    await RecordTransport(records).synchronize(server.session, server);
    expect(await records.pendingUploads(account), isEmpty);
    expect(server.objects, hasLength(13));
    await records.checkInvariants();
  });

  test(
    'one confirmed group uses one durable acknowledgment transaction',
    () async {
      await seed(3);
      await audit();
      await RecordTransport(records).synchronize(server.session, server);
      expect(await sql.query('commits', where: 'cursor = 0'), hasLength(1));
      expect(await records.pendingUploads(account), isEmpty);
      expect(await sql.query('record_actions'), hasLength(3));
    },
  );

  test('an acknowledgment failure rolls back every action in its group', () async {
    final identities = await seed(3);
    await sql.execute(
      "CREATE TRIGGER fail_ack BEFORE UPDATE OF pending ON record_actions "
      "WHEN OLD.identity = '${identities[1]}' BEGIN SELECT RAISE(ABORT, 'disk full'); END",
    );
    await expectLater(
      RecordTransport(records).synchronize(server.session, server),
      throwsA(isA<DatabaseException>()),
    );
    records = LocalResumeStore(openDatabase: () async => database);
    expect(
      (await records.pendingUploads(account)).map(RecordJournal.identity),
      identities,
    );
    await sql.execute('DROP TRIGGER fail_ack');
    await RecordTransport(records).synchronize(server.session, server);
    expect(await records.pendingUploads(account), isEmpty);
    expect(server.objects, hasLength(3));
    await records.checkInvariants();
  });

  for (final malformed in [false, true]) {
    test(
      '${malformed ? 'mismatched confirmation' : 'failed request'} retains only unconfirmed identities across restart',
      () async {
        final identities = await seed(3);
        await records.write('another-account', listening(7000));
        if (malformed) {
          server.malformed = identities[1];
        } else {
          server.reject = identities[1];
        }
        await audit();
        await expectLater(
          RecordTransport(records).synchronize(server.session, server),
          throwsException,
        );
        records = LocalResumeStore(openDatabase: () async => database);
        expect(
          (await records.pendingUploads(account)).map(RecordJournal.identity),
          [identities[1]],
        );
        expect(await records.pendingUploads('another-account'), hasLength(1));
        expect(await sql.query('commits', where: 'cursor = 0'), hasLength(1));
        expect(await records.discoveryCursor(account), 0);
        server.reject = null;
        server.malformed = null;
        await RecordTransport(records).synchronize(server.session, server);
        expect(await records.pendingUploads(account), isEmpty);
        expect(server.objects, hasLength(3));
        expect(
          (await records.read(
            account,
          ))!['resumes']['edition'].single['milliseconds'],
          3000,
        );
        await records.checkInvariants();
      },
    );
  }
}
