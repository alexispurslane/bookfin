import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../sync/journal.dart';

/// One account's durable rows as SQLite returns them, before any decoding.
///
/// [identities], [payloads] are the retained actions in the order of their
/// rows, and [pending] names the actions that wait for upload. [versions]
/// holds the JSON list of current action identities of each record, and
/// [coverage] the highest applied sequence of each installation.
typedef AccountRows = ({
  String metadata,
  String replica,
  int cursor,
  List<String> identities,
  List<String> payloads,
  List<String> pending,
  Map<String, String> versions,
  Map<String, int> coverage,
});

/// The rows that one commit writes, as [RecordDatabase.encodeCommit] makes
/// them.
typedef RecordCommit = ({
  String account,
  bool initialize,
  Map<String, Object?> values,
  List<Map<String, Object?>> actions,
  List<String> acknowledged,
  List<Map<String, Object?>> versions,
  List<Map<String, Object?>> coverage,
});

/// The columns of each table that holds rows of an account, in the format
/// before the journal (`accounts`) and in the journal format. Each table has
/// a table of the same columns, after a `kept_at` column, that keeps the
/// damaged rows of an account: `set_aside_` and the table's name.
const _accountTables = {
  'accounts': ['account', 'payload'],
  'record_accounts': ['account', 'replica', 'cursor', 'metadata'],
  'record_actions': ['account', 'identity', 'payload', 'pending'],
  'record_versions': ['account', 'record', 'identities'],
  'record_coverage': ['account', 'replica', 'sequence'],
};

class RecordDatabase {
  RecordDatabase._(this._database, {this.keptFile});
  final Database _database;

  /// The name of the copy of a record file that could not be opened, or
  /// null when the file opened. [open] copied the damaged file and its
  /// write-ahead log to this name and its `-wal` name, then started a new
  /// file.
  final String? keptFile;

  /// Opens the record file at [path], or the default file.
  ///
  /// When SQLite reports the file as damaged (not a database, or corrupt),
  /// this copies the file aside as [keptFile] says, deletes the damaged
  /// original only after the copy is complete, and opens a new empty file.
  /// Other failures, such as a full disk, throw and change nothing.
  static Future<RecordDatabase> open({
    DatabaseFactory? factory,
    String? path,
  }) async {
    final files = factory ?? databaseFactory;
    final name = path ?? 'bookfin-personal-records-v1.sqlite';
    try {
      return RecordDatabase._(await _openFile(files, name));
    } on DatabaseException catch (error) {
      // SQLITE_CORRUPT and SQLITE_NOTADB. Android reports extended codes.
      if (!const {11, 26}.contains((error.getResultCode() ?? 0) & 0xff)) {
        rethrow;
      }
    }
    final kept =
        '$name.damaged-${DateTime.now().toUtc().millisecondsSinceEpoch}';
    for (final suffix in ['', '-wal']) {
      if (await files.databaseExists('$name$suffix')) {
        await files.writeDatabaseBytes(
          '$kept$suffix',
          await files.readDatabaseBytes('$name$suffix'),
        );
      }
    }
    await files.deleteDatabase(name);
    return RecordDatabase._(await _openFile(files, name), keptFile: kept);
  }

  static Future<Database> _openFile(DatabaseFactory files, String name) =>
      files.openDatabase(
        name,
        options: OpenDatabaseOptions(
          version: 3,
          onConfigure: (database) async {
            await database.rawQuery('PRAGMA journal_mode=WAL');
            await database.execute('PRAGMA synchronous=FULL');
          },
          onCreate: (database, _) async {
            await database.execute(
              'CREATE TABLE accounts (account TEXT PRIMARY KEY NOT NULL, payload TEXT NOT NULL)',
            );
            await _createRows(database);
            await _createSetAside(database);
          },
          onUpgrade: (database, previous, _) async {
            if (previous < 2) await _createRows(database);
            await _createSetAside(database);
          },
        ),
      );

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

