import 'dart:isolate';

import 'package:sqflite/sqflite.dart';

// The record file code of Bookfin itself, through a link to its lib
// directory, so that this measures the read that the app does.
import 'bookfin/playback/database.dart';
import 'main.dart' show account, payload, replica, stalled;

/// Measures the reads of an account of [size] actions in a record file that
/// Bookfin's own RecordDatabase writes, in WAL mode, and checks what a read
/// in a worker isolate sees. Hands [report] one line for each run or check.
Future<void> measureRestore(int size, void Function(String line) report) async {
  final path = 'bench-restore-$size.sqlite';
  await deleteDatabase(path);
  final database = await RecordDatabase.open(path: path);
  await database.writeCommit(commit(1, size, initialize: true));
  final reader = database.reader;
  // Warm up both connections and the page cache once.
  await database.rows(account);
  await Isolate.run(() => reader.rows(account));
  for (var run = 0; run < 3; run++) {
    final main = await stalled(() => database.rows(account));
    report(
      'size=$size way=recordMain run=$run ms=${main.ms} stallMs=${main.stallMs}',
    );
    final worker = await stalled(() async {
      await database.actionCount(account);
      return Isolate.run(() => reader.rows(account));
    });
    report(
      'size=$size way=recordWorker run=$run ms=${worker.ms} stallMs=${worker.stallMs}',
    );
  }

  // A commit of the UI isolate's connection, still in the write-ahead log,
  // is in the worker's read.
  await database.writeCommit(commit(size + 1, size + 1));
  final seen = await Isolate.run(() => reader.rows(account));
  report(
    'check walVisible=${seen.rows!.payloads.length == size + 1} damaged=${seen.damaged}',
  );

  // A commit of the UI isolate's connection during a worker read waits for
  // nothing and is lost by nothing.
  final during = Isolate.run(() => reader.rows(account));
  final clock = Stopwatch()..start();
  await database.writeCommit(commit(size + 2, size + 2));
  final writeMs = clock.elapsedMilliseconds;
  final read = await during;
  final after = await Isolate.run(() => reader.rows(account));
  final count = read.rows!.payloads.length;
  report(
    'check concurrentWriteMs=$writeMs readCount=$count '
    'readIsOneSnapshot=${count == size + 1 || count == size + 2} '
    'afterCount=${after.rows!.payloads.length} expected=${size + 2}',
  );
  await database.close();
  await deleteDatabase(path);
}

/// The commit of the actions [first] to [last] of the measured account, in
/// the shape that RecordDatabase.encodeCommit makes.
RecordCommit commit(int first, int last, {bool initialize = false}) => (
  account: account,
  initialize: initialize,
  values: {
    'account': account,
    'replica': replica,
    'cursor': last,
    'metadata': '{"version":3,"speed":1.0,"reading":{"version":1}}',
  },
  actions: [
    for (var sequence = first; sequence <= last; sequence++)
      {
        'account': account,
        'identity': 'action.$replica.$sequence',
        'payload': payload(sequence),
        'pending': 0,
      },
  ],
  acknowledged: const [],
  versions: [
    {
      'account': account,
      'record': 'edition-${last % 40}',
      'identities': '["action.$replica.$last"]',
    },
  ],
  coverage: [
    {'account': account, 'replica': replica, 'sequence': last},
  ],
);
