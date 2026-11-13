import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:bookfin/sync/transport.dart';
import 'package:bookfin/playback/database.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:bookfin/playback/store.dart';
import 'package:bookfin/sync/journal.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../playback/playback_test.dart'
    show LocalFiles, TestEngine, account, title, recording;
import '../sync/fixture.dart';

const samples = 8;

Map<String, dynamic> statistics(List<double> milliseconds) {
  final sorted = milliseconds.toList()..sort();
  return {
    'samples': milliseconds.length,
    'minimumMilliseconds': sorted.first,
    'medianMilliseconds': (sorted[3] + sorted[4]) / 2,
    'maximumMilliseconds': sorted.last,
    'meanMilliseconds':
        milliseconds.reduce((first, second) => first + second) /
        milliseconds.length,
  };
}

Map<String, dynamic> position(int milliseconds) => {
  'edition': 'book',
  'source': 'audio',
  'revision': 'v1',
  'milliseconds': milliseconds,
};

Map<String, dynamic> resume(int milliseconds, {String edition = 'book'}) => {
  ...position(milliseconds),
  'edition': edition,
  'sources': 'same-recording',
  'pendingOffline': true,
};

Map<String, dynamic> history(String identity) => {
  'id': identity,
  'at': '1970-01-01T00:00:00Z',
  'kind': 'pause',
  'bookTitle': 'Growth fixture',
  'editionLabel': 'Audio',
  'before': position(0),
  'after': position(0),
};

String resumeAddress(String edition) => jsonEncode([
  'audio',
  'resumes',
  jsonEncode([edition, 'same-recording']),
]);

Map<String, dynamic> seededState(
  int resumeActions, {
  required bool allPending,
  String account = 'growth',
}) {
  final journal = RecordJournal(account, 'local');
  for (var index = 0; index < 32; index++) {
    journal.change(
      jsonEncode(['audio', 'history', 'history-$index']),
      history('history-$index'),
    );
  }
  for (var index = 0; index < 8; index++) {
    journal.change(jsonEncode(['audio', 'bookmarks', 'bookmark-$index']), {
      'id': 'bookmark-$index',
      'position': position(0),
      'createdAt': '1970-01-01T00:00:00Z',
      'bookTitle': 'Growth fixture',
      'editionLabel': 'Audio',
      'title': 'bookmark-$index',
    });
  }
  journal.change(jsonEncode(['reading', 'bookmarks', 'reading-one']), {
    'id': 'reading-one',
    'position': {
      'edition': 'book',
      'source': 'ebook',
      'revision': 'text-v1',
      'anchor': 'page-one',
    },
    'createdAt': '1970-01-01T00:00:00Z',
    'title': 'Reading bookmark',
  });
  journal.change(jsonEncode(['audio', 'history', 'history-0']), null);
  journal.change(jsonEncode(['audio', 'bookmarks', 'bookmark-0']), null);
  final encoded = journal.encode();
  final actions = encoded['actions'] as List<Map<String, dynamic>>;
  final baseSequence = actions.length;
  for (var index = 1; index <= resumeActions; index++) {
    final sequence = baseSequence + index;
    actions.add({
      'version': 1,
      'account': account,
      'replica': 'local',
      'sequence': sequence,
      'context': {'local': sequence - 1},
      'record': resumeAddress('book'),
      'value': resume(index * 1000),
      'preserve': <String>[],
    });
  }
  final localActions = actions.toList();
  for (final entry in [('other_a', 500), ('other_b', 900)]) {
    actions.add({
      'version': 1,
      'account': account,
      'replica': entry.$1,
      'sequence': 1,
      'context': <String, int>{},
      'record': resumeAddress('conflicted-book'),
      'value': resume(entry.$2, edition: 'conflicted-book'),
      'preserve': <String>[],
    });
  }
  actions.add({
    'version': 1,
    'account': account,
    'replica': 'gap',
    'sequence': 2,
    'context': {'gap': 1},
    'record': jsonEncode(['audio', 'history', 'gap-event']),
    'value': history('gap-event'),
    'preserve': <String>[],
  });
  encoded['pending'] =
      (allPending
              ? localActions
              : localActions.skip(max(0, localActions.length - 16)))
          .map(RecordJournal.identity)
          .toList();
  RecordJournal(account, 'local', encoded).checkInvariants();
  return {
    'version': 3,
    'history': [],
    'bookmarks': [],
    'resumes': <String, dynamic>{},
    'sync': encoded,
  };
}

