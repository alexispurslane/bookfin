import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:bookfin/playback/database.dart';
import 'package:bookfin/playback/record_codec.dart';
import 'package:bookfin/playback/store.dart';
import 'package:bookfin/sync/journal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/record_reads.dart';
import 'journal_growth_measurement_test.dart' show seededState;

/// Recreates the exact v3 lookup-free schema over the original payload rows.
/// Only this disposable fixture uses DROP COLUMN (not the production migration).
Future<void> versionThree(String path) async {
  final sql = await databaseFactoryFfi.openDatabase(path);
  for (final row in await sql.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'index' AND name LIKE 'record_action_%'",
  )) {
    await sql.execute('DROP INDEX ${row['name']}');
  }
  for (final table in ['record_actions', 'set_aside_record_actions']) {
    for (final column in ['author', 'sequence', 'record']) {
      await sql.execute('ALTER TABLE $table DROP COLUMN $column');
    }
  }
  await sql.execute('DROP TABLE record_objects');
  await sql.execute('DROP TABLE set_aside_record_objects');
  await sql.execute('PRAGMA user_version = 3');
  await sql.close();
}

Future<int> replayInWorker(RecordReader reader) =>
    Isolate.run(() => fullReplay(reader));

Future<int> fullReplay(RecordReader reader) async {
  final rows = (await reader.rows('growth')).rows!;
  final decoded = RecordDatabase.decode(rows);
  final sync = decoded['sync'] as Map<String, dynamic>;
  final journal = RecordJournal(
    'growth',
    sync['replica'] as String,
    sync,
    validateRecordAction,
  );
  recordSnapshot(
    decoded['snapshot'] as Map<String, dynamic>,
    journal.values,
    reading: false,
  );
  recordSnapshot(
    decoded['snapshot'] as Map<String, dynamic>,
    journal.values,
    reading: true,
  );
  return (sync['actions'] as List).length;
}

