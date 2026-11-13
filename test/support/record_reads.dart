import 'dart:isolate';
import 'dart:typed_data';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

typedef RecordQuery = ({
  String sql,
  List<Object?> arguments,
  List<Map<String, Object?>> rows,
});

/// Observes actual SQLite replies, including those delivered in workers.
class ObservedFiles implements DatabaseFactory {
  ObservedFiles(this.files, this.replies);
  final DatabaseFactory files;
  final SendPort replies;
  @override
  Future<Database> openDatabase(
    String path, {
    OpenDatabaseOptions? options,
  }) async {
    final database = await files.openDatabase(path, options: options);
    return ObservedDatabase(database, replies);
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

class ObservedDatabase implements Database {
  ObservedDatabase(this.database, this.replies);
  @override
  final Database database;
  final SendPort replies;
  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async {
    final rows = await database.rawQuery(sql, arguments);
    replies.send(<RecordQuery>[
      (sql: sql, arguments: arguments ?? const [], rows: rows),
    ]);
    return rows;
  }

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) =>
      database.execute(sql, arguments);
  @override
  Future<void> close() async {
    await database.close();
    replies.send(<RecordQuery>[]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