class MeasuredRecords extends ListeningStore {
  MeasuredRecords(this.records);
  final LocalResumeStore records;
  int writes = 0;
  Future<void> idle = Future.value();
  @override
  Future<Map<String, dynamic>?> read(String accountKey) =>
      records.read(accountKey);
  @override
  void acceptSnapshot(String accountKey, Map<String, dynamic>? value) =>
      records.acceptSnapshot(accountKey, value);
  @override
  Future<void> save(String accountKey, ListeningChanges changes) {
    writes++;
    return idle = records.save(accountKey, changes);
  }
}

Future<Map<String, dynamic>> cadence(Directory directory) async {
  final database = await RecordDatabase.open(
    factory: databaseFactoryFfi,
    path: '${directory.path}/cadence.sqlite',
  );
  final records = MeasuredRecords(
    LocalResumeStore(openDatabase: () async => database),
  );
  final engine = TestEngine();
  final downloads = LocalFiles();
  final playback = Playback(
    downloads: downloads,
    engine: engine,
    store: records,
  );
  try {
    await playback.bind(account(), [title]);
    await playback.open(title, recording);
    await playback.flush();
    final before = records.writes;
    final original =
        jsonDecode((await database.read(account().scope.key))!) as Map;
    for (var milliseconds = 100; milliseconds <= 2000; milliseconds += 100) {
      engine.emit(0, milliseconds, playing: true);
      await Future<void>.delayed(Duration.zero);
      await records.idle;
    }
    final after =
        jsonDecode((await database.read(account().scope.key))!) as Map;
    final newActions =
        (after['sync']['actions'] as List).length -
        (original['sync']['actions'] as List).length;
    expect(records.writes - before, 2);
    expect(newActions, 2);
    expect(
      (after['sync']['pending'] as List).length -
          (original['sync']['pending'] as List).length,
      2,
    );
    return {
      'syntheticDecoderSamples': 20,
      'sourcePositionStepMilliseconds': 100,
      'sourcePositionDurationMilliseconds': 2000,
      'databaseWrites': records.writes - before,
      'newImmutableResumeActions': newActions,
      'newPendingActions': 2,
      'realTimeListeningMeasured': false,
    };
  } finally {
    await playback.close();
    downloads.dispose();
    await database.close();
  }
}

