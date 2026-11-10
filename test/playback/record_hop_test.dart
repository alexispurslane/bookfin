import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:bookfin/playback/database.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:bookfin/playback/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A hop that runs each work item in a new isolate, as production does, and
/// counts the work items. [inputs] holds the input of each, in hop order.
class CountingHop {
  int hops = 0;
  final inputs = <Object?>[];

  /// Runs with each work item, beside it.
  Future<void> Function()? beside;

  Future<R> call<M, R>(FutureOr<R> Function(M) work, M input) async {
    hops++;
    inputs.add(input);
    final result = Isolate.run(() => work(input));
    await beside?.call();
    return result;
  }
}

/// The SQLite binding [files], except that a read-only open, which only
/// the hop's [RecordReader] makes, throws [error].
class FailingReadOnlyOpen implements DatabaseFactory {
  FailingReadOnlyOpen(this.files, this.error);
  final DatabaseFactory files;
  final Object error;

  @override
  Future<Database> openDatabase(String path, {OpenDatabaseOptions? options}) {
    if (options?.readOnly ?? false) throw error;
    return files.openDatabase(path, options: options);
  }

  @override
  Future<String> getDatabasesPath() => files.getDatabasesPath();

  @override
  Future<void> setDatabasesPath(String path) => files.setDatabasesPath(path);

  @override
  Future<void> deleteDatabase(String path) => files.deleteDatabase(path);

  @override
  Future<bool> databaseExists(String path) => files.databaseExists(path);

  @override
  Future<void> writeDatabaseBytes(String path, Uint8List bytes) =>
      files.writeDatabaseBytes(path, bytes);

  @override
  Future<Uint8List> readDatabaseBytes(String path) =>
      files.readDatabaseBytes(path);
}

/// A SQLite failure with the result [code], as the binding reports it.
class SqliteFailure extends DatabaseException {
  SqliteFailure(super.message, this.code);
  final int code;

  @override
  int? getResultCode() => code;

  @override
  Object? get result => null;
}

/// The result codes of SQLITE_CANTOPEN and SQLITE_CORRUPT.
const cannotOpen = 14;
const corrupt = 11;

Map<String, dynamic> position(int milliseconds) => {
  'edition': 'book',
  'source': 'audio',
  'revision': 'v1',
  'milliseconds': milliseconds,
};

Map<String, dynamic> event(String id) => {
  'id': id,
  'at': '1970-01-01T00:00:00Z',
  'kind': 'pause',
  'bookTitle': 'Hop fixture',
  'editionLabel': 'Audio',
  'before': position(0),
  'after': position(0),
};

Map<String, dynamic> settings() => {
  'version': 3,
  'selected': 'book',
  'speed': 1.0,
  'backward': 10,
  'forward': 30,
};

ListeningChanges resume(int milliseconds) => ListeningChanges(
  settings(),
  resumes: {
    'book': [
      {
        'source': 'audio',
        'revision': 'v1',
        'sources': 'recording',
        'milliseconds': milliseconds,
        'pendingOffline': false,
      },
    ],
  },
);

