import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

import 'restore.dart';

/// The number of actions of each measured account. One second of
/// listening adds about one action, so 21600 actions are six hours.
const sizes = [3600, 21600, 43200];
const account = '["http://jellyfin.local","server","alice"]';

/// Measures each way of reading the rows of an account of each size, and
/// hands [report] one line for each run.
Future<void> measure(void Function(String line) report) async {
  final token = RootIsolateToken.instance!;
  for (final size in sizes) {
    final path = 'bench-$size.sqlite';
    await deleteDatabase(path);
    final database = await openDatabase(path, version: 1, onCreate: create);
    await fill(database, size);
    final bytes = await payloadBytes(database);
    // Warm up the connection and the page cache once.
    await rows(database);
    for (var run = 0; run < 3; run++) {
      final main = await stalled(() => rows(database));
      report(
        'size=$size bytes=$bytes way=main run=$run ms=${main.ms} stallMs=${main.stallMs}',
      );
      final codec = await stalled(() async => decodeOnly(size, bytes));
      report(
        'size=$size bytes=$bytes way=codec run=$run ms=${codec.ms} stallMs=${codec.stallMs}',
      );
      final worker = await stalled(
        () => Isolate.run(() => workerRows(token, path)),
      );
      report(
        'size=$size bytes=$bytes way=worker run=$run ms=${worker.ms} stallMs=${worker.stallMs}',
      );
      final own = await stalled(
        () => Isolate.run(() => workerOwnRows(token, path)),
      );
      report(
        'size=$size bytes=$bytes way=workerOwn run=$run ms=${own.ms} stallMs=${own.stallMs}',
      );
    }
    await database.close();
    await deleteDatabase(path);
    await measureRestore(size, report);
  }
  report('done');
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Results())),
    ),
  );
}

class Results extends StatefulWidget {
  const Results({super.key});
  @override
  State<Results> createState() => _ResultsState();
}

class _ResultsState extends State<Results> {
  final lines = <String>['Measuring…'];
  @override
  void initState() {
    super.initState();
    unawaited(_measure());
  }

  void _report(String line) {
    // ignore: avoid_print
    print('BENCH $line');
    setState(() => lines.add(line));
  }

  Future<void> _measure() => measure(_report);

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [for (final line in lines) Text(line)],
  );
}

/// Runs [work] and measures its wall time, and the longest gap between two
/// runs of a 1 ms timer on this isolate meanwhile, both in milliseconds.
Future<({int ms, int stallMs})> stalled(Future<Object?> Function() work) async {
  final clock = Stopwatch()..start();
  var last = 0;
  var longest = 0;
  final beat = Timer.periodic(const Duration(milliseconds: 1), (_) {
    final now = clock.elapsedMicroseconds;
    if (now - last > longest) longest = now - last;
    last = now;
  });
  await work();
  final total = clock.elapsedMicroseconds;
  beat.cancel();
  if (total - last > longest) longest = total - last;
  return (ms: total ~/ 1000, stallMs: longest ~/ 1000);
}