Future<Map<String, dynamic>> measure(
  Directory directory,
  int retainedResumes,
  bool allPending,
) async {
  final name =
      '$retainedResumes-${allPending ? 'offline' : 'mostly-acknowledged'}';
  final path = '${directory.path}/$name.sqlite';
  final database = await RecordDatabase.open(
    factory: databaseFactoryFfi,
    path: path,
  );
  final state = seededState(retainedResumes, allPending: allPending);
  await database.write('growth', jsonEncode(state));
  final store = LocalResumeStore(openDatabase: () async => database);
  final startup = Stopwatch()..start();
  await store.read('growth');
  startup.stop();
  await store.write('growth', {
    'version': 3,
    'history': [],
    'bookmarks': [],
    'resumes': <String, dynamic>{},
  });
  final initial = jsonDecode((await database.read('growth'))!) as Map;
  final initialActions = (initial['sync']['actions'] as List)
      .cast<Map<String, dynamic>>();
  final initialPending = (initial['sync']['pending'] as List).cast<String>();
  var snapshot = (await store.read('growth'))!;
  store.acceptSnapshot('growth', snapshot);
  final sql = await databaseFactoryFfi.openDatabase(path);
  await auditWrites(sql);
  var milliseconds = retainedResumes * 1000;
  final writeTimes = <double>[];
  for (var iteration = 0; iteration < samples + 2; iteration++) {
    milliseconds += 1000;
    ((snapshot['resumes'] as Map)['book'] as List).single['milliseconds'] =
        milliseconds;
    final watch = Stopwatch()..start();
    await store.write('growth', snapshot);
    watch.stop();
    if (iteration >= 2) {
      writeTimes.add(watch.elapsedMicroseconds / 1000);
    }
  }
  final work = await sql.rawQuery(
    'SELECT kind, count(*) AS rows, sum(bytes) AS bytes FROM measured_row_writes GROUP BY kind',
  );
  expect(
    work.singleWhere((row) => row['kind'] == 'record_actions.insert')['rows'],
    samples + 2,
  );
  expect(
    work.where(
      (row) =>
          (row['kind'] as String).startsWith('record_actions.') &&
          row['kind'] != 'record_actions.insert',
    ),
    isEmpty,
  );
  final saved = (await database.read('growth'))!;
  final decodeTimes = <double>[];
  for (var iteration = 0; iteration < samples; iteration++) {
    final watch = Stopwatch()..start();
    final decoded = jsonDecode(saved) as Map<String, dynamic>;
    final replayed = RecordJournal(
      'growth',
      'local',
      decoded['sync'] as Map<String, dynamic>,
    );
    watch.stop();
    expect(
      replayed.encode()['actions'],
      hasLength(initialActions.length + samples + 2),
    );
    decodeTimes.add(watch.elapsedMicroseconds / 1000);
  }
  await database.checkInvariants();
  await store.checkInvariants();
  await database.close();
  final reopened = await RecordDatabase.open(
    factory: databaseFactoryFfi,
    path: path,
  );
  try {
    final restarted = LocalResumeStore(openDatabase: () async => reopened);
    final restartWatch = Stopwatch()..start();
    snapshot = (await restarted.read('growth'))!;
    restartWatch.stop();
    final restartedRaw = jsonDecode((await reopened.read('growth'))!) as Map;
    final journal = RecordJournal(
      'growth',
      'local',
      (restartedRaw['sync'] as Map).cast<String, dynamic>(),
    );
    final retained = {
      for (final action
          in journal.encode()['actions'] as List<Map<String, dynamic>>)
        RecordJournal.identity(action): action,
    };
    for (final action in initialActions) {
      expect(retained[RecordJournal.identity(action)], action);
    }
    expect(journal.pending, containsAll(initialPending));
    expect(journal.pending, hasLength(initialPending.length + samples + 2));
    expect(
      journal.conflicts.values.single.map(
        (action) => action['value']['milliseconds'],
      ),
      unorderedEquals([500, 900]),
    );
    expect(retained, contains('action.gap.2'));
    expect(
      journal.values,
      isNot(contains(jsonEncode(['audio', 'history', 'gap-event']))),
    );
    snapshot = (await restarted.read('growth'))!;
    expect(snapshot['history'], hasLength(31));
    expect(snapshot['bookmarks'], hasLength(7));
    expect(
      (await restarted.reading.read('growth'))!['bookmarks'],
      hasLength(1),
    );
    expect(await restarted.read('another-account'), isNull);
    await reopened.checkInvariants();
    return {
      'profile': name,
      'retainedResumeActionsAtStart': retainedResumes,
      'totalRetainedActionsAtStart': initialActions.length,
      'pendingActionsAtStart': initialPending.length,
      'journalAndMetadataExportUtf8BytesAtStart': utf8
          .encode(jsonEncode(initial))
          .length,
      'journalAndMetadataExportUtf8BytesAfterSamples': utf8
          .encode(saved)
          .length,
      'logicalRowWritesAcrossTenSavesIncludingWarmup': work,
      'closedSqliteFileBytes': await File(path).length(),
      'ordinarySaveIncludingNewActionValidationAndSqliteCommit': statistics(
        writeTimes,
      ),
      'migrationStartupMilliseconds': startup.elapsedMicroseconds / 1000,
      'normalizedRestartMilliseconds': restartWatch.elapsedMicroseconds / 1000,
      'explicitWholeHistoryExportDecodeAndReplayOnly': statistics(decodeTimes),
      'allOriginalActionsAndPendingRetainedAfterRestart': true,
      'historyDeletionsReadingConflictsAndCausalGapRetainedAfterRestart': true,
      'preconditioningWrites': 1,
      'warmupWrites': 2,
      'measuredWrites': samples,
    };
  } finally {
    await reopened.close();
  }
}