Map<String, dynamic> page(int sourcePage) => {
  'edition': 'ebook',
  'source': 'pdf',
  'revision': 'r1',
  'anchor': jsonEncode({'page': sourcePage}),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late RecordDatabase database;
  late String path;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final directory = await Directory.systemTemp.createTemp('bookfin-hop-');
    addTearDown(() => directory.delete(recursive: true));
    path = '${directory.path}/records.sqlite';
    database = await RecordDatabase.open(
      factory: databaseFactoryFfi,
      path: path,
    );
    addTearDown(database.close);
  });

  /// Saves a listening account of 20 history events and 30 resume moves,
  /// which is 50 journal actions in 21 records, and one reading place, into
  /// [records], or into [database].
  Future<void> seedLargeAccount([RecordDatabase? records]) async {
    final into = records ?? database;
    final writer = LocalResumeStore(openDatabase: () async => into);
    await writer.save(
      'alice',
      ListeningChanges(
        settings(),
        history: {
          for (var index = 0; index < 20; index++) 'h$index': event('h$index'),
        },
      ),
    );
    for (var second = 1; second <= 30; second++) {
      await writer.save('alice', resume(second * 1000));
    }
    await writer.reading.write('alice', {
      'version': 1,
      'fontSize': 22,
      'resumes': [page(7)],
      'bookmarks': <dynamic>[],
    });
  }

  test(
    'opening a large account replays its journal in one hop for both domains',
    () async {
      await seedLargeAccount();
      final hop = CountingHop();
      final store = LocalResumeStore(
        openDatabase: () async => database,
        hop: hop.call,
      );

      final listening = (await store.read('alice'))!;
      final reading = (await store.reading.read('alice'))!;

      expect(hop.hops, 1);
      expect(listening['history'], hasLength(20));
      expect(listening['resumes']['book'].single['milliseconds'], 30000);
      expect(reading['fontSize'], 22);
      expect(reading['resumes'].single['anchor'], jsonEncode({'page': 7}));
      await store.checkInvariants();
    },
  );

  test('a refresh after a change derives the snapshot in one hop', () async {
    await seedLargeAccount();
    final hop = CountingHop();
    final store = LocalResumeStore(
      openDatabase: () async => database,
      hop: hop.call,
    );
    final opened = (await store.read('alice'))!;
    store.acceptSnapshot('alice', opened);
    await store.save('alice', resume(31000));
    final before = hop.hops;

    final refreshed = (await store.read('alice'))!;

    expect(hop.hops, before + 1);
    expect(refreshed['resumes']['book'].single['milliseconds'], 31000);
    expect(refreshed['history'], hasLength(20));
  });

  test(
    'a snapshot accepted from a hop read still guards against stale writes',
    () async {
      await seedLargeAccount();
      final store = LocalResumeStore(
        openDatabase: () async => database,
        hop: CountingHop().call,
      );
      final opened = (await store.read('alice'))!;
      store.acceptSnapshot('alice', opened);
      final before = (await database.load('alice'))!['sync']['actions'] as List;

      // The writer resends the place that it read, which adds no sync action.
      await store.save('alice', resume(30000));

      final after = (await database.load('alice'))!['sync']['actions'] as List;
      expect(after, hasLength(before.length));
    },
  );

  test('a large legacy preferences account decodes and encodes its migration in workers', () async {
    SharedPreferences.setMockInitialValues({
      'bookfin.playback.v1.bob': jsonEncode({
        ...settings(),
        'history': [for (var index = 0; index < 40; index++) event('h$index')],
        'bookmarks': <dynamic>[],
        'resumes': <String, dynamic>{},
      }),
    });
    final hop = CountingHop();
    final store = LocalResumeStore(hop: hop.call);

    final listening = (await store.read('bob'))!;

    expect(hop.hops, 2);
    expect(listening['history'], hasLength(40));
  });

  // Measured in AOT (tool/research/record_hop_bench): a hop costs the UI
  // isolate about 9 to 11 µs. Restoring an account of one action costs it
  // about 27 µs, and an account without actions about 9 µs. Decoding a
  // saved text costs more than a hop from about 32 characters.
  test('an account with one saved place restores in another isolate, because its replay costs more than a hop', () async {
    final writer = LocalResumeStore(openDatabase: () async => database);
    await writer.save('carol', resume(1000));
    final hop = CountingHop();
    final store = LocalResumeStore(
      openDatabase: () async => database,
      hop: hop.call,
    );

    expect((await store.read('carol'))!['resumes']['book'], hasLength(1));
    expect(hop.hops, 1);
  });

  test('an account with settings and no records restores here, because a hop costs more', () async {
    final writer = LocalResumeStore(openDatabase: () async => database);
    await writer.write('dave', settings());
    final hop = CountingHop();
    final store = LocalResumeStore(
      openDatabase: () async => database,
      hop: hop.call,
    );

    expect((await store.read('dave'))!['speed'], 1.0);
    expect(hop.hops, 0);
  });

  test('one legacy preferences record decodes and encodes its migration in workers', () async {
    SharedPreferences.setMockInitialValues({
      'bookfin.playback.v1.erin': jsonEncode({
        ...settings(),
        'history': [event('h0')],
      }),
    });
    final hop = CountingHop();
    final store = LocalResumeStore(hop: hop.call);

    expect((await store.read('erin'))!['history'], hasLength(1));
    expect(hop.hops, 2);
  });

  test('a saved text too short to hold a record decodes here, because a hop costs more', () async {
    SharedPreferences.setMockInitialValues({
      'bookfin.playback.v1.fred': jsonEncode({'speed': 1.5}),
    });
    final hop = CountingHop();
    final store = LocalResumeStore(hop: hop.call);

    expect((await store.read('fred'))!['speed'], 1.5);
    expect(hop.hops, 0);
  });

  test(
    'a change drops the kept view, so the next read shows the change',
    () async {
      await seedLargeAccount();
      final store = LocalResumeStore(
        openDatabase: () async => database,
        hop: CountingHop().call,
      );
      await store.read('alice');
      await store.reading.write('alice', {
        'version': 1,
        'fontSize': 30,
        'resumes': [page(8)],
        'bookmarks': <dynamic>[],
      });

      final reading = (await store.reading.read('alice'))!;

      expect(reading['fontSize'], 30);
      expect(reading['resumes'].single['anchor'], jsonEncode({'page': 8}));
      await store.checkInvariants();
    },
  );

  test('a large account is read from the record file in its hop, so no record crosses the UI isolate', () async {
    await seedLargeAccount();
    final hop = CountingHop();
    final store = LocalResumeStore(
      openDatabase: () async => database,
      hop: hop.call,
    );

    final listening = (await store.read('alice'))!;

    expect(hop.hops, 1);
    expect(listening['history'], hasLength(20));
    expect(listening['resumes']['book'].single['milliseconds'], 30000);
    expect(
      '${hop.inputs.single}'.contains('Hop fixture'),
      isFalse,
      reason: 'the input of the hop carries no record',
    );
    await store.checkInvariants();
  });

  test('a place saved on the UI isolate while a hop reads the record file stays on the phone', () async {
    await seedLargeAccount();
    final hop = CountingHop();
    final store = LocalResumeStore(
      openDatabase: () async => database,
      hop: hop.call,
    );
    // Another owner of the same connection saves while the hop reads.
    final other = LocalResumeStore(openDatabase: () async => database);
    hop.beside = () => other.save('bob', resume(42000));

    final listening = (await store.read('alice'))!;

    expect(listening['resumes']['book'].single['milliseconds'], 30000);
    final restarted = LocalResumeStore(openDatabase: () async => database);
    expect(
      (await restarted.read('bob'))!['resumes']['book'].single['milliseconds'],
      42000,
    );
    expect((await restarted.read('alice'))!['history'], hasLength(20));
  });

  test('damaged pages that a hop read finds set the record file aside, and a place saved after them stays', () async {
    await seedLargeAccount();
    await database.close();
    // The rows of the actions are damaged, and their index is not, so only
    // a read of the payloads finds the damage.
    final sql = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await sql.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    final root =
        (await sql.query(
              'sqlite_master',
              columns: ['rootpage'],
              where: "name = 'record_actions'",
            )).single['rootpage']
            as int;
    await sql.close();
    final bytes = await File(path).readAsBytes();
    bytes.fillRange((root - 1) * 4096, root * 4096, 0xff);
    await File(path).writeAsBytes(bytes, flush: true);
    final reopened = await RecordDatabase.open(
      factory: databaseFactoryFfi,
      path: path,
    );
    addTearDown(reopened.close);
    final hop = CountingHop();
    final store = LocalResumeStore(
      openDatabase: () async => reopened,
      hop: hop.call,
    );

    expect(await store.read('alice'), isNull);
    expect(hop.hops, 1);
    expect(store.setAside('alice'), isTrue);
    expect(reopened.keptFile, isNotNull);
    await store.save('alice', resume(99000));
    final restarted = LocalResumeStore(openDatabase: () async => reopened);
    expect(
      (await restarted.read(
        'alice',
      ))!['resumes']['book'].single['milliseconds'],
      99000,
    );
    await restarted.checkInvariants();
  });

  test('a damaged large account is set aside in the same hop and the store keeps saving', () async {
    await seedLargeAccount();
    final sql = await databaseFactoryFfi.openDatabase(path);
    await sql.rawUpdate(
      "UPDATE record_actions SET payload = '[]' WHERE rowid = (SELECT MIN(rowid) FROM record_actions)",
    );
    // The connection is the same instance as the store's, which the test
    // closes at its end.
    final before = await database.rows('alice');
    final hop = CountingHop();
    final store = LocalResumeStore(
      openDatabase: () async => database,
      hop: hop.call,
    );

    await store.read('alice');
    expect(hop.hops, 1);
    expect(store.setAside('alice'), isTrue);
    await store.save('alice', resume(99000));

    final kept = await sql.query('set_aside_record_actions', orderBy: 'rowid');
    expect([for (final row in kept) row['payload']], before!.payloads);
    expect(
      (await sql.query('set_aside_record_accounts')).single['metadata'],
      before.metadata,
    );
  });

  test('a large account moves from the format before the journal into the database in one hop', () async {
    SharedPreferences.setMockInitialValues({
      'bookfin.playback.v1.dana': jsonEncode({
        ...settings(),
        'history': [for (var index = 0; index < 40; index++) event('h$index')],
        'bookmarks': <dynamic>[],
        'resumes': <String, dynamic>{},
      }),
    });
    final hop = CountingHop();
    final store = LocalResumeStore(
      openDatabase: () async => database,
      hop: hop.call,
    );

    expect((await store.read('dana'))!['history'], hasLength(40));
    expect(hop.hops, 1);
    expect((await database.rows('dana'))!.payloads, hasLength(40));
    await store.checkInvariants();
    final restarted = LocalResumeStore(openDatabase: () async => database);
    expect((await restarted.read('dana'))!['history'], hasLength(40));
  });

  /// A record file at a new path, opened with [files].
  Future<RecordDatabase> openWith(DatabaseFactory files) async {
    final records = await RecordDatabase.open(
      factory: files,
      path: '$path.other',
    );
    addTearDown(records.close);
    return records;
  }

  for (final (reason, error) in [
    (
      'SQLite cannot open its file',
      SqliteFailure('unable to open', cannotOpen),
    ),
    ('its isolate cannot reach SQLite', StateError('no binding')),
  ]) {
    test(
      'a large account restores through the UI isolate\'s connection when the hop read fails because $reason, and nothing is reported',
      () async {
        final records = await openWith(
          FailingReadOnlyOpen(databaseFactoryFfi, error),
        );
        await seedLargeAccount(records);
        final hop = CountingHop();
        final store = LocalResumeStore(
          openDatabase: () async => records,
          hop: hop.call,
        );

        final listening = (await store.read('alice'))!;
        final reading = (await store.reading.read('alice'))!;

        expect(listening['history'], hasLength(20));
        expect(listening['resumes']['book'].single['milliseconds'], 30000);
        expect(reading['resumes'].single['anchor'], jsonEncode({'page': 7}));
        expect(
          '${hop.inputs.last}'.contains('Hop fixture'),
          isTrue,
          reason: 'the rows that the UI isolate read still restore in a hop',
        );
        expect(store.setAside('alice'), isFalse);
        expect(records.keptFile, isNull);
        await store.checkInvariants();
      },
    );
  }

  test('damage that the hop read reports sets the record file aside, and the UI isolate does not read the file again', () async {
    // The file is intact, so only the hop's report of damage can make the
    // account disappear, and a read on the UI isolate would find it.
    final records = await openWith(
      FailingReadOnlyOpen(
        databaseFactoryFfi,
        SqliteFailure('malformed', corrupt),
      ),
    );
    await seedLargeAccount(records);
    final store = LocalResumeStore(
      openDatabase: () async => records,
      hop: CountingHop().call,
    );

    expect(await store.read('alice'), isNull);
    expect(store.setAside('alice'), isTrue);
    expect(records.keptFile, isNotNull);
    await store.save('alice', resume(99000));
    // A restart opens the file with the platform's binding again, whose
    // reads report no damage.
    await records.close();
    final reopened = await RecordDatabase.open(
      factory: databaseFactoryFfi,
      path: '$path.other',
    );
    addTearDown(reopened.close);
    final restarted = LocalResumeStore(openDatabase: () async => reopened);
    expect(
      (await restarted.read(
        'alice',
      ))!['resumes']['book'].single['milliseconds'],
      99000,
    );
  });
}