  /// Creates the tables that keep damaged rows. Their columns have no type
  /// and no constraint, so a copy keeps each value exactly as it was.
  static Future<void> _createSetAside(DatabaseExecutor database) async {
    for (final MapEntry(key: table, value: columns) in _accountTables.entries) {
      await database.execute(
        'CREATE TABLE set_aside_$table (kept_at, ${columns.join(', ')})',
      );
    }
  }

  /// The durable rows of [account] as text, or null when it has none.
  ///
  /// Nothing is decoded, so a read can send the rows to another isolate as
  /// strings and decode them there with [decode].
  Future<AccountRows?> rows(String account) => _database.transaction((
    transaction,
  ) async {
    final accounts = await transaction.query(
      'record_accounts',
      where: 'account = ?',
      whereArgs: [account],
    );
    if (accounts.isEmpty) return null;
    final row = accounts.single;
    final actions = await transaction.query(
      'record_actions',
      where: 'account = ?',
      whereArgs: [account],
      orderBy: 'rowid',
    );
    final versions = await transaction.query(
      'record_versions',
      where: 'account = ?',
      whereArgs: [account],
    );
    final coverage = await transaction.query(
      'record_coverage',
      where: 'account = ?',
      whereArgs: [account],
    );
    // NOTE: Engine rule 1. These loops only copy column values out of
    // the rows, about 50 ns each, so that the hop sends strings instead
    // of row maps. The JSON in them is decoded in the hop.
    return (
      metadata: row['metadata'] as String,
      replica: row['replica'] as String,
      cursor: row['cursor'] as int,
      identities: [for (final action in actions) action['identity'] as String],
      payloads: [for (final action in actions) action['payload'] as String],
      pending: [
        for (final action in actions)
          if (action['pending'] == 1) action['identity'] as String,
      ],
      versions: {
        for (final version in versions)
          version['record'] as String: version['identities'] as String,
      },
      coverage: {
        for (final entry in coverage)
          entry['replica'] as String: entry['sequence'] as int,
      },
    );
  });

  /// The account that [rows] hold: the settings under `snapshot`, the
  /// journal under `sync`, and the current versions and causal coverage
  /// that the rows recorded, under `current` and `coverage`.
  ///
  /// Throws a [FormatException] when a row cannot be decoded or does not
  /// name the action that it holds.
  static Map<String, dynamic> decode(AccountRows rows) {
    final metadata = jsonDecode(rows.metadata);
    if (metadata is! Map<String, dynamic> ||
        (metadata['reading'] != null &&
            metadata['reading'] is! Map<String, dynamic>)) {
      throw const FormatException(
        'Personal-record metadata must be an object.',
      );
    }
    final decodedActions = <Map<String, dynamic>>[];
    for (var index = 0; index < rows.payloads.length; index++) {
      final decoded = jsonDecode(rows.payloads[index]);
      if (decoded is! Map<String, dynamic> ||
          rows.identities[index] != RecordJournal.identity(decoded)) {
        throw const FormatException(
          'Stored action identity does not match its payload.',
        );
      }
      decodedActions.add(decoded);
    }
    final current = <String, List<String>>{};
    for (final MapEntry(key: record, value: text) in rows.versions.entries) {
      final identities = jsonDecode(text);
      if (identities is! List ||
          identities.any((identity) => identity is! String)) {
        throw const FormatException(
          'Current versions must name retained actions.',
        );
      }
      current[record] = identities.cast<String>()..sort();
    }
    return {
      'snapshot': metadata,
      'sync': {
        'version': 1,
        'replica': rows.replica,
        'cursor': rows.cursor,
        'actions': decodedActions,
        'pending': List.of(rows.pending),
      },
      'current': current,
      'coverage': Map.of(rows.coverage),
    };
  }

  /// The decoded account of [account], as [decode] returns it, or null
  /// when it has none. It decodes on the calling isolate, so only an
  /// on-demand invariant check calls it.
  Future<Map<String, dynamic>?> load(String account) async {
    final saved = await rows(account);
    return saved == null ? null : decode(saved);
  }