Future<void> create(Database database, int _) async {
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

const replica = '0f1e2d3c4b5a69788796a5b4c3d2e1f00f1e2d3c';

/// One resume action of [sequence] in the shape that RecordJournal saves.
String payload(int sequence) {
  final edition = 'edition-${sequence % 40}';
  final sources = jsonEncode([
    ['source-a', 'revision-1'],
  ]);
  return jsonEncode({
    'version': 1,
    'account': account,
    'replica': replica,
    'sequence': sequence,
    'context': {replica: sequence - 1},
    'record': jsonEncode([
      'audio',
      'resumes',
      jsonEncode([edition, jsonDecode(sources)]),
    ]),
    'value': {
      'source': 'source-a',
      'revision': 'revision-1',
      'sources': sources,
      'milliseconds': sequence * 1000,
      'pendingOffline': false,
      'edition': edition,
    },
    'preserve': [],
  });
}

Future<void> fill(Database database, int size) async {
  await database.insert('record_accounts', {
    'account': account,
    'replica': replica,
    'cursor': size,
    'metadata': '{"version":3,"speed":1.0,"reading":{"version":1}}',
  });
  for (var start = 1; start <= size; start += 2000) {
    final batch = database.batch();
    for (
      var sequence = start;
      sequence < start + 2000 && sequence <= size;
      sequence++
    ) {
      batch.insert('record_actions', {
        'account': account,
        'identity': 'action.$replica.$sequence',
        'payload': payload(sequence),
        'pending': sequence > size - 20 ? 1 : 0,
      });
    }
    await batch.commit(noResult: true);
  }
  for (var edition = 0; edition < 40; edition++) {
    await database.insert('record_versions', {
      'account': account,
      'record': 'edition-$edition',
      'identities': '["action.$replica.${size - edition}"]',
    });
  }
  await database.insert('record_coverage', {
    'account': account,
    'replica': replica,
    'sequence': size,
  });
}

Future<int> payloadBytes(Database database) async =>
    (await database.rawQuery(
          'SELECT SUM(LENGTH(payload)) AS bytes FROM record_actions',
        )).single['bytes']
        as int;

/// The read of RecordDatabase.rows: four queries in one transaction, and
/// the copy of the column values into lists of strings.
Future<int> rows(Database database, {bool transaction = true}) async {
  Future<int> read(DatabaseExecutor executor) async {
    final accounts = await executor.query(
      'record_accounts',
      where: 'account = ?',
      whereArgs: [account],
    );
    final actions = await executor.query(
      'record_actions',
      where: 'account = ?',
      whereArgs: [account],
      orderBy: 'rowid',
    );
    final versions = await executor.query(
      'record_versions',
      where: 'account = ?',
      whereArgs: [account],
    );
    final coverage = await executor.query(
      'record_coverage',
      where: 'account = ?',
      whereArgs: [account],
    );
    final payloads = [
      for (final action in actions) action['payload'] as String,
    ];
    final identities = [
      for (final action in actions) action['identity'] as String,
    ];
    return accounts.length +
        payloads.length +
        identities.length +
        versions.length +
        coverage.length;
  }

  return transaction ? database.transaction(read) : read(database);
}

/// Decodes, on this isolate, a reply of the shape that sqflite on Android
/// sends for the actions query: column names and one list of values per
/// row. The reply is encoded first, which is not measured.
Future<int> decodeOnly(int size, int bytes) async {
  const codec = StandardMethodCodec();
  final reply = codec.encodeSuccessEnvelope({
    'columns': ['account', 'identity', 'payload', 'pending'],
    'rows': [
      for (var sequence = 1; sequence <= size; sequence++)
        [account, 'action.$replica.$sequence', payload(sequence), 0],
    ],
  });
  final clock = Stopwatch()..start();
  final decoded = codec.decodeEnvelope(reply) as Map;
  final elapsed = clock.elapsedMicroseconds;
  // ignore: avoid_print
  print('BENCH decodeOnlyUs size=$size us=$elapsed');
  return (decoded['rows'] as List).length;
}

/// The read in a background isolate. It opens the file that the UI isolate
/// keeps open. With singleInstance, the Android plugin hands back the same
/// native connection, so this isolate must not close it.
Future<int> workerRows(RootIsolateToken token, String path) async {
  BackgroundIsolateBinaryMessenger.ensureInitialized(token);
  final database = await openDatabase(path, singleInstance: true);
  // NOTE: Not in a transaction. The connection is shared with the UI
  // isolate, whose transaction lock does not cover this isolate.
  return rows(database, transaction: false);
}

/// The read in a background isolate on a connection of its own. Without
/// singleInstance, the Android plugin opens a second connection to the file,
/// so this isolate reads in its own transaction and closes the connection.
Future<int> workerOwnRows(RootIsolateToken token, String path) async {
  BackgroundIsolateBinaryMessenger.ensureInitialized(token);
  final database = await openDatabase(
    path,
    singleInstance: false,
    readOnly: true,
  );
  try {
    return await rows(database);
  } finally {
    await database.close();
  }
}
