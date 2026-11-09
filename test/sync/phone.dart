import 'dart:io';

import 'package:bookfin/catalog/jellyfin.dart';
import 'package:bookfin/playback/database.dart';
import 'package:bookfin/playback/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fixture.dart';

/// A phone: one SQLite record file and the store that a fresh app start
/// would build over it.
class Phone {
  Phone._(this.path, this.database);
  final String path;
  RecordDatabase database;
  late LocalResumeStore store = LocalResumeStore(
    openDatabase: () async => database,
  );

  static Future<Phone> open(String name) async {
    final directory = await Directory.systemTemp.createTemp('bookfin-$name-');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/records.sqlite';
    final phone = Phone._(
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
    store = LocalResumeStore(openDatabase: () async => database);
  }

  /// A second SQLite connection to the record file, as another process
  /// would hold. sqflite shares one connection per path by default.
  Future<Database> separateConnection() async {
    final sql = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    addTearDown(sql.close);
    return sql;
  }

  /// Makes the next write into the table [table] fail after it changed
  /// rows, as a process killed in the middle of a write stops, runs
  /// [write], and lets later writes succeed again. With [when], an SQL
  /// condition on the new row `NEW`, only the insert of such a row fails.
  Future<void> killDuring(
    String table,
    Future<void> Function() write, {
    String? when,
  }) async {
    final sql = await separateConnection();
    await sql.execute(
      "CREATE TRIGGER cut AFTER INSERT ON $table ${when == null ? '' : 'WHEN $when'} BEGIN SELECT RAISE(ABORT, 'killed'); END",
    );
    try {
      await expectLater(write(), throwsA(anything));
    } finally {
      await sql.execute('DROP TRIGGER cut');
    }
  }

  /// The addresses of the records that the record file holds a current
  /// version of for [account].
  Future<Iterable<String>> savedRecords(String account) async =>
      ((await database.load(account))!['current'] as Map).keys.cast<String>();
}

/// A Jellyfin client whose personal-record uploads fail while [offline].
class Connection extends JellyfinClient {
  Connection(SyncFixture fixture)
    : super(fixture.client.server, deviceId: 'connection');
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