  /// The rows that saving [metadata] and the unsaved changes of [journal]
  /// writes, as text. [initialize] writes a new account and removes its
  /// row in the format before the journal.
  ///
  /// It touches no database, so a hop can encode a large first commit.
  static RecordCommit encodeCommit(
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
    return (
      account: account,
      initialize: initialize,
      values: {
        'account': account,
        'replica': journal.replica,
        'cursor': journal.cursor,
        'metadata': jsonEncode(metadata),
      },
      actions: [
        for (final entry in journal.additions.entries)
          {
            'account': account,
            'identity': entry.key,
            'payload': jsonEncode(entry.value),
            'pending': journal.pending.contains(entry.key) ? 1 : 0,
          },
      ],
      acknowledged: List.of(journal.acknowledged),
      versions: [
        for (final record in journal.changedRecords)
          {
            'account': account,
            'record': record,
            'identities': jsonEncode(journal.versions(record)),
          },
      ],
      coverage: [
        for (final entry in journal.changedCoverage.entries)
          {'account': account, 'replica': entry.key, 'sequence': entry.value},
      ],
    );
  }

  /// Writes [commit] in one transaction.
  Future<void> writeCommit(RecordCommit commit) =>
      _database.transaction((transaction) => _write(transaction, commit));

  /// Moves every row of the account of [commit] into the tables that keep
  /// damaged rows, stamped with [keptAt] in milliseconds since the epoch,
  /// and writes [commit] as the account's first commit, in one
  /// transaction. So a failure or a kill leaves the damaged rows where they
  /// were, or the new account with the damaged rows kept aside.
  Future<void> replaceDamaged(RecordCommit commit, {required int keptAt}) {
    if (!commit.initialize) {
      throw ArgumentError('A damaged account is replaced by a first commit.');
    }
    return _database.transaction((transaction) async {
      for (final MapEntry(key: table, value: columns)
          in _accountTables.entries) {
        await transaction.rawInsert(
          'INSERT INTO set_aside_$table SELECT ?, ${columns.join(', ')} FROM $table WHERE account = ? ORDER BY rowid',
          [keptAt, commit.account],
        );
        await transaction.delete(
          table,
          where: 'account = ?',
          whereArgs: [commit.account],
        );
      }
      await _write(transaction, commit);
    });
  }

  static Future<void> _write(
    Transaction transaction,
    RecordCommit commit,
  ) async {
    final account = commit.account;
    if (commit.initialize) {
      await transaction.insert('record_accounts', commit.values);
    } else {
      final updated = await transaction.update(
        'record_accounts',
        commit.values,
        where: 'account = ?',
        whereArgs: [account],
      );
      if (updated != 1) {
        throw StateError('The retained account must exist before updating it.');
      }
    }
    final batch = transaction.batch();
    for (final action in commit.actions) {
      batch.insert('record_actions', action);
    }
    for (final identity in commit.acknowledged) {
      batch.update(
        'record_actions',
        {'pending': 0},
        where: 'account = ? AND identity = ?',
        whereArgs: [account, identity],
      );
    }
    for (final version in commit.versions) {
      batch.insert(
        'record_versions',
        version,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    for (final coverage in commit.coverage) {
      batch.insert(
        'record_coverage',
        coverage,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
    if (commit.initialize) {
      await transaction.delete(
        'accounts',
        where: 'account = ?',
        whereArgs: [account],
      );
    }
  }

  /// Saves [metadata] and the unsaved changes of [journal] in one
  /// transaction. One save changes a few records, so it encodes on the
  /// calling isolate.
  Future<void> commit(
    String account,
    Map<String, dynamic> metadata,
    RecordJournal journal, {
    bool initialize = false,
  }) => writeCommit(
    encodeCommit(account, metadata, journal, initialize: initialize),
  );

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
