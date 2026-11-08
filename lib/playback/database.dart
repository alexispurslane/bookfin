import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

import '../sync/journal.dart';

/// One account's durable rows as SQLite returns them, before any decoding.
///
/// [identities], [payloads] are the retained actions in the order of their
/// rows, and [pending] names the actions that wait for upload. [versions]
/// holds the JSON list of current action identities of each record, and
/// [coverage] the highest applied sequence of each installation.
/// [malformed] says that a value had a type that its column does not hold,
/// such as a blob in a text column. Such a text reads as an empty string, and
/// such a number as -1, so that neither decodes.
typedef AccountRows = ({
  bool malformed,
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

/// Thrown by a read or a write of a [RecordDatabase] that found damaged
/// pages in the record file. The file was set aside, as [RecordDatabase.open]
/// does, and the database continues on a new empty file, so the caller must
/// write again what it holds in memory.
class RecordFileSetAside implements Exception {
  const RecordFileSetAside(this.keptFile);

  /// The name that the damaged file was copied to.
  final String keptFile;

  @override
  String toString() => 'The damaged record file was kept as $keptFile.';
}

/// Read access to the record file from another isolate. It is sendable to
/// another isolate, and holds no connection: each read opens a read-only
/// connection of its own in the isolate that reads, and closes it.
///
/// It never uses the connection of the isolate that writes. sqflite on
/// Android hands every isolate the same native connection for a path unless
/// a connection opens with `singleInstance: false`, and the Dart lock of a
/// transaction covers one isolate only.
///
/// Measured on emulator-5556 with this code (tool/research/record_rows_bench,
/// results-emulator-5556.txt), for six hours of listening (21,600 actions,
/// 10.5 MB): a read on the UI isolate's connection stalls the UI isolate
/// for 28 to 31 ms, because the platform channel decodes the reply there,
/// and a read here for 4 to 6 ms, which is the noise of the 1 ms timer.
/// For 43,200 actions, the stalls are 75 to 102 ms and 13 to 30 ms.
///
/// The Android plugin runs the work of all connections on one thread, so a
/// commit of another connection waits until a read here ends. The store
/// runs one operation at a time, so none of its commits waits for it.
final class RecordReader {
  const RecordReader._(this._name, this._files);
  final String _name;

  /// The SQLite binding in the isolate that calls it.
  final DatabaseFactory Function() _files;

  /// The durable rows of [account] as [RecordDatabase.rows] reads them, or
  /// null when it has none. [damaged] says that SQLite reported damaged
  /// pages, which the owner of the file sets aside with
  /// [RecordDatabase.setAsideDamaged].
  ///
  /// One statement reads them, so they come from one snapshot of the file:
  /// a commit of another connection is in all of them or in none. A
  /// read-only connection writes nothing and takes no write lock, so a
  /// commit of another connection during the read waits for nothing.
  Future<({AccountRows? rows, bool damaged})> rows(String account) async {
    try {
      final database = await _files().openDatabase(
        _name,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      try {
        return (
          rows: await RecordDatabase._readRows(database, account),
          damaged: false,
        );
      } finally {
        await database.close();
      }
    } on DatabaseException catch (error) {
      if (!RecordDatabase._damaged(error)) rethrow;
      return (rows: null, damaged: true);
    }
  }
}

class RecordDatabase {
  RecordDatabase._(
    this._files,
    this._name,
    this._database,
    this.reader, {
    this.keptFile,
  });
  final DatabaseFactory _files;
  final String _name;
  Database _database;

  /// Reads the record file from another isolate.
  final RecordReader reader;

  /// The name of the copy of a record file that SQLite reported as damaged,
  /// or null while the file is intact. [open], or a later read or write that
  /// found damaged pages, copied the damaged file and its write-ahead log to
  /// this name and its `-wal` name, then started a new file.
  String? keptFile;

  /// Opens the record file at [path], or the default file, with the
  /// SQLite binding [factory], or the platform's.
  ///
  /// When SQLite reports the file as damaged (not a database, or corrupt),
  /// this copies the file aside as [keptFile] says, deletes the damaged
  /// original only after the copy is complete, and opens a new empty file.
  /// Other failures, such as a full disk, throw and change nothing.
  ///
  /// [reader] reads with [factory] copied into the reading isolate, which
  /// the FFI binding of tests allows, or with the platform's binding, which
  /// reaches the plugin through the root isolate.
  static Future<RecordDatabase> open({
    DatabaseFactory? factory,
    String? path,
  }) async {
    final files = factory ?? databaseFactory;
    final name = path ?? 'bookfin-personal-records-v1.sqlite';
    final reader = RecordReader._(
      name,
      factory == null
          ? _platformFiles(RootIsolateToken.instance!)
          : _copied(factory),
    );
    try {
      return RecordDatabase._(
        files,
        name,
        await _openFile(files, name),
        reader,
      );
    } on DatabaseException catch (error) {
      if (!_damaged(error)) rethrow;
    }
    final kept = await _keepAside(files, name);
    return RecordDatabase._(
      files,
      name,
      await _openFile(files, name),
      reader,
      keptFile: kept,
    );
  }

  /// The platform's SQLite binding in a background isolate, which reaches
  /// the plugin through the root isolate of [token]. The function holds
  /// only [token], so it is sendable.
  static DatabaseFactory Function() _platformFiles(RootIsolateToken token) =>
      () {
        BackgroundIsolateBinaryMessenger.ensureInitialized(token);
        return databaseFactory;
      };

  /// [files] itself. The function holds only [files].
  static DatabaseFactory Function() _copied(DatabaseFactory files) =>
      () => files;

  /// Whether [error] says that the file is damaged: SQLITE_CORRUPT or
  /// SQLITE_NOTADB. Android reports extended codes.
  static bool _damaged(DatabaseException error) =>
      const {11, 26}.contains((error.getResultCode() ?? 0) & 0xff);

  /// Copies the closed file [name] and its write-ahead log aside, deletes
  /// the original only after the copy is complete, and returns the name of
  /// the copy.
  static Future<String> _keepAside(DatabaseFactory files, String name) async {
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
    return kept;
  }

  /// Runs [work] on the record file. When SQLite reports damaged pages, this
  /// closes the file, sets it aside as [open] does, opens a new empty file,
  /// and throws [RecordFileSetAside]. Other failures throw as they are.
  Future<T> _guarded<T>(Future<T> Function(Database database) work) async {
    try {
      return await work(_database);
    } on DatabaseException catch (error) {
      if (!_damaged(error)) rethrow;
    }
    return setAsideDamaged();
  }

  /// Closes the record file, sets it aside as [open] does, opens a new
  /// empty file, and throws [RecordFileSetAside]. A [reader] that found
  /// damaged pages hands them to this owner of the file.
  Future<Never> setAsideDamaged() async {
    await _database.close();
    final kept = keptFile = await _keepAside(_files, _name);
    _database = await _openFile(_files, _name);
    throw RecordFileSetAside(kept);
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
  /// strings and decode them there with [decode]. Throws
  /// [RecordFileSetAside] when the file has damaged pages. The rows of a
  /// large account cross the platform channel to this isolate, so such an
  /// account is read with [reader] instead.
  Future<AccountRows?> rows(String account) =>
      _guarded((database) => _readRows(database, account));

  /// How many actions [account] retains. It reads only the index of the
  /// actions. Throws [RecordFileSetAside] when the file has damaged pages.
  Future<int> actionCount(String account) => _guarded(
    (database) async =>
        (await database.rawQuery(
              'SELECT COUNT(*) AS count FROM record_actions WHERE account = ?',
              [account],
            )).single['count']
            as int,
  );

  /// The rows of [account] that [database] holds, read in one statement and
  /// so from one snapshot, or null when it has none. `kind` names the table
  /// of each row: 0 the account, 1 an action, in the order of its rows, 2 a
  /// record's current versions, and 3 the coverage of an installation.
  static Future<AccountRows?> _readRows(
    DatabaseExecutor database,
    String account,
  ) async {
    final rows = await database.rawQuery(
      'SELECT 0 AS kind, NULL AS position, replica AS name, cursor AS number, metadata AS content FROM record_accounts WHERE account = ? '
      'UNION ALL SELECT 1, rowid, identity, pending, payload FROM record_actions WHERE account = ? '
      'UNION ALL SELECT 2, NULL, record, NULL, identities FROM record_versions WHERE account = ? '
      'UNION ALL SELECT 3, NULL, replica, sequence, NULL FROM record_coverage WHERE account = ? '
      'ORDER BY kind, position',
      [account, account, account, account],
    );
    if (rows.isEmpty || rows.first['kind'] != 0) return null;
    // A value of another type than its column holds reads as one that does
    // not decode, and marks the rows as malformed.
    var malformed = false;
    String text(Object? value) {
      if (value is String) return value;
      malformed = true;
      return '';
    }

    int number(Object? value) {
      if (value is int) return value;
      malformed = true;
      return -1;
    }

    // NOTE: Engine rule 1. This loop only copies column values out of the
    // rows, about 50 ns each, so that a hop sends strings instead of row
    // maps. The JSON in them is decoded in the hop. A large account runs it
    // in the hop that reads it.
    final head = rows.first;
    final identities = <String>[];
    final payloads = <String>[];
    final pending = <String>[];
    final versions = <String, String>{};
    final coverage = <String, int>{};
    for (final row in rows.skip(1)) {
      switch (row['kind']) {
        case 1:
          final identity = text(row['name']);
          identities.add(identity);
          payloads.add(text(row['content']));
          switch (row['number']) {
            case 1:
              pending.add(identity);
            case 0:
              break;
            default:
              malformed = true;
          }
        case 2:
          versions[text(row['name'])] = text(row['content']);
        case 3:
          coverage[text(row['name'])] = number(row['number']);
      }
    }
    return (
      metadata: text(head['content']),
      replica: text(head['name']),
      cursor: number(head['number']),
      identities: identities,
      payloads: payloads,
      pending: pending,
      versions: versions,
      coverage: coverage,
      malformed: malformed,
    );
  }

  /// The account that [rows] hold: the settings under `snapshot`, the
  /// journal under `sync`, and the current versions and causal coverage
  /// that the rows recorded, under `current` and `coverage`.
  ///
  /// Throws a [FormatException] when a row is malformed, cannot be decoded
  /// or does not name the action that it holds.
  static Map<String, dynamic> decode(AccountRows rows) {
    if (rows.malformed) {
      throw const FormatException(
        'A personal-record value has a type that its column does not hold.',
      );
    }
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

  /// Writes [commit] in one transaction. Throws [RecordFileSetAside] when
  /// the file has damaged pages.
  Future<void> writeCommit(RecordCommit commit) => _guarded(
    (database) =>
        database.transaction((transaction) => _write(transaction, commit)),
  );

  /// Writes each of [commits] in one transaction.
  Future<void> writeCommits(List<RecordCommit> commits) =>
      _database.transaction((transaction) async {
        for (final commit in commits) {
          await _write(transaction, commit);
        }
      });

  /// Moves every row of the account of [commit] into the tables that keep
  /// damaged rows, stamped with [keptAt] in milliseconds since the epoch,
  /// and writes [commit] as the account's first commit, in one
  /// transaction. So a failure or a kill leaves the damaged rows where they
  /// were, or the new account with the damaged rows kept aside. Throws
  /// [RecordFileSetAside] when the file has damaged pages.
  Future<void> replaceDamaged(RecordCommit commit, {required int keptAt}) {
    if (!commit.initialize) {
      throw ArgumentError('A damaged account is replaced by a first commit.');
    }
    return _guarded(
      (database) => database.transaction((transaction) async {
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
      }),
    );
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
