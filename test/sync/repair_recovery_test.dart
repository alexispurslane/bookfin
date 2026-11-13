import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bookfin/playback/database.dart';
import 'package:bookfin/playback/store.dart';
import 'package:bookfin/sync/journal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'unreadable_discovery_test.dart' show bookmark;

/// Corrupts real SQLite pages after repair commits but before its count read.
/// The other operations use the real factory and real transactions unchanged.
class _DamageFiles implements DatabaseFactory {
  bool armed = false;
  bool damaged = false;

  @override
  Future<Database> openDatabase(
    String path, {
    OpenDatabaseOptions? options,
  }) async => _DamageDatabase(
    await databaseFactoryFfi.openDatabase(path, options: options),
    this,
  );
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

class _DamageDatabase extends Fake implements Database {
  _DamageDatabase(this.database, this.files);
  @override
  final Database database;
  final _DamageFiles files;

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async {
    if (files.armed &&
        sql ==
            'SELECT COUNT(*) AS count FROM record_objects WHERE account = ?') {
      files.armed = false;
      await database.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
      await database.execute('PRAGMA cache_size = 0');
      await database.execute('PRAGMA shrink_memory');
      final roots = await database.rawQuery(
        "SELECT rootpage FROM sqlite_master WHERE tbl_name = 'record_objects'",
      );
      final file = File(database.path);
      final bytes = await file.readAsBytes();
      for (final row in roots) {
        final root = row['rootpage'] as int;
        bytes.fillRange((root - 1) * 4096, root * 4096, 0xff);
      }
      await file.writeAsBytes(bytes, flush: true);
      files.damaged = true;
    }
    return database.rawQuery(sql, arguments);
  }

  @override
  Future<T> transaction<T>(
    Future<T> Function(Transaction) action, {
    bool? exclusive,
  }) => database.transaction(action, exclusive: exclusive);
  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) =>
      database.execute(sql, arguments);
  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) => database.query(
    table,
    distinct: distinct,
    columns: columns,
    where: where,
    whereArgs: whereArgs,
    groupBy: groupBy,
    having: having,
    orderBy: orderBy,
    limit: limit,
    offset: offset,
  );
  @override
  Future<void> close() => database.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test('damage after a repair commits keeps the newly received unreadable original', () async {
    SharedPreferences.setMockInitialValues({});
    final root = await Directory.systemTemp.createTemp(
      'bookfin-repair-recovery-',
    );
    addTearDown(() => root.delete(recursive: true));
    final files = _DamageFiles();
    final path = '${root.path}/records.sqlite';
    var database = await RecordDatabase.open(factory: files, path: path);
    addTearDown(() => database.close());
    var store = LocalResumeStore(openDatabase: () async => database);
    final journal = RecordJournal('alice', 'remote')
      ..change(jsonEncode(['audio', 'bookmarks', 'kept']), bookmark('kept'));
    final action = journal.uploads.single;
    await store.receivePage('alice', [
      {
        ...action,
        'value': {...bookmark('kept'), 'title': 'damaged'},
      },
    ], 1);
    final original = {
      'Id': 'action.bad.1',
      'Sequence': 2,
      'Payload': ' exact { unreadable original',
      'Deleted': false,
    };
    files.armed = true;
    await store.receiveObjects('alice', [
      {
        'Id': RecordJournal.identity(action),
        'Sequence': 1,
        'Payload': jsonEncode(action),
        'Deleted': false,
      },
      original,
    ], 2);
    expect(files.damaged, isTrue);
    expect(database.keptFile, isNotNull);
    expect(await store.unreadableCount('alice'), 1);
    expect(await store.discoveryCursor('alice'), 2);
    expect((await store.read('alice'))!['bookmarks'], [bookmark('kept')]);
    await database.close();
    database = await RecordDatabase.open(
      factory: databaseFactoryFfi,
      path: path,
    );
    store = LocalResumeStore(openDatabase: () async => database);
    expect(await store.unreadableCount('alice'), 1);
    expect(await store.discoveryCursor('alice'), 2);
    expect(
      jsonDecode(
        (await database.retainedObjects('alice')).single['body'] as String,
      ),
      original,
    );
    await store.checkInvariants();
  });
}
