import 'dart:convert';
import 'dart:io';

import 'package:bookfin/catalog/jellyfin.dart';
import 'package:bookfin/playback/database.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:bookfin/playback/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../sync/fixture.dart';

// Each test names one way that a listening position could be lost, and shows
// that the record store keeps the position through it.

const _settings = <String, dynamic>{
  'version': 3,
  'selected': 'edition',
  'speed': 1.0,
  'backward': 10,
  'forward': 30,
};

/// The change set that moves the place in the audio edition `edition` to
/// [milliseconds].
ListeningChanges _place(int milliseconds) => ListeningChanges(
  _settings,
  resumes: {
    'edition': [
      {
        'source': 'source',
        'revision': 'revision',
        'sources': '[["source","revision"]]',
        'milliseconds': milliseconds,
        'pendingOffline': false,
      },
    ],
  },
);

/// A listening bookmark [id] at [milliseconds] in the audio edition
/// `edition`, as JSON.
Map<String, dynamic> _bookmark(String id, int milliseconds) => {
  'id': id,
  'position': {
    'edition': 'edition',
    'source': 'source',
    'revision': 'revision',
    'milliseconds': milliseconds,
  },
  'createdAt': '2026-11-07T12:00:00.000Z',
  'title': 'Mark',
  'bookTitle': 'Book',
  'editionLabel': 'Recording',
};

/// The saved place in `edition` in [snapshot], or null when it has none.
int? _savedPlace(Map<String, dynamic>? snapshot) {
  final resumes = snapshot?['resumes'] as Map<String, dynamic>?;
  final places = resumes?['edition'] as List?;
  return places == null ? null : (places.single as Map)['milliseconds'] as int;
}

/// A phone: one SQLite record file and the store that a fresh app start
/// would build over it.
class _Phone {
  _Phone._(this.path, this.database);
  final String path;
  RecordDatabase database;
  late LocalResumeStore store = _storeOver(database);

  static LocalResumeStore _storeOver(RecordDatabase database) =>
      LocalResumeStore(openDatabase: () async => database);

  static Future<_Phone> open(String name) async {
    final directory = await Directory.systemTemp.createTemp('bookfin-$name-');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/records.sqlite';
    final phone = _Phone._(
      path,
      await RecordDatabase.open(factory: databaseFactoryFfi, path: path),
    );
    addTearDown(() => phone.database.close());
    return phone;
  }

  /// Drops everything that the app held in memory, as a killed process does,
  /// and starts again from the file.
  Future<void> restart() async {
    await database.close();
    database = await RecordDatabase.open(
      factory: databaseFactoryFfi,
      path: path,
    );
    store = _storeOver(database);
  }
}

/// A Jellyfin client whose personal-record uploads fail while [offline].
class _Connection extends JellyfinClient {
  _Connection(SyncFixture fixture)
    : super(fixture.client.server, deviceId: 'durability');
  bool offline = false;

  @override
  Future<Map<String, dynamic>> uploadPersonalRecord(
    JellyfinSession session,
    String identity,
    String payload,
  ) {
    if (offline) throw const SocketException('The network is unavailable.');
    return super.uploadPersonalRecord(session, identity, payload);
  }
}

/// A preference platform that keeps its values in memory and counts writes.
class _CountingPreferences extends SharedPreferencesStorePlatform {
  final values = <String, Object>{};
  final writes = <String>[];
  bool failWrites = false;

  /// Writes to a key that starts with this fail too.
  String? failPrefix;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    writes.add(key);
    if (failWrites || (failPrefix != null && key.startsWith(failPrefix!))) {
      throw const FileSystemException('The disk is full.');
    }
    values[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    writes.add(key);
    values.remove(key);
    return true;
  }

  @override
  Future<bool> clear() async => throw UnimplementedError();

  @override
  Future<Map<String, Object>> getAll() async => Map.of(values);
}

