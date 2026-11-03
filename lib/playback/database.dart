import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../sync/journal.dart';

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
        version: 2,
        onConfigure: (database) async {
          await database.rawQuery('PRAGMA journal_mode=WAL');
          await database.execute('PRAGMA synchronous=FULL');
        },
        onCreate: (database, _) async {
          await database.execute(
            'CREATE TABLE accounts (account TEXT PRIMARY KEY NOT NULL, payload TEXT NOT NULL)',
          );
          await _createRows(database);
        },
        onUpgrade: (database, _, _) => _createRows(database),
      ),
    );
    return RecordDatabase._(database);
  }

  static Future<void> _createRows(DatabaseExecutor database) async {
    await database.execute(
      'CREATE TABLE record_accounts (account TEXT PRIMARY KEY NOT NULL, replica TEXT NOT NULL, cursor INTEGER NOT NULL, metadata TEXT NOT NULL)',
    );
    await database.execute(
      'CREATE TABLE record_actions (account TEXT NOT NULL, identity TEXT NOT NULL, payload TEXT NOT NULL, pending INTEGER NOT NULL CHECK(pending IN (0, 1)), PRIMARY KEY (account, identity))',
    );
    await database.execute(
      'CREATE TABLE record_versions (account TEXT NOT NULL, record TEXT NOT NULL, identities TEXT NOT NULL, PRIMARY KEY (account, record))',
    );
    await database.execute(
      'CREATE TABLE record_coverage (account TEXT NOT NULL, replica TEXT NOT NULL, sequence INTEGER NOT NULL, PRIMARY KEY (account, replica))',
    );
  }

  Future<Map<String, dynamic>?> load(String account) =>
      _database.transaction((transaction) async {
        final rows = await transaction.query(
          'record_accounts',
          where: 'account = ?',
          whereArgs: [account],
        );
        if (rows.isEmpty) return null;
        final row = rows.single;
        final metadata = jsonDecode(row['metadata'] as String);
        if (metadata is! Map<String, dynamic> ||
            (metadata['reading'] != null &&
                metadata['reading'] is! Map<String, dynamic>)) {
          throw const FormatException(
            'Personal-record metadata must be an object.',
          );
        }
        final actions = await transaction.query(
          'record_actions',
          where: 'account = ?',
          whereArgs: [account],
          orderBy: 'rowid',
        );
        final decodedActions = <Map<String, dynamic>>[];
        for (final action in actions) {
          final decoded = jsonDecode(action['payload'] as String);
          if (decoded is! Map<String, dynamic> ||
              action['identity'] != RecordJournal.identity(decoded)) {
            throw const FormatException(
              'Stored action identity does not match its payload.',
            );
          }
          decodedActions.add(decoded);
        }
        final current = <String, List<String>>{};
        for (final version in await transaction.query(
          'record_versions',
          where: 'account = ?',
          whereArgs: [account],
        )) {
          final identities = jsonDecode(version['identities'] as String);
          if (identities is! List ||
              identities.any((identity) => identity is! String)) {
            throw const FormatException(
              'Current versions must name retained actions.',
            );
          }
          current[version['record'] as String] = identities.cast<String>()
            ..sort();
        }
        return {
          'snapshot': metadata,
          'sync': {
            'version': 1,
            'replica': row['replica'],
            'cursor': row['cursor'],
            'actions': decodedActions,
            'pending': [
              for (final action in actions)
                if (action['pending'] == 1) action['identity'],
            ],
          },
          'current': current,
          'coverage': {
            for (final coverage in await transaction.query(
              'record_coverage',
              where: 'account = ?',
              whereArgs: [account],
            ))
              coverage['replica'] as String: coverage['sequence'],
          },
        };
      });

  Future<void> commit(
    String account,
    Map<String, dynamic> metadata,
    RecordJournal journal, {
    bool initialize = false,
  }) {
    if (journal.account != account || journal.cursor < 0) {
      throw ArgumentError(
        'Account ownership and a nonnegative discovery cursor are required.',
      );
    }
    return _database.transaction((transaction) async {
      final values = {
        'account': account,
        'replica': journal.replica,
        'cursor': journal.cursor,
        'metadata': jsonEncode(metadata),
      };
      if (initialize) {
        await transaction.insert('record_accounts', values);
      } else {
        final updated = await transaction.update(
          'record_accounts',
          values,
          where: 'account = ?',
          whereArgs: [account],
        );
        if (updated != 1) {
          throw StateError(
            'The retained account must exist before updating it.',
          );
        }
      }
      final batch = transaction.batch();
      for (final entry in journal.additions.entries) {
        batch.insert('record_actions', {
          'account': account,
          'identity': entry.key,
          'payload': jsonEncode(entry.value),
          'pending': journal.pending.contains(entry.key) ? 1 : 0,
        });
      }
      for (final identity in journal.acknowledged) {
        batch.update(
          'record_actions',
          {'pending': 0},
          where: 'account = ? AND identity = ?',
          whereArgs: [account, identity],
        );
      }
      for (final record in journal.changedRecords) {
        batch.insert('record_versions', {
          'account': account,
          'record': record,
          'identities': jsonEncode(journal.versions(record)),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final entry in journal.changedCoverage.entries) {
        batch.insert('record_coverage', {
          'account': account,
          'replica': entry.key,
          'sequence': entry.value,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
      if (initialize) {
        await transaction.delete(
          'accounts',
          where: 'account = ?',
          whereArgs: [account],
        );
      }
    });
  }

  Future<String?> read(String account) async {
    final normalized = await load(account);
    if (normalized != null) {
      return jsonEncode({
        ...normalized['snapshot'] as Map,
        'sync': normalized['sync'],
      });
    }
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
