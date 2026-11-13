import 'dart:convert';
import 'dart:io';

import 'package:bookfin/sync/transport.dart';
import 'package:bookfin/playback/database.dart';
import 'package:bookfin/playback/store.dart';
import 'package:bookfin/sync/journal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fixture.dart';

Map<String, dynamic> listening(int milliseconds) => {
  'version': 3,
  'bookmarks': <dynamic>[],
  'history': <dynamic>[],
  'resumes': {
    'edition': {
      'source': 'source',
      'revision': 'revision',
      'milliseconds': milliseconds,
    },
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  HttpOverrides.global = null;

  test('opening an actual version-one SQLite account migrates all immutable positions once', () async {
    SharedPreferences.setMockInitialValues({});
    final directory = await Directory.systemTemp.createTemp('bookfin-v1-');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/records.sqlite';
    final legacy = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (database, _) => database.execute(
          'CREATE TABLE accounts (account TEXT PRIMARY KEY NOT NULL, payload TEXT NOT NULL)',
        ),
      ),
    );
    final journal = RecordJournal('alice', 'original');
    final address = jsonEncode([
      'audio',
      'resumes',
      jsonEncode(['edition', 'source', 'revision']),
    ]);
    for (final milliseconds in [1000, 2000]) {
      journal.change(address, {
        'edition': 'edition',
        ...listening(milliseconds)['resumes']['edition'] as Map,
      });
    }
    journal.cursor = 27;
    await legacy.insert('accounts', {
      'account': 'alice',
      'payload': jsonEncode({...listening(2000), 'sync': journal.encode()}),
    });
    await legacy.close();
    final database = await RecordDatabase.open(
      factory: databaseFactoryFfi,
      path: path,
    );
    addTearDown(database.close);
    final store = LocalResumeStore(openDatabase: () async => database);
    expect(
      (await store.read('alice'))!['resumes']['edition'].single['milliseconds'],
      2000,
    );
    expect(
      (jsonDecode((await database.read('alice'))!) as Map)['sync'],
      journal.encode(),
    );
    await store.write('alice', listening(3000));
    final restarted = LocalResumeStore(openDatabase: () async => database);
    expect(
      (await restarted.read(
        'alice',
      ))!['resumes']['edition'].single['milliseconds'],
      3000,
    );
    expect(
      (jsonDecode((await database.read('alice'))!) as Map)['sync']['actions'],
      hasLength(3),
    );
    await restarted.checkInvariants();
  });

  Future<({String path, RecordDatabase records, Database sql})>
  storage() async {
    SharedPreferences.setMockInitialValues({});
    final directory = await Directory.systemTemp.createTemp('bookfin-rows-');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/records.sqlite';
    final records = await RecordDatabase.open(
      factory: databaseFactoryFfi,
      path: path,
    );
    final sql = await databaseFactoryFfi.openDatabase(path);
    addTearDown(records.close);
    return (path: path, records: records, sql: sql);
  }

  Future<void> forbidWholeAccountReplacement(Database sql) async {
    for (final operation in ['INSERT', 'UPDATE', 'DELETE']) {
      await sql.execute('''
        CREATE TRIGGER reject_account_${operation.toLowerCase()}
        BEFORE $operation ON accounts BEGIN
          SELECT RAISE(ABORT, 'retained account payload must not be rewritten');
        END
      ''');
    }
  }

  test('ordinary saves retain every position without replacing the whole account payload', () async {
    final disk = await storage();
    final store = LocalResumeStore(openDatabase: () async => disk.records);
    await store.write('alice', listening(1000));
    await forbidWholeAccountReplacement(disk.sql);
    await store.write('alice', listening(2000));
    await store.write('alice', listening(3000));
    await disk.records.close();
    final reopened = await RecordDatabase.open(
      factory: databaseFactoryFfi,
      path: disk.path,
    );
    addTearDown(reopened.close);
    final restarted = LocalResumeStore(openDatabase: () async => reopened);
    expect(
      (await restarted.read(
        'alice',
      ))!['resumes']['edition'].single['milliseconds'],
      3000,
    );
    final saved = jsonDecode((await reopened.read('alice'))!) as Map;
    expect(
      (saved['sync']['actions'] as List).map(
        (action) => action['value']['milliseconds'],
      ),
      [1000, 2000, 3000],
    );
    expect(saved['sync']['pending'], hasLength(3));
    expect(await restarted.read('bob'), isNull);
  });

  test(
    'acknowledgments survive restart without replacing retained payloads',
    () async {
      final disk = await storage();
      final fixture = await SyncFixture.open();
      addTearDown(fixture.close);
      final account = fixture.session.scope.key;
      final store = LocalResumeStore(openDatabase: () async => disk.records);
      await store.write(account, listening(1000));
      await store.write(account, listening(2000));
      await forbidWholeAccountReplacement(disk.sql);
      await RecordTransport(store).synchronize(fixture.session, fixture.client);
      await disk.records.close();
      final reopened = await RecordDatabase.open(
        factory: databaseFactoryFfi,
        path: disk.path,
      );
      addTearDown(reopened.close);
      final saved = jsonDecode((await reopened.read(account))!) as Map;
      expect(saved['sync']['pending'], isEmpty);
      expect(saved['sync']['actions'], hasLength(2));
      expect(saved['sync']['cursor'], 2);
    },
  );

  test('migration failure rolls back every row and leaves the legacy account retryable', () async {
    final disk = await storage();
    final legacy = listening(1000);
    final journal = RecordJournal('alice', 'original');
    final address = jsonEncode([
      'audio',
      'resumes',
      jsonEncode(['edition', 'source', 'revision']),
    ]);
    for (final milliseconds in [1000, 2000, 3000]) {
      journal.change(address, {
        'edition': 'edition',
        ...listening(milliseconds)['resumes']['edition'] as Map,
      });
    }
    journal.cursor = 19;
    legacy['sync'] = journal.encode();
    final original = jsonEncode(legacy);
    await disk.records.write('alice', original);
    await disk.sql.execute(
      "CREATE TRIGGER fail_migration BEFORE DELETE ON accounts BEGIN SELECT RAISE(ABORT, 'disk full during migration'); END",
    );
    final store = LocalResumeStore(openDatabase: () async => disk.records);
    await expectLater(store.read('alice'), throwsA(isA<DatabaseException>()));
    expect((await disk.sql.query('accounts')).single['payload'], original);
    for (final table in [
      'record_accounts',
      'record_actions',
      'record_versions',
      'record_coverage',
    ]) {
      expect(await disk.sql.query(table), isEmpty);
    }
    await disk.sql.execute('DROP TRIGGER fail_migration');
    expect(
      (await store.read('alice'))!['resumes']['edition'].single['milliseconds'],
      3000,
    );
    expect(await disk.sql.query('accounts'), isEmpty);
    final saved = jsonDecode((await disk.records.read('alice'))!) as Map;
    expect(saved['sync'], journal.encode());
    await store.checkInvariants();
  });

  test('a failed position transaction cannot advance records pending identity or causal coverage', () async {
    final disk = await storage();
    final store = LocalResumeStore(openDatabase: () async => disk.records);
    await store.write('alice', listening(1000));
    final original = jsonDecode((await disk.records.read('alice'))!) as Map;
    await disk.sql.execute(
      "CREATE TRIGGER fail_position BEFORE INSERT ON record_coverage BEGIN SELECT RAISE(ABORT, 'disk full during coverage'); END",
    );
    await expectLater(
      store.write('alice', listening(2000)),
      throwsA(isA<DatabaseException>()),
    );
    expect(jsonDecode((await disk.records.read('alice'))!), original);
    expect(
      (await store.read('alice'))!['resumes']['edition'].single['milliseconds'],
      1000,
    );
    await disk.sql.execute('DROP TRIGGER fail_position');
    await store.write('alice', listening(2000));
    final saved = jsonDecode((await disk.records.read('alice'))!) as Map;
    expect(saved['sync']['actions'], hasLength(2));
    expect(saved['sync']['pending'], hasLength(2));
    expect((saved['sync']['actions'] as List).last['sequence'], 2);
    await store.checkInvariants();
  });

  test('a failed acknowledgment retains the same upload identity for a restart and retry', () async {
    final disk = await storage();
    final fixture = await SyncFixture.open();
    addTearDown(fixture.close);
    final account = fixture.session.scope.key;
    final store = LocalResumeStore(openDatabase: () async => disk.records);
    await store.write(account, listening(1000));
    final original = jsonDecode((await disk.records.read(account))!) as Map;
    await disk.sql.execute(
      "CREATE TRIGGER fail_ack BEFORE UPDATE OF pending ON record_actions BEGIN SELECT RAISE(ABORT, 'disk full during acknowledgment'); END",
    );
    await expectLater(
      RecordTransport(store).synchronize(fixture.session, fixture.client),
      throwsA(isA<DatabaseException>()),
    );
    expect(fixture.objects, hasLength(1));
    expect(jsonDecode((await disk.records.read(account))!), original);
    await disk.sql.execute('DROP TRIGGER fail_ack');
    await disk.records.close();
    final reopened = await RecordDatabase.open(
      factory: databaseFactoryFfi,
      path: disk.path,
    );
    addTearDown(reopened.close);
    final restarted = LocalResumeStore(openDatabase: () async => reopened);
    await RecordTransport(restarted)
        .synchronize(fixture.session, fixture.client);
    expect(fixture.objects, hasLength(1));
    final saved = jsonDecode((await reopened.read(account))!) as Map;
    expect(saved['sync']['actions'], original['sync']['actions']);
    expect(saved['sync']['pending'], isEmpty);
    expect(saved['sync']['cursor'], 1);
  });

  test('a held deletion survives restart and applies when its earlier action arrives', () async {
    final disk = await storage();
    final fixture = await SyncFixture.open();
    addTearDown(fixture.close);
    final account = fixture.session.scope.key;
    final remote = RecordJournal(account, 'remote');
    final address = jsonEncode(['audio', 'bookmarks', 'remote-mark']);
    final bookmark = {
      'id': 'remote-mark',
      'title': 'Remote bookmark',
      'position': {
        'edition': 'edition',
        ...listening(900)['resumes']['edition'] as Map,
      },
      'createdAt': '2026-11-02T12:00:00.000Z',
      'bookTitle': 'Book',
      'editionLabel': 'Audio',
    };
    remote.change(address, bookmark);
    remote.change(address, null);
    void publish(Map<String, dynamic> action) {
      final identity = RecordJournal.identity(action);
      fixture.objects[identity] = {
        'Id': identity,
        'Sequence': fixture.objects.length + 1,
        'Payload': jsonEncode(action),
        'Deleted': false,
      };
    }

    publish(remote.uploads.last);
    await RecordTransport(
      LocalResumeStore(openDatabase: () async => disk.records),
    ).synchronize(fixture.session, fixture.client);
    final held = jsonDecode((await disk.records.read(account))!) as Map;
    expect(held['sync']['actions'], [remote.uploads.last]);
    expect(held['sync']['cursor'], 1);
    expect(await disk.sql.query('record_coverage'), isEmpty);
    await disk.records.close();
    final reopened = await RecordDatabase.open(
      factory: databaseFactoryFfi,
      path: disk.path,
    );
    addTearDown(reopened.close);
    final restarted = LocalResumeStore(openDatabase: () async => reopened);
    expect((await restarted.read(account))!['bookmarks'], isEmpty);
    await restarted.write(account, listening(2000));
    publish(remote.uploads.first);
    await RecordTransport(restarted)
        .synchronize(fixture.session, fixture.client);
    expect((await restarted.read(account))!['bookmarks'], isEmpty);
    final stale = RecordJournal(account, 'late');
    stale.change(address, bookmark);
    fixture.publish(stale);
    await RecordTransport(restarted)
        .synchronize(fixture.session, fixture.client);
    expect((await restarted.read(account))!['bookmarks'], isEmpty);
    expect((await restarted.conflicts(account))[address], hasLength(2));
    final saved = jsonDecode((await reopened.read(account))!) as Map;
    expect(saved['sync']['actions'], containsAll(remote.uploads));
    expect(
      (saved['sync']['actions'] as List).singleWhere(
        (action) => action['replica'] == 'late',
      ),
      stale.uploads.single,
    );
    expect(saved['sync']['pending'], isEmpty);
    await restarted.checkInvariants();
  });

  test('an altered server copy replaces the saved action, keeps the saved copy aside, and advances the discovery cursor', () async {
    final disk = await storage();
    final fixture = await SyncFixture.open();
    addTearDown(fixture.close);
    final account = fixture.session.scope.key;
    final remote = RecordJournal(account, 'remote');
    final address = jsonEncode([
      'audio',
      'resumes',
      jsonEncode(['edition', 'source', 'revision']),
    ]);
    remote.change(address, {
      'edition': 'edition',
      ...listening(900)['resumes']['edition'] as Map,
    });
    fixture.publish(remote);
    final store = LocalResumeStore(openDatabase: () async => disk.records);
    await RecordTransport(store).synchronize(fixture.session, fixture.client);
    final original = jsonDecode((await disk.records.read(account))!) as Map;
    final action = remote.uploads.single;
    final changed = jsonDecode(jsonEncode(action)) as Map<String, dynamic>;
    changed['value']['milliseconds'] = 1200;
    fixture.objects[RecordJournal.identity(action)] = {
      'Id': RecordJournal.identity(action),
      'Sequence': 2,
      'Payload': jsonEncode(changed),
      'Deleted': false,
    };
    // The server's copy wins (ta-tso8): an action never changes, and the
    // server holds the copy uploaded before any damage on this phone.
    final report = await RecordTransport(store)
        .synchronize(fixture.session, fixture.client);
    expect(report.replaced, 1);
    final replaced = jsonDecode((await disk.records.read(account))!) as Map;
    expect(replaced['sync']['actions'], [changed]);
    expect(replaced['sync']['cursor'], 2);
    final kept = await disk.sql.query('set_aside_record_actions');
    expect(
      kept.map((row) => jsonDecode(row['payload'] as String)),
      contains(equals(action)),
    );
    expect(original['sync']['actions'], [action]);
  });

  test('a legacy account with a damaged superseded value is kept aside when it moves into the record tables', () async {
    final disk = await storage();
    final journal = RecordJournal('alice', 'original');
    final address = jsonEncode([
      'audio',
      'resumes',
      jsonEncode(['edition', 'source', 'revision']),
    ]);
    journal.change(address, {
      'edition': 'edition',
      ...listening(1000)['resumes']['edition'] as Map,
    });
    journal.change(address, {
      'edition': 'edition',
      ...listening(2000)['resumes']['edition'] as Map,
    });
    final damaged = jsonDecode(
      jsonEncode({...listening(2000), 'sync': journal.encode()}),
    ) as Map;
    damaged['sync']['actions'][0]['value']['edition'] = 7;
    final raw = jsonEncode(damaged);
    await disk.records.write('alice', raw);
    final store = LocalResumeStore(openDatabase: () async => disk.records);
    await store.read('alice');
    expect(store.setAside('alice'), isTrue);
    expect((await disk.sql.query('set_aside_accounts')).single['payload'], raw);
    expect(await disk.sql.query('accounts'), isEmpty);
    expect(await disk.sql.query('record_accounts'), hasLength(1));
    await store.checkInvariants();
  });

  test('reordered actions wake cross-installation dependencies after restart without duplicate versions', () async {
    final disk = await storage();
    final fixture = await SyncFixture.open();
    addTearDown(fixture.close);
    final account = fixture.session.scope.key;
    Map<String, dynamic> bookmark(String identity) => {
      'id': identity,
      'title': identity,
      'position': {
        'edition': 'edition',
        ...listening(900)['resumes']['edition'] as Map,
      },
      'createdAt': '2026-11-02T12:00:00.000Z',
      'bookTitle': 'Book',
      'editionLabel': 'Audio',
    };
    final first = RecordJournal(account, 'first');
    first.change(jsonEncode(['audio', 'bookmarks', 'one']), bookmark('one'));
    final second = RecordJournal(account, 'second')..receive(first.uploads);
    second.change(
      jsonEncode(['audio', 'bookmarks', 'joined']),
      bookmark('joined'),
    );
    first.change(jsonEncode(['audio', 'bookmarks', 'two']), bookmark('two'));
    fixture.publish(second);
    final later = first.uploads.last;
    fixture.objects[RecordJournal.identity(later)] = {
      'Id': RecordJournal.identity(later),
      'Sequence': 2,
      'Payload': jsonEncode(later),
      'Deleted': false,
    };
    await RecordTransport(
      LocalResumeStore(openDatabase: () async => disk.records),
    ).synchronize(fixture.session, fixture.client);
    await disk.records.close();
    final reopened = await RecordDatabase.open(
      factory: databaseFactoryFfi,
      path: disk.path,
    );
    addTearDown(reopened.close);
    final restarted = LocalResumeStore(openDatabase: () async => reopened);
    expect((await restarted.read(account))!['bookmarks'], isEmpty);
    fixture.publish(first);
    await RecordTransport(restarted)
        .synchronize(fixture.session, fixture.client);
    expect(
      ((await restarted.read(account))!['bookmarks'] as List).map(
        (mark) => mark['id'],
      ),
      unorderedEquals(['one', 'two', 'joined']),
    );
    final duplicate = second.uploads.single;
    fixture.objects[RecordJournal.identity(duplicate)]!['Sequence'] = 4;
    await RecordTransport(restarted)
        .synchronize(fixture.session, fixture.client);
    expect(await restarted.conflicts(account), isEmpty);
    final saved = jsonDecode((await reopened.read(account))!) as Map;
    expect(saved['sync']['actions'], hasLength(3));
    expect(saved['sync']['cursor'], 4);
    await restarted.checkInvariants();
  });

  test('a conflict remains readable after a held version applies before a later concurrent arrival and restart', () async {
    final disk = await storage();
    final fixture = await SyncFixture.open();
    addTearDown(fixture.close);
    final account = fixture.session.scope.key;
    final dependency = RecordJournal(account, 'dependency');
    dependency.change(jsonEncode(['audio', 'bookmarks', 'dependency']), {
      'id': 'dependency',
      'title': 'Dependency',
      'position': {
        'edition': 'edition',
        ...listening(900)['resumes']['edition'] as Map,
      },
      'createdAt': '2026-11-02T12:00:00.000Z',
      'bookTitle': 'Book',
      'editionLabel': 'Audio',
    });
    final address = jsonEncode([
      'audio',
      'resumes',
      jsonEncode(['edition', 'source', 'revision']),
    ]);
    final held = RecordJournal(account, 'held')..receive(dependency.uploads);
    held.change(address, {
      'edition': 'edition',
      ...listening(900)['resumes']['edition'] as Map,
    });
    final store = LocalResumeStore(openDatabase: () async => disk.records);
    fixture.publish(held);
    await RecordTransport(store).synchronize(fixture.session, fixture.client);
    fixture.publish(dependency);
    await RecordTransport(store).synchronize(fixture.session, fixture.client);
    final concurrent = RecordJournal(account, 'concurrent');
    concurrent.change(address, {
      'edition': 'edition',
      ...listening(100)['resumes']['edition'] as Map,
    });
    fixture.publish(concurrent);
    await RecordTransport(store).synchronize(fixture.session, fixture.client);
    expect((await store.conflicts(account))[address], hasLength(2));
    await disk.records.close();
    final reopened = await RecordDatabase.open(
      factory: databaseFactoryFfi,
      path: disk.path,
    );
    addTearDown(reopened.close);
    final restarted = LocalResumeStore(openDatabase: () async => reopened);
    expect(
      (await restarted.conflicts(
        account,
      ))[address]!.map((action) => action['value']['milliseconds']),
      unorderedEquals([900, 100]),
    );
    expect((await restarted.read(account))!['resumes'], isEmpty);
    await restarted.checkInvariants();
  });
}