Future<Map<String, dynamic>> queryWork(
  String path,
  List<RecordQuery> queries,
  Directory directory,
) async {
  final file = File('${directory.path}/queries.json');
  await file.writeAsString(
    jsonEncode([
      for (final query in queries)
        {'sql': query.sql, 'arguments': query.arguments},
    ]),
  );
  final result = await Process.run('python3', [
    '-c',
    r'''
import json, sqlite3, sys
connection = sqlite3.connect(sys.argv[1])
work = []
for query in json.load(open(sys.argv[2])):
    steps = [0]
    def progress():
        steps[0] += 1
        return 0
    plan = connection.execute('EXPLAIN QUERY PLAN ' + query['sql'], query['arguments']).fetchall()
    connection.set_progress_handler(progress, 1)
    rows = connection.execute(query['sql'], query['arguments']).fetchall()
    connection.set_progress_handler(None, 0)
    work.append({'sql': query['sql'], 'vmInstructions': steps[0], 'rows': len(rows), 'plan': plan})
print(json.dumps({'vmInstructions': sum(item['vmInstructions'] for item in work), 'queries': work}))
''',
    path,
    file.path,
  ]);
  expect(result.exitCode, 0, reason: '${result.stderr}');
  return jsonDecode(result.stdout as String) as Map<String, dynamic>;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  final output = Platform.environment['BOOKFIN_CURRENT_RESTORE_EVIDENCE'];
  test(
    'measure current restoration against complete retained replay on this host',
    () async {
      SharedPreferences.setMockInitialValues({});
      final results = <Map<String, dynamic>>[];
      for (final count in [60, 600, 3600, 21600, 216000]) {
        final directory = await Directory.systemTemp.createTemp(
          'bookfin-restore-measure-',
        );
        final path = '${directory.path}/records.sqlite';
        var database = await RecordDatabase.open(
          factory: databaseFactoryFfi,
          path: path,
        );
        try {
          await database.write(
            'growth',
            jsonEncode(seededState(count, allPending: false)),
          );
          await LocalResumeStore(openDatabase: () async => database)
              .read('growth');
          final originals = (await database.rows('growth'))!;
          await database.close();
          await versionThree(path);
          final upgrade = Stopwatch()..start();
          database = await RecordDatabase.open(
            factory: databaseFactoryFfi,
            path: path,
          );
          upgrade.stop();
          final restored = <double>[];
          final replayed = <double>[];
          List<RecordQuery> queries = [];
          for (var sample = 0; sample < 3; sample++) {
            await database.close();
            final port = ReceivePort();
            final read = Completer<List<RecordQuery>>();
            final captured = <RecordQuery>[];
            final subscription = port.listen((message) {
              final batch = (message as List).cast<RecordQuery>();
              captured.addAll(batch);
              if (batch.isEmpty && !read.isCompleted) {
                read.complete(captured.toList());
              }
            });
            database = await RecordDatabase.open(
              factory: ObservedFiles(databaseFactoryFfi, port.sendPort),
              path: path,
            );
            final store = LocalResumeStore(openDatabase: () async => database);
            final watch = Stopwatch()..start();
            final snapshot = (await store.read('growth'))!;
            await store.reading.read('growth');
            watch.stop();
            restored.add(watch.elapsedMicroseconds / 1000);
            expect((snapshot['history'] as List), hasLength(31));
            expect((snapshot['bookmarks'] as List), hasLength(7));
            queries = await read.future;
            await subscription.cancel();
            port.close();
            // Use an unobserved reader for the intentionally complete comparison.
            await database.close();
            database = await RecordDatabase.open(
              factory: databaseFactoryFfi,
              path: path,
            );
            final reader = database.reader;
            watch.reset();
            watch.start();
            expect(await replayInWorker(reader), count + 46);
            watch.stop();
            replayed.add(watch.elapsedMicroseconds / 1000);
          }
          final after = (await database.rows('growth'))!;
          expect(after.payloads, originals.payloads);
          expect(after.pending, originals.pending);
          final work = await queryWork(path, queries, directory);
          final payloads = queries
              .expand((query) => query.rows)
              .where((row) => row['payload'] != null || row['kind'] == 1)
              .length;
          expect(payloads, lessThan(64));
          results.add({
            'retainedResumeActions': count,
            'retainedActions': originals.payloads.length,
            'currentRecordsIncludingDeletions': originals.versions.length,
            'currentVersions': originals.versions.values.fold<int>(
              0,
              (n, text) => n + (jsonDecode(text) as List).length,
            ),
            'pendingIdentities': originals.pending.length,
            'heldActions': 1,
            'payloadsReadOnRestore': payloads,
            'upgradeMilliseconds': upgrade.elapsedMicroseconds / 1000,
            'restoreMilliseconds': restored,
            'fullReplayMilliseconds': replayed,
            'originalPayloadsUnchanged': true,
            'queryWork': work,
          });
          // ignore: avoid_print — opt-in measurement output.
          print(
            'RESTORE $count payloads=$payloads vm=${work['vmInstructions']} restore=$restored replay=$replayed upgrade=${upgrade.elapsedMilliseconds}ms',
          );
        } finally {
          await database.close();
          await directory.delete(recursive: true);
        }
      }
      await File(output!).writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'description': 'Warm host filesystem; Flutter debug test; three samples; one-time v3 upgrade separate. SQLite VM instructions measured by re-executing captured production queries on the same unchanged fixture. No Android claims.',
          'profiles': results,
        }),
      );
      final firstWork =
          (results.first['queryWork'] as Map)['vmInstructions'] as int;
      final lastWork =
          (results.last['queryWork'] as Map)['vmInstructions'] as int;
      expect(
        lastWork,
        lessThan(firstWork * 2),
        reason: 'With fixed current records and pending identities, restoration must not scan superseded actions.',
      );
    },
    skip: output == null,
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
