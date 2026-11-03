import 'package:sqflite/sqflite.dart';

class RecordDatabase {
  RecordDatabase._(this._database);
  final Database _database;

  static Future<RecordDatabase> open({
    DatabaseFactory? factory,
    String? path,
  }) async {
    final database = await (factory ?? databaseFactory).openDatabase(
      path ?? 'bookfin-personal-records-v1.sqlite',
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (database) async {
          await database.rawQuery('PRAGMA journal_mode=WAL');
          await database.execute('PRAGMA synchronous=FULL');
        },
        onCreate: (database, _) => database.execute(
          'CREATE TABLE accounts (account TEXT PRIMARY KEY NOT NULL, payload TEXT NOT NULL)',
        ),
      ),
    );
    return RecordDatabase._(database);
  }

  Future<String?> read(String account) async {
    final rows = await _database.query(
      'accounts',
      columns: ['payload'],
      where: 'account = ?',
      whereArgs: [account],
    );
    return rows.isEmpty ? null : rows.single['payload'] as String;
  }

  Future<void> write(String account, String payload) =>
      _database.transaction((transaction) async {
        await transaction.insert('accounts', {
          'account': account,
          'payload': payload,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      });

  Future<void> checkInvariants() async {
    final result = await _database.rawQuery('PRAGMA integrity_check');
    if (result.length != 1 || result.single.values.single != 'ok') {
      throw StateError(
        'The personal-record database failed its integrity check.',
      );
    }
  }

  Future<void> close() => _database.close();
}
