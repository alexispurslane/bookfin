import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bookfin/sync/transport.dart';
import 'package:bookfin/catalog/jellyfin.dart';
import 'package:bookfin/playback/database.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:bookfin/playback/store.dart';
import 'package:flutter/foundation.dart' show compute;
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

/// The SQLite files of the FFI binding, in which each record file that
/// opens after the first has a full disk while [full] holds: a write that
/// needs a new page fails with SQLITE_FULL. The pages that the new file
/// starts with fit.
class _FillingDisk implements DatabaseFactory {
  bool full = true;
  int _opened = 0;

  @override
  Future<Database> openDatabase(String path, {OpenDatabaseOptions? options}) {
    final first = _opened++ == 0;
    return databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: options?.version,
        onConfigure: options?.onConfigure,
        onCreate: options?.onCreate,
        onUpgrade: options?.onUpgrade,
        onOpen: (database) async {
          if (!first && full) {
            final pages = (await database.rawQuery('PRAGMA page_count'))
                .single
                .values
                .single;
            await database.rawQuery('PRAGMA max_page_count = $pages');
          }
        },
      ),
    );
  }

  /// Gives the record file at [path] room again, on the connection that the
  /// store holds.
  Future<void> free(String path) async {
    full = false;
    final shared = await databaseFactoryFfi.openDatabase(path);
    await shared.rawQuery('PRAGMA max_page_count = 1073741823');
  }

  @override
  Future<String> getDatabasesPath() => databaseFactoryFfi.getDatabasesPath();
  @override
  Future<void> setDatabasesPath(String path) =>
      databaseFactoryFfi.setDatabasesPath(path);
  @override
  Future<void> deleteDatabase(String path) =>
      databaseFactoryFfi.deleteDatabase(path);
  @override
  Future<bool> databaseExists(String path) =>
      databaseFactoryFfi.databaseExists(path);
  @override
  Future<void> writeDatabaseBytes(String path, Uint8List bytes) =>
      databaseFactoryFfi.writeDatabaseBytes(path, bytes);
  @override
  Future<Uint8List> readDatabaseBytes(String path) =>
      databaseFactoryFfi.readDatabaseBytes(path);
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
      await RecordTransport(tablet.store)
          .synchronize(server.session, server.client);
      final sql = await _separateConnection(phone.path);
      await sql.execute(
        "CREATE TRIGGER cut AFTER INSERT ON record_actions BEGIN SELECT RAISE(ABORT, 'killed'); END",
      );
      await expectLater(
        RecordTransport(phone.store).synchronize(server.session, server.client),
        throwsA(anything),
      );
      await sql.execute('DROP TRIGGER cut');
      await sql.close();

      await phone.restart();
      await RecordTransport(phone.store)
          .synchronize(server.session, server.client);
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

  group('a SQLite file whose pages are damaged after it opened', () {
    /// Writes [bytes] over the last [pages] pages of the record file at
    /// [path], after another connection moved the write-ahead log into it.
    Future<List<int>> damageTail(String path, {required int pages}) async {
      final sql = await _separateConnection(path);
      await sql.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
      await sql.close();
      final file = File(path);
      final bytes = await file.readAsBytes();
      final start = bytes.length - pages * 4096;
      expect(start, greaterThan(4096), reason: 'the schema page stays');
      for (var index = start; index < bytes.length; index++) {
        bytes[index] = index * 7 % 251;
      }
      await file.writeAsBytes(bytes, flush: true);
      return bytes;
    }

    /// Saves listening history for [account] that fills several pages.
    Future<void> fillHistory(LocalResumeStore store, String account) async {
      for (var index = 0; index < 40; index++) {
        await store.save(
          account,
          ListeningChanges(
            _settings,
            bookmarks: {
              'mark-$index': {
                ..._bookmark('mark-$index', index * 1000),
                'title': 'Mark $index ${'·' * 200}',
              },
            },
          ),
        );
      }
    }

    test('is kept aside as it was and reported', () async {
      final phone = await _Phone.open('pages-kept');
      await phone.store.save('alice', _place(10000));
      await fillHistory(phone.store, 'alice');
      await phone.database.close();
      final damaged = await damageTail(phone.path, pages: 4);
      phone.database = await RecordDatabase.open(
        factory: databaseFactoryFfi,
        path: phone.path,
      );
      expect(phone.database.keptFile, isNull, reason: 'the file opens');
      phone.store = LocalResumeStore(openDatabase: () async => phone.database);

      await phone.store.read('alice');
      expect(phone.store.setAside('alice'), isTrue);
      final kept = File(phone.path).parent
          .listSync()
          .whereType<File>()
          .where((file) => RegExp(r'\.damaged-\d+$').hasMatch(file.path));
      expect(kept.single.readAsBytesSync(), damaged);
    });

    test('keeps a place saved after it through a kill and a restart', () async {
      final phone = await _Phone.open('pages-then-place');
      await phone.store.save('alice', _place(10000));
      await fillHistory(phone.store, 'alice');
      await phone.database.close();
      await damageTail(phone.path, pages: 4);
      phone.database = await RecordDatabase.open(
        factory: databaseFactoryFfi,
        path: phone.path,
      );
      phone.store = LocalResumeStore(openDatabase: () async => phone.database);

      await phone.store.read('alice');
      await phone.store.save('alice', _place(20000));
      await phone.restart();
      expect(_savedPlace(await phone.store.read('alice')), 20000);
      expect(phone.store.setAside('alice'), isFalse);
      await phone.store.checkInvariants();
    });

    test('keeps the records of an account that the store had read before it found the damage', () async {
      final phone = await _Phone.open('pages-cached');
      await phone.store.save('alice', _place(10000));
      await phone.store.save(
        'alice',
        ListeningChanges(
          _settings,
          bookmarks: {'mark': _bookmark('mark', 15000)},
        ),
      );
      await fillHistory(phone.store, 'bob');
      await phone.restart();
      expect(_savedPlace(await phone.store.read('alice')), 10000);
      await damageTail(phone.path, pages: 4);

      await phone.store.read('bob');
      expect(phone.store.setAside('bob'), isTrue);
      await phone.store.save('alice', _place(20000));
      await phone.restart();
      final alice = await phone.store.read('alice');
      expect(_savedPlace(alice), 20000);
      expect((alice!['bookmarks'] as List).single['id'], 'mark');
      await phone.store.checkInvariants();
    });
    test('found by a save keeps the place of that save and the records held in memory', () async {
      final phone = await _Phone.open('pages-on-save');
      await phone.store.save(
        'alice',
        ListeningChanges(
          _settings,
          bookmarks: {'mark': _bookmark('mark', 15000)},
        ),
      );
      await fillHistory(phone.store, 'alice');
      await phone.restart();
      await phone.store.read('alice');
      // The store's connection drops the pages that it read, so that the
      // next save reads the damaged pages from the file.
      final shared = await databaseFactoryFfi.openDatabase(phone.path);
      await shared.execute('PRAGMA cache_size = 0');
      await shared.execute('PRAGMA shrink_memory');
      await damageTail(phone.path, pages: 4);

      await phone.store.save('alice', _place(20000));
      expect(phone.store.setAside('alice'), isTrue);
      await phone.restart();
      final alice = await phone.store.read('alice');
      expect(_savedPlace(alice), 20000);
      expect(
        (alice!['bookmarks'] as List).map((mark) => mark['id']),
        contains('mark'),
      );
      await phone.store.checkInvariants();
    });

    /// Writes bytes that are not a page over the first page of [table] and
    /// of each of its indexes in the record file at [path], after another
    /// connection moved the write-ahead log into it. The other tables stay
    /// readable.
    Future<void> damageTable(String path, String table) async {
      final sql = await _separateConnection(path);
      await sql.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
      final roots = [
        for (final row in await sql.query(
          'sqlite_master',
          columns: ['rootpage'],
          where: 'tbl_name = ?',
          whereArgs: [table],
        ))
          row['rootpage'] as int,
      ];
      await sql.close();
      final file = File(path);
      final bytes = await file.readAsBytes();
      for (final root in roots) {
        for (var index = (root - 1) * 4096; index < root * 4096; index++) {
          bytes[index] = 0xff;
        }
      }
      await file.writeAsBytes(bytes, flush: true);
    }

    test('found while a damaged account is replaced keeps the records that still decode and those held in memory', () async {
      final phone = await _Phone.open('pages-on-replace');
      await phone.store.save('alice', _place(10000));
      await phone.store.save(
        'alice',
        ListeningChanges(
          _settings,
          bookmarks: {'mark': _bookmark('mark', 15000)},
        ),
      );
      await fillHistory(phone.store, 'bob');
      final sql = await _separateConnection(phone.path);
      await sql.update('record_accounts', {
        'metadata': '{broken',
      }, where: "account = 'alice'");
      await sql.close();
      // The replacement of Alice's account first copies her rows in the
      // table of the format before the journal, whose page is damaged.
      await damageTable(phone.path, 'accounts');
      await phone.restart();
      expect(phone.database.keptFile, isNull, reason: 'the file opens');
      await phone.store.read('bob');

      final alice = await phone.store.read('alice');
      expect(phone.store.setAside('alice'), isTrue);
      expect(phone.database.keptFile, isNotNull);
      expect(_savedPlace(alice), 10000);
      await phone.store.checkInvariants();
      await phone.restart();
      final restarted = await phone.store.read('alice');
      expect(_savedPlace(restarted), 10000);
      expect((restarted!['bookmarks'] as List).single['id'], 'mark');
      expect((await phone.store.read('bob'))!['bookmarks'], hasLength(40));
    });

    test('that leaves no room to write the records held in memory into the new file keeps them until there is room', () async {
      final directory = await Directory.systemTemp.createTemp(
        'bookfin-pages-full-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}/records.sqlite';
      final disk = _FillingDisk();
      final writer = await RecordDatabase.open(
        factory: databaseFactoryFfi,
        path: path,
      );
      final first = LocalResumeStore(openDatabase: () async => writer);
      await first.save(
        'alice',
        ListeningChanges(
          _settings,
          bookmarks: {'mark': _bookmark('mark', 15000)},
        ),
      );
      await fillHistory(first, 'alice');
      await first.save('bob', _place(5000));
      await writer.close();
      var database = await RecordDatabase.open(factory: disk, path: path);
      addTearDown(() => database.close());
      final store = LocalResumeStore(openDatabase: () async => database);
      await store.read('alice');
      await store.read('bob');
      // The store's connection drops the pages that it read, so that the
      // next save reads the damaged pages from the file.
      final shared = await databaseFactoryFfi.openDatabase(path);
      await shared.execute('PRAGMA cache_size = 0');
      await shared.execute('PRAGMA shrink_memory');
      await damageTail(path, pages: 4);

      await expectLater(
        store.save('alice', _place(20000)),
        // SQLite rolls back a transaction that fills the disk itself, so
        // sqflite reports the ROLLBACK that follows.
        throwsA(isA<DatabaseException>()),
      );
      expect(database.keptFile, isNotNull);
      expect(store.setAside('alice'), isTrue);
      await disk.free(path);
      await store.read('bob');

      await database.close();
      database = await RecordDatabase.open(
        factory: databaseFactoryFfi,
        path: path,
      );
      final restarted = LocalResumeStore(openDatabase: () async => database);
      final alice = await restarted.read('alice');
      expect(_savedPlace(alice), 20000);
      expect(
        (alice!['bookmarks'] as List).map((mark) => mark['id']),
        contains('mark'),
      );
      expect(_savedPlace(await restarted.read('bob')), 5000);
      await restarted.checkInvariants();
    });
  });

  group('a record row with a value of the wrong type', () {
    test(
      'is kept aside as it was, and the records that decode come back',
      () async {
        final phone = await _Phone.open('blob-kept');
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
          "UPDATE record_actions SET payload = x'00ff7b' WHERE rowid = (SELECT MAX(rowid) FROM record_actions)",
        );

        await phone.restart();
        final snapshot = await phone.store.read('alice');
        expect(phone.store.setAside('alice'), isTrue);
        expect(_savedPlace(snapshot), 10000);
        expect(snapshot!['bookmarks'], isEmpty);
        final kept = await sql.query('set_aside_record_actions');
        expect(
          kept.map((row) => row['payload']),
          contains(equals([0x00, 0xff, 0x7b])),
        );
        await phone.store.checkInvariants();
      },
    );

    test('keeps a place saved after it through a kill and a restart', () async {
      final phone = await _Phone.open('blob-then-place');
      await phone.store.save('alice', _place(10000));
      final sql = await _separateConnection(phone.path);
      addTearDown(sql.close);
      await sql.rawUpdate("UPDATE record_accounts SET metadata = x'00ff'");

      await phone.restart();
      await phone.store.read('alice');
      expect(phone.store.setAside('alice'), isTrue);
      await phone.store.save('alice', _place(20000));
      await phone.restart();
      expect(_savedPlace(await phone.store.read('alice')), 20000);
      await phone.store.checkInvariants();
    });
  });

  group('kept copies of damaged records', () {
    const columns = {
      'accounts': 'account, payload',
      'record_accounts': 'account, replica, cursor, metadata',
      'record_actions': 'account, identity, payload, pending',
      'record_versions': 'account, record, identities',
      'record_coverage': 'account, replica, sequence',
    };

    /// Copies every row of [account] into the tables that keep damaged
    /// rows, stamped with [keptAt], as an earlier version did with rows that
    /// it could not read. [move] also deletes the rows from the record
    /// tables, as that version did.
    Future<void> keepAside(
      Database sql,
      String account, {
      int keptAt = 1,
      bool move = true,
    }) async {
      for (final MapEntry(key: table, value: names) in columns.entries) {
        await sql.rawInsert(
          'INSERT INTO set_aside_$table SELECT ?, $names FROM $table WHERE account = ? ORDER BY rowid',
          [keptAt, account],
        );
        if (move) {
          await sql.delete(table, where: 'account = ?', whereArgs: [account]);
        }
      }
    }

    /// How many rows the tables that keep damaged rows hold.
    Future<int> keptRows(Database sql) async {
      var count = 0;
      for (final table in columns.keys) {
        count += (await sql.query('set_aside_$table')).length;
      }
      return count;
    }

    /// The identities of the listening bookmarks of [snapshot].
    Set<String> marks(Map<String, dynamic>? snapshot) => {
      for (final mark in (snapshot?['bookmarks'] as List? ?? []))
        (mark as Map)['id'] as String,
    };

    /// The change set that saves listening bookmarks [ids].
    ListeningChanges marked(List<String> ids) => ListeningChanges(
      _settings,
      bookmarks: {
        for (final (index, id) in ids.indexed)
          id: _bookmark(id, (index + 1) * 1000),
      },
    );

    /// A phone whose earlier version kept the bookmarks `one` and `two` of
    /// alice aside, and whose place was saved at 20000 after that.
    Future<(_Phone, Database)> phoneWithKeptMarks(String name) async {
      final phone = await _Phone.open(name);
      await phone.store.save('alice', marked(['one', 'two']));
      final sql = await _separateConnection(phone.path);
      addTearDown(sql.close);
      await keepAside(sql, 'alice');
      await phone.restart();
      await phone.store.save('alice', _place(20000));
      await phone.restart();
      return (phone, sql);
    }

    test('marks that an earlier version kept aside come back at the next launch beside the place saved since', () async {
      final (phone, _) = await phoneWithKeptMarks('kept-marks');

      await phone.store.recoverKept();
      final shown = await phone.store.read('alice');
      expect(_savedPlace(shown), 20000);
      expect(marks(shown), {'one', 'two'});
      expect(phone.store.keptNotifier.value, (recovered: 2, kept: true));
      await phone.store.checkInvariants();
      await phone.restart();
      expect(marks(await phone.store.read('alice')), {'one', 'two'});
    });

    test('a kept copy older than the saved records neither moves the place back nor brings back a deleted mark', () async {
      final phone = await _Phone.open('kept-older');
      await phone.store.save('alice', _place(10000));
      await phone.store.save('alice', marked(['one']));
      final sql = await _separateConnection(phone.path);
      addTearDown(sql.close);
      await keepAside(sql, 'alice', move: false);
      await phone.store.save('alice', _place(20000));
      await phone.store.save(
        'alice',
        ListeningChanges(_settings, bookmarks: {'one': null}),
      );
      await phone.restart();

      await phone.store.recoverKept();
      final shown = await phone.store.read('alice');
      expect(_savedPlace(shown), 20000);
      expect(marks(shown), isEmpty);
      expect(phone.store.keptNotifier.value, (recovered: 0, kept: true));
    });

    test('a kept place that this phone never saw stays beside the saved place as a choice', () async {
      final phone = await _Phone.open('kept-concurrent');
      await phone.store.save('alice', _place(10000));
      final sql = await _separateConnection(phone.path);
      addTearDown(sql.close);
      await keepAside(sql, 'alice');
      await phone.restart();
      await phone.store.save('alice', _place(20000));
      await phone.restart();

      await phone.store.recoverKept();
      final places = (await phone.store.conflicts('alice')).values
          .expand((versions) => versions)
          .map((action) => (action['value'] as Map)['milliseconds'])
          .toSet();
      expect(places, {10000, 20000});
    });

    test('a kill during the merge keeps the saved place and the kept copy, and the next launch merges again', () async {
      final (phone, sql) = await phoneWithKeptMarks('kept-kill');
      final kept = await keptRows(sql);
      await sql.execute(
        "CREATE TRIGGER cut AFTER INSERT ON record_actions BEGIN SELECT RAISE(ABORT, 'killed'); END",
      );

      await expectLater(phone.store.recoverKept(), throwsA(anything));
      await sql.execute('DROP TRIGGER cut');
      await phone.restart();
      final shown = await phone.store.read('alice');
      expect(_savedPlace(shown), 20000);
      expect(marks(shown), isEmpty);
      expect(await keptRows(sql), kept);

      await phone.store.recoverKept();
      expect(marks(await phone.store.read('alice')), {'one', 'two'});
    });

    test('records that came back add nothing at the next launch', () async {
      final (phone, sql) = await phoneWithKeptMarks('kept-twice');
      await phone.store.recoverKept();
      final actions = (await sql.query('record_actions')).length;

      await phone.restart();
      await phone.store.recoverKept();
      expect(phone.store.keptNotifier.value, (recovered: 0, kept: true));
      expect((await sql.query('record_actions')).length, actions);
    });

    test(
      'a kept record file that SQLite cannot read stays kept as it was',
      () async {
        final phone = await _Phone.open('kept-unreadable');
        await phone.store.save('alice', _place(20000));
        final damaged = List<int>.generate(8192, (index) => index * 7 % 251);
        final copy = File('${phone.path}.damaged-1');
        await copy.writeAsBytes(damaged);

        await phone.store.recoverKept();
        expect(copy.readAsBytesSync(), damaged);
        expect(phone.store.keptNotifier.value, (recovered: 0, kept: true));
        expect(_savedPlace(await phone.store.read('alice')), 20000);
      },
    );

    test('a kept record file gives back the records of the accounts that it can read', () async {
      final old = await _Phone.open('kept-file-old');
      await old.store.save('alice', marked(['one', 'two']));
      final source = await _separateConnection(old.path);
      await source.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
      await source.close();
      final phone = await _Phone.open('kept-file');
      await phone.store.save('alice', _place(20000));
      final copy = File('${phone.path}.damaged-1');
      await copy.writeAsBytes(await File(old.path).readAsBytes());
      final bytes = copy.readAsBytesSync();

      await phone.store.recoverKept();
      final shown = await phone.store.read('alice');
      expect(_savedPlace(shown), 20000);
      expect(marks(shown), {'one', 'two'});
      expect(copy.readAsBytesSync(), bytes);
    });

    test('a kept record file gives back records that were still in its write-ahead log', () async {
      final old = await _Phone.open('kept-wal-old');
      await old.store.save('alice', marked(['one', 'two']));
      final phone = await _Phone.open('kept-wal');
      await phone.store.save('alice', _place(20000));
      for (final suffix in ['', '-wal']) {
        await File('${phone.path}.damaged-1$suffix')
            .writeAsBytes(await File('${old.path}$suffix').readAsBytes());
      }

      await phone.store.recoverKept();
      expect(marks(await phone.store.read('alice')), {'one', 'two'});
    });

    test(
      'a record file kept aside when it opened counts as a kept copy at once',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'bookfin-kept-open-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final path = '${directory.path}/records.sqlite';
        await File(path).writeAsString('not a database ' * 512);
        final database = await RecordDatabase.open(
          factory: databaseFactoryFfi,
          path: path,
        );
        addTearDown(database.close);
        final store = LocalResumeStore(openDatabase: () async => database);

        await store.read('alice');
        expect(store.keptNotifier.value.kept, isTrue);
      },
    );

    test(
      'a kept preference value gives back its records without a database',
      () async {
        // An account key holds dots, as a server address does.
        final account = jsonEncode([
          'https://books.example',
          'server',
          'alice',
        ]);
        await LocalResumeStore().save(account, marked(['one', 'two']));
        final preferences = await SharedPreferences.getInstance();
        final text = preferences.getString('bookfin.playback.v1.$account')!;
        await preferences.remove('bookfin.playback.v1.$account');
        await preferences.setString(
          'bookfin.damaged-records.v1.$account.1',
          text,
        );
        final store = LocalResumeStore();
        await store.save(account, _place(20000));

        await store.recoverKept();
        final shown = await store.read(account);
        expect(_savedPlace(shown), 20000);
        expect(marks(shown), {'one', 'two'});
        expect(store.keptNotifier.value, (recovered: 2, kept: true));
      },
    );

    test(
      'damage found during this launch counts as a kept copy at once',
      () async {
        final phone = await _Phone.open('kept-now');
        await phone.store.save('alice', _place(10000));
        final sql = await _separateConnection(phone.path);
        addTearDown(sql.close);
        await sql.update('record_accounts', {'metadata': '{broken'});

        await phone.restart();
        await phone.store.read('alice');
        expect(phone.store.keptNotifier.value.kept, isTrue);
      },
    );

    test('the retry reads the kept copies in another isolate', () async {
      final (phone, _) = await phoneWithKeptMarks('kept-hop');
      var hops = 0;
      final store = LocalResumeStore(
        openDatabase: () async => phone.database,
        hop: <M, R>(FutureOr<R> Function(M) work, M input) {
          hops++;
          return compute(work, input);
        },
      );

      await store.recoverKept();
      expect(hops, greaterThan(0));
      expect(marks(await store.read('alice')), {'one', 'two'});
    });

    test(
      'Discard deletes every kept copy and keeps the records that came back',
      () async {
        final (phone, sql) = await phoneWithKeptMarks('kept-discard');
        final copy = File('${phone.path}.damaged-1');
        await copy.writeAsBytes(List<int>.filled(4096, 7));
        await File('${copy.path}-wal').writeAsBytes(List<int>.filled(64, 7));
        final preferences = await SharedPreferences.getInstance();
        await preferences.setString(
          'bookfin.damaged-records.v1.alice.1',
          '{broken',
        );
        await phone.store.recoverKept();

        await phone.store.discardKept();
        expect(await keptRows(sql), 0);
        expect(
          copy.parent.listSync().where(
            (file) => file.path.contains('.damaged-'),
          ),
          isEmpty,
        );
        expect(
          preferences.getKeys().where(
            (key) => key.startsWith('bookfin.damaged-records.'),
          ),
          isEmpty,
        );
        expect(phone.store.keptNotifier.value, (recovered: 2, kept: false));
        await phone.restart();
        final shown = await phone.store.read('alice');
        expect(_savedPlace(shown), 20000);
        expect(marks(shown), {'one', 'two'});
      },
    );

    test(
      'a mark that came back reaches another device at the next sync',
      () async {
        final server = await SyncFixture.open();
        addTearDown(server.close);
        final account = server.session.scope.key;
        final phone = await _Phone.open('kept-sync');
        await phone.store.save(account, marked(['one']));
        final sql = await _separateConnection(phone.path);
        addTearDown(sql.close);
        await keepAside(sql, account);
        await phone.restart();
        await phone.store.save(account, _place(20000));
        await phone.restart();

        await phone.store.recoverKept();
        await RecordTransport(phone.store)
            .synchronize(server.session, server.client);
        final tablet = await _Phone.open('kept-sync-tablet');
        await RecordTransport(tablet.store)
            .synchronize(server.session, server.client);
        final shown = await tablet.store.read(account);
        expect(_savedPlace(shown), 20000);
        expect(marks(shown), {'one'});
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
        RecordTransport(phone.store).synchronize(server.session, connection),
        throwsA(isA<SocketException>()),
      );
      await phone.restart();
      expect(_savedPlace(await phone.store.read(account)), 10000);

      connection.offline = false;
      await RecordTransport(phone.store)
          .synchronize(server.session, connection);
      await RecordTransport(tablet.store)
          .synchronize(server.session, connection);
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

      await RecordTransport(store).synchronize(server.session, server.client);
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
        await RecordTransport(phone.store)
            .synchronize(server.session, server.client);
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
        await RecordTransport(phone.store)
            .synchronize(server.session, server.client);
        expect(server.objects, hasLength(2));
        expect(await phone.store.conflicts(account), isEmpty);
        await RecordTransport(tablet.store)
            .synchronize(server.session, server.client);
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
        await RecordTransport(phone.store)
            .synchronize(server.session, connection);
        await RecordTransport(tablet.store)
            .synchronize(server.session, connection);

        await phone.store.save(account, _place(20000));
        await tablet.store.save(account, _place(30000));
        for (final device in [phone, tablet, phone]) {
          await RecordTransport(device.store)
              .synchronize(server.session, connection);
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