Future<void> auditWrites(Database database) async {
  await database.execute(
    'CREATE TABLE measured_row_writes (kind TEXT NOT NULL, bytes INTEGER NOT NULL)',
  );
  for (final table in [
    'record_accounts',
    'record_actions',
    'record_versions',
    'record_coverage',
  ]) {
    final column = switch (table) {
      'record_accounts' => 'metadata',
      'record_actions' => 'payload',
      'record_versions' => 'identities',
      _ => 'sequence',
    };
    for (final operation in ['INSERT', 'UPDATE']) {
      final bytes = table == 'record_actions' && operation == 'UPDATE'
          ? '1'
          : 'length(CAST(NEW.$column AS BLOB))';
      await database.execute(
        '''CREATE TRIGGER measured_${table}_${operation.toLowerCase()}
        AFTER $operation ON $table BEGIN
          INSERT INTO measured_row_writes VALUES ('$table.${operation.toLowerCase()}', $bytes);
        END''',
      );
    }
  }
  await database.execute(
    "CREATE TRIGGER immutable_payload BEFORE UPDATE OF payload ON record_actions BEGIN SELECT RAISE(ABORT, 'measurement forbids rewriting retained payloads'); END",
  );
  await database.execute(
    "CREATE TRIGGER immutable_action BEFORE DELETE ON record_actions BEGIN SELECT RAISE(ABORT, 'measurement forbids deleting retained actions'); END",
  );
}