/// A second SQLite connection to the record file at [path], as another
/// process would hold. sqflite shares one connection per path by default.
Future<Database> _separateConnection(String path) => databaseFactoryFfi
    .openDatabase(path, options: OpenDatabaseOptions(singleInstance: false));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  HttpOverrides.global = null;
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('a kill in the middle of a write', () {
    test('leaves the last saved listening place on the phone', () async {
      final phone = await _Phone.open('kill');
      const account = 'alice';
      await phone.store.save(account, _place(10000));
      // A trigger fails the write after it changed some rows, as a process
      // killed mid-write stops after some of its statements.
      final sql = await _separateConnection(phone.path);
      await sql.execute(
        "CREATE TRIGGER cut AFTER INSERT ON record_versions BEGIN SELECT RAISE(ABORT, 'killed'); END",
      );
      await expectLater(
        phone.store.save(account, _place(20000)),
        throwsA(anything),
      );
      await sql.execute('DROP TRIGGER cut');
      await sql.close();

      await phone.restart();
      expect(_savedPlace(await phone.store.read(account)), 10000);
      await phone.store.checkInvariants();
    });

    test('without a database, one save is one preference write that holds the whole account', () async {
      final preferences = _CountingPreferences();
      SharedPreferencesStorePlatform.instance = preferences;
      SharedPreferences.resetStatic();
      await LocalResumeStore().save('alice', _place(10000));
      preferences.writes.clear();

      await LocalResumeStore().save('alice', _place(20000));
      expect(preferences.writes, ['flutter.bookfin.playback.v1.alice']);
      expect(_savedPlace(await LocalResumeStore().read('alice')), 20000);
    });

    test(
      'without a database, a failed preference write keeps the previous place',
      () async {
        final preferences = _CountingPreferences();
        SharedPreferencesStorePlatform.instance = preferences;
        SharedPreferences.resetStatic();
        final store = LocalResumeStore();
        await store.save('alice', _place(10000));
        preferences.failWrites = true;
        await expectLater(
          store.save('alice', _place(20000)),
          throwsA(anything),
        );
        preferences.failWrites = false;

        // A new process starts without the plugin's memory cache.
        SharedPreferences.resetStatic();
        expect(_savedPlace(await LocalResumeStore().read('alice')), 10000);
      },
    );
  });

  test(
    'a kill while a phone saves places from another device does not skip them',
    () async {
      final server = await SyncFixture.open();
      addTearDown(server.close);
      final phone = await _Phone.open('receiving');
      final tablet = await _Phone.open('sending');
      final account = server.session.scope.key;
      await tablet.store.save(account, _place(30000));
      await tablet.store.synchronize(server.session, server.client);
      final sql = await _separateConnection(phone.path);
      await sql.execute(
        "CREATE TRIGGER cut AFTER INSERT ON record_actions BEGIN SELECT RAISE(ABORT, 'killed'); END",
      );
      await expectLater(
        phone.store.synchronize(server.session, server.client),
        throwsA(anything),
      );
      await sql.execute('DROP TRIGGER cut');
      await sql.close();

      await phone.restart();
      await phone.store.synchronize(server.session, server.client);
      expect(_savedPlace(await phone.store.read(account)), 30000);
    },
  );

  group('a damaged preference value', () {
    const key = 'bookfin.playback.v1.alice';

    /// The saved preference values, as a new process reads them.
    Future<Map<String, String>> saved() async {
      SharedPreferences.resetStatic();
      final preferences = await SharedPreferences.getInstance();
      return {
        for (final name in preferences.getKeys())
          name: preferences.getString(name)!,
      };
    }

    /// The text of a journal-format account whose second action, a bookmark,
    /// names another bookmark than its record, after a place at 10000.
    Future<String> damagedBookmark() async {
      await LocalResumeStore().save('alice', _place(10000));
      await LocalResumeStore().save(
        'alice',
        ListeningChanges(
          _settings,
          bookmarks: {'mark': _bookmark('mark', 15000)},
        ),
      );
      final value = jsonDecode((await saved())[key]!) as Map<String, dynamic>;
      final actions = (value['sync'] as Map)['actions'] as List;
      ((actions.last as Map)['value'] as Map)['id'] = 'another mark';
      return jsonEncode(value);
    }

    test('is kept aside under its own key', () async {
      const damaged = '{"resumes": "not an object"';
      SharedPreferences.setMockInitialValues({key: damaged});

      await LocalResumeStore().read('alice');
      final kept = (await saved()).entries.where(
        (entry) => entry.key.startsWith('bookfin.damaged-records.v1.alice.'),
      );
      expect(kept.single.value, damaged);
    });

    test(
      'gives back the records that still decode and skips the broken one',
      () async {
        final damaged = await damagedBookmark();
        SharedPreferences.setMockInitialValues({key: damaged});

        final snapshot = await LocalResumeStore().read('alice');
        expect(_savedPlace(snapshot), 10000);
        expect(snapshot!['bookmarks'], isEmpty);
      },
    );

    test(
      'whose actions contradict each other still lets the account save places',
      () async {
        Map<String, dynamic> action(
          int sequence,
          String record,
          List<String> preserve,
        ) => {
          'version': 1,
          'account': 'alice',
          'replica': 'old',
          'sequence': sequence,
          'context': {'old': sequence - 1},
          'record': jsonEncode(['audio', 'history', record]),
          'value': null,
          'preserve': preserve,
        };
        // The second action preserves a version of another record.
        final damaged = jsonEncode({
          ..._settings,
          'sync': {
            'version': 1,
            'replica': 'old',
            'cursor': 0,
            'actions': [
              action(1, 'first', []),
              action(2, 'second', ['action.old.1']),
            ],
            'pending': <String>[],
          },
        });
        SharedPreferences.setMockInitialValues({key: damaged});
        await LocalResumeStore().save('alice', _place(20000));

        expect(_savedPlace(await LocalResumeStore().read('alice')), 20000);
        expect(
          (await saved()).entries
              .where(
                (entry) => entry.key.startsWith('bookfin.damaged-records.'),
              )
              .single
              .value,
          damaged,
        );
      },
    );

    test('keeps a place saved after it through a restart', () async {
      SharedPreferences.setMockInitialValues({key: '[]'});
      await LocalResumeStore().save('alice', _place(20000));

      SharedPreferences.resetStatic();
      expect(_savedPlace(await LocalResumeStore().read('alice')), 20000);
    });

    test('stays where it was when it cannot be copied aside', () async {
      final preferences = _CountingPreferences()
        ..values['flutter.$key'] = '[]'
        ..failPrefix = 'flutter.bookfin.damaged-records.';
      SharedPreferencesStorePlatform.instance = preferences;
      SharedPreferences.resetStatic();

      await expectLater(
        LocalResumeStore().save('alice', _place(20000)),
        throwsA(anything),
      );
      expect(preferences.values, {'flutter.$key': '[]'});
    });
  });

  group('damaged SQLite rows', () {
    /// Every row of the record tables and of the tables that keep damaged
    /// rows, by table, as [sql] reads them.
    Future<Map<String, List<Map<String, Object?>>>> tables(Database sql) async {
      final names = await sql.query(
        'sqlite_master',
        columns: ['name'],
        where: "type = 'table' AND name LIKE 'record_%' OR name LIKE 'set_aside_%' OR name = 'accounts'",
      );
      return {
        for (final row in names)
          row['name'] as String: await sql.query(row['name'] as String),
      };
    }

    test('are kept aside as they were', () async {
      final phone = await _Phone.open('kept-rows');
      await phone.store.save('alice', _place(10000));
      final sql = await _separateConnection(phone.path);
      addTearDown(sql.close);
      await sql.update('record_accounts', {'metadata': '{broken'});
      final before = await tables(sql);

      await phone.restart();
      await phone.store.read('alice');
      expect(phone.store.setAside('alice'), isTrue);
      final after = await tables(sql);
      for (final table in [
        'record_accounts',
        'record_actions',
        'record_versions',
        'record_coverage',
      ]) {
        expect(
          [
            for (final row in after['set_aside_$table']!)
              {...row}..remove('kept_at'),
          ],
          before[table],
          reason: table,
        );
      }
    });

    test(
      'give back the records that still decode and skip the broken one',
      () async {
        final phone = await _Phone.open('salvaged-rows');
        await phone.store.save('alice', _place(10000));
        await phone.store.save(
          'alice',
          ListeningChanges(
            _settings,
            bookmarks: {'mark': _bookmark('mark', 15000)},
          ),
        );
        final sql = await _separateConnection(phone.path);
        addTearDown(sql.close);
        await sql.rawUpdate(
          "UPDATE record_actions SET payload = '{broken' WHERE rowid = (SELECT MAX(rowid) FROM record_actions)",
        );

        await phone.restart();
        final snapshot = await phone.store.read('alice');
        expect(_savedPlace(snapshot), 10000);
        expect(snapshot!['bookmarks'], isEmpty);
        await phone.store.checkInvariants();
      },
    );

    test(
      'keep a place saved after them through a kill and a restart',
      () async {
        final phone = await _Phone.open('rows-then-place');
        await phone.store.save('alice', _place(10000));
        final sql = await _separateConnection(phone.path);
        addTearDown(sql.close);
        await sql.update('record_accounts', {'metadata': '{broken'});

        await phone.restart();
        await phone.store.save('alice', _place(20000));
        await phone.restart();
        expect(_savedPlace(await phone.store.read('alice')), 20000);
        await phone.store.checkInvariants();
      },
    );

    test(
      'stay where they were when the new account cannot be written',
      () async {
        final phone = await _Phone.open('rows-stay');
        await phone.store.save('alice', _place(10000));
        final sql = await _separateConnection(phone.path);
        addTearDown(sql.close);
        await sql.update('record_accounts', {'metadata': '{broken'});
        final before = await tables(sql);
        await sql.execute(
          "CREATE TRIGGER cut AFTER INSERT ON record_actions BEGIN SELECT RAISE(ABORT, 'killed'); END",
        );

        await phone.restart();
        await expectLater(phone.store.read('alice'), throwsA(anything));
        expect(await tables(sql), before);
      },
    );
  });

  group('a SQLite file that cannot be opened', () {
    test('that another connection holds is not set aside', () async {
      final directory = await Directory.systemTemp.createTemp('bookfin-file-');
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}/records.sqlite';
      final holder = await _separateConnection(path);
      await holder.execute('PRAGMA locking_mode=EXCLUSIVE');
      await holder.execute('BEGIN EXCLUSIVE');
      addTearDown(holder.close);

      await expectLater(
        RecordDatabase.open(factory: databaseFactoryFfi, path: path),
        throwsA(isA<DatabaseException>()),
      );
      expect(
        directory.listSync().where((file) => file.path.contains('.damaged-')),
        isEmpty,
      );
    });

    test('is kept aside as it was', () async {
      final directory = await Directory.systemTemp.createTemp('bookfin-file-');
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}/records.sqlite';
      final damaged = List<int>.generate(8192, (index) => index * 7 % 251);
      await File(path).writeAsBytes(damaged);

      final database = await RecordDatabase.open(
        factory: databaseFactoryFfi,
        path: path,
      );
      addTearDown(database.close);
      final kept = directory.listSync().whereType<File>().where(
        (file) => file.path.contains('.damaged-'),
      );
      expect(kept.single.readAsBytesSync(), damaged);
    });

    test(
      'is replaced by a store that keeps a place through a restart',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'bookfin-file-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final path = '${directory.path}/records.sqlite';
        await File(path).writeAsString('not a database ' * 512);

        var database = await RecordDatabase.open(
          factory: databaseFactoryFfi,
          path: path,
        );
        final first = LocalResumeStore(openDatabase: () async => database);
        await first.save('alice', _place(20000));
        expect(first.setAside('alice'), isTrue);
        await database.close();
        database = await RecordDatabase.open(
          factory: databaseFactoryFfi,
          path: path,
        );
        addTearDown(database.close);
        final restarted = LocalResumeStore(openDatabase: () async => database);
        expect(_savedPlace(await restarted.read('alice')), 20000);
        expect(restarted.setAside('alice'), isFalse);
      },
    );
  });

  group('record sync', () {
    late SyncFixture server;
    setUp(() async {
      server = await SyncFixture.open();
      addTearDown(server.close);
    });

    test('a failed sync keeps the place on the phone and sends it on the next sync', () async {
      final phone = await _Phone.open('offline');
      final tablet = await _Phone.open('tablet');
      final account = server.session.scope.key;
      final connection = _Connection(server)..offline = true;
      addTearDown(connection.close);
      await phone.store.save(account, _place(10000));

      await expectLater(
        phone.store.synchronize(server.session, connection),
        throwsA(isA<SocketException>()),
      );
      await phone.restart();
      expect(_savedPlace(await phone.store.read(account)), 10000);

      connection.offline = false;
      await phone.store.synchronize(server.session, connection);
      await tablet.store.synchronize(server.session, connection);
      expect(_savedPlace(await tablet.store.read(account)), 10000);
    });

    test('the first sync of records saved before sync existed sends each record once, without a database', () async {
      final account = server.session.scope.key;
      final legacy = {
        ..._settings,
        'history': <dynamic>[],
        'bookmarks': <dynamic>[],
        'resumes': _place(10000).resumes,
      };
      SharedPreferences.setMockInitialValues({
        'bookfin.playback.v1.$account': jsonEncode(legacy),
      });
      final store = LocalResumeStore();

      await store.synchronize(server.session, server.client);
      expect(server.objects, hasLength(1));
      expect(await store.conflicts(account), isEmpty);
      expect(_savedPlace(await store.read(account)), 10000);
    });

    test(
      'records given back from damaged rows sync without copies or conflicts',
      () async {
        final phone = await _Phone.open('salvage-sync');
        final tablet = await _Phone.open('salvage-tablet');
        final account = server.session.scope.key;
        await phone.store.save(account, _place(10000));
        await phone.store.synchronize(server.session, server.client);
        await phone.store.save(
          account,
          ListeningChanges(
            _settings,
            bookmarks: {'mark': _bookmark('mark', 15000)},
          ),
        );
        final sql = await _separateConnection(phone.path);
        addTearDown(sql.close);
        await sql.update('record_accounts', {'metadata': '{broken'});

        await phone.restart();
        await phone.store.synchronize(server.session, server.client);
        expect(server.objects, hasLength(2));
        expect(await phone.store.conflicts(account), isEmpty);
        await tablet.store.synchronize(server.session, server.client);
        final shown = await tablet.store.read(account);
        expect(_savedPlace(shown), 10000);
        expect((shown!['bookmarks'] as List).single['id'], 'mark');
      },
    );

    test(
      'two devices that moved the same place offline both keep both places',
      () async {
        final phone = await _Phone.open('phone');
        final tablet = await _Phone.open('tablet');
        final account = server.session.scope.key;
        final connection = _Connection(server);
        addTearDown(connection.close);
        await phone.store.save(account, _place(10000));
        await phone.store.synchronize(server.session, connection);
        await tablet.store.synchronize(server.session, connection);

        await phone.store.save(account, _place(20000));
        await tablet.store.save(account, _place(30000));
        for (final device in [phone, tablet, phone]) {
          await device.store.synchronize(server.session, connection);
        }

        for (final device in [phone, tablet]) {
          final versions = (await device.store.conflicts(account)).values
              .expand((versions) => versions)
              .map((action) => action['value']['milliseconds'])
              .toSet();
          expect(versions, {20000, 30000});
        }
        final conflict = (await phone.store.conflicts(account)).entries.single;
        final tabletPlace = conflict.value.firstWhere(
          (action) => action['value']['milliseconds'] == 30000,
        );
        await phone.store.resolve(
          account,
          conflict.key,
          'action.${tabletPlace['replica']}.${tabletPlace['sequence']}',
        );
        final resolved = (await phone.store.read(account))!;
        expect(_savedPlace(resolved), 30000);
        expect(
          (resolved['bookmarks'] as List).map(
            (bookmark) => bookmark['position']['milliseconds'],
          ),
          contains(20000),
        );
      },
    );
  });
}