Future<Map<String, dynamic>> measureAcknowledgments(
  Directory directory,
  int retainedResumes,
) async {
  final fixture = await SyncFixture.open();
  final account = fixture.session.scope.key;
  final path = '${directory.path}/$retainedResumes-ack.sqlite';
  var database = await RecordDatabase.open(
    factory: databaseFactoryFfi,
    path: path,
  );
  try {
    await database.write(
      account,
      jsonEncode(
        seededState(retainedResumes, allPending: false, account: account),
      ),
    );
    var store = LocalResumeStore(openDatabase: () async => database);
    await RecordTransport(store).synchronize(fixture.session, fixture.client);
    final sql = await databaseFactoryFfi.openDatabase(path);
    await auditWrites(sql);
    final times = <double>[];
    var snapshot = (await store.read(account))!;
    for (var iteration = 0; iteration < samples; iteration++) {
      ((snapshot['resumes'] as Map)['book'] as List).single['milliseconds'] =
          (retainedResumes + iteration + 1) * 1000;
      await store.write(account, snapshot);
      final watch = Stopwatch()..start();
      await RecordTransport(store).synchronize(fixture.session, fixture.client);
      watch.stop();
      times.add(watch.elapsedMicroseconds / 1000);
    }
    final work = await sql.rawQuery(
      'SELECT kind, count(*) AS rows, sum(bytes) AS bytes FROM measured_row_writes GROUP BY kind',
    );
    expect(
      work.singleWhere((row) => row['kind'] == 'record_actions.update')['rows'],
      samples,
    );
    final saved = jsonDecode((await database.read(account))!) as Map;
    expect(saved['sync']['pending'], isEmpty);
    final actions = saved['sync']['actions'];
    await store.checkInvariants();
    await database.close();
    database = await RecordDatabase.open(
      factory: databaseFactoryFfi,
      path: path,
    );
    store = LocalResumeStore(openDatabase: () async => database);
    snapshot = (await store.read(account))!;
    expect(
      (jsonDecode((await database.read(account))!) as Map)['sync']['actions'],
      actions,
    );
    expect(
      (jsonDecode((await database.read(account))!) as Map)['sync']['pending'],
      isEmpty,
    );
    expect(snapshot['history'], hasLength(31));
    await store.checkInvariants();
    return {
      'retainedResumeActionsAtStart': retainedResumes,
      'singlePendingUploadAckAndDiscoveryIncludingLoopbackHttp': statistics(
        times,
      ),
      'logicalRowWritesAcrossEightSavesAndSyncs': work,
      'acknowledgedActionsAndEmptyPendingSurviveRestart': true,
    };
  } finally {
    await database.close();
    await fixture.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  HttpOverrides.global = null;
  final destination = Platform.environment['BOOKFIN_JOURNAL_GROWTH_EVIDENCE'];
  test(
    'measure incremental saves and acknowledgments while retaining every original action',
    () async {
      SharedPreferences.setMockInitialValues({});
      final directory = await Directory.systemTemp.createTemp(
        'bookfin-journal-growth-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final cadenceResult = await cadence(directory);
      final profiles = <Map<String, dynamic>>[];
      for (final size in [60, 600, 3600, 21600]) {
        profiles.add(await measure(directory, size, true));
      }
      profiles.add(await measure(directory, 21600, false));
      final acknowledgments = <Map<String, dynamic>>[];
      for (final size in [60, 600, 3600, 21600]) {
        acknowledgments.add(await measureAcknowledgments(directory, size));
      }
      final evidence = {
        'ticket': 't6-t9po',
        'measuredAtUtc': DateTime.now().toUtc().toIso8601String(),
        'host': Platform.operatingSystem,
        'dart': Platform.version,
        'baseCommit': (await Process.run('git', [
          'rev-parse',
          'HEAD',
        ])).stdout.toString().trim(),
        'cadence': cadenceResult,
        'profiles': profiles,
        'acknowledgments': acknowledgments,
        'sourcesSha256': {
          for (final name in [
            'lib/playback/playback.dart',
            'lib/playback/store.dart',
            'lib/playback/database.dart',
            'lib/sync/journal.dart',
            'test/research/journal_growth_measurement_test.dart',
          ])
            name: sha256.convert(await File(name).readAsBytes()).toString(),
        },
        'limits': [
          'Synthetic host fixtures, not Android performance or real-time listening',
          'Eight measured saves after two warmups per profile, not a soak or hardening campaign',
          'Test-owned SQLite audit triggers count logical changed rows and field bytes, not filesystem, flash, or WAL write amplification; totals include warmups',
          'Acknowledgment samples include loopback HTTP validation, one upload, its durable acknowledgment, and discovery; initial pending uploads are cleared before timing',
          'Normalized startup reads committed current and held payloads plus pending identities; legacy migration and explicit verification still read every action',
          'Restart timing uses a new owner and reopened SQLite with a warm host filesystem, not a cold process or device launch',
          'Normalized startup and memory depend on current records, held actions and pending identities; retained disk storage continues growing without compaction, checkpoints, pruning, or expiry',
        ],
      };
      await File(destination!).parent.create(recursive: true);
      await File(destination).writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(evidence)}\n',
      );
    },
    skip: destination == null
        ? 'Set BOOKFIN_JOURNAL_GROWTH_EVIDENCE to run the bounded host measurement.'
        : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
