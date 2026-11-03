import 'dart:convert';
import 'dart:io';
import 'dart:math';

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
}) {
  final journal = RecordJournal('growth', 'local');
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
      'account': 'growth',
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
      'account': 'growth',
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
    'account': 'growth',
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
  RecordJournal('growth', 'local', encoded).checkInvariants();
  return {
    'version': 3,
    'history': [],
    'bookmarks': [],
    'resumes': <String, dynamic>{},
    'sync': encoded,
  };
}

class MeasuredRecords extends ResumeStore {
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
  Future<void> write(String accountKey, Map<String, dynamic> value) {
    writes++;
    return idle = records.write(accountKey, value);
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
  var milliseconds = retainedResumes * 1000;
  final writeTimes = <double>[];
  var rewrittenPayloadBytes = 0;
  for (var iteration = 0; iteration < samples + 2; iteration++) {
    milliseconds += 1000;
    ((snapshot['resumes'] as Map)['book'] as List).single['milliseconds'] =
        milliseconds;
    final watch = Stopwatch()..start();
    await store.write('growth', snapshot);
    watch.stop();
    if (iteration >= 2) {
      writeTimes.add(watch.elapsedMicroseconds / 1000);
      rewrittenPayloadBytes += utf8
          .encode((await database.read('growth'))!)
          .length;
    }
  }
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
  await database.close();
  final reopened = await RecordDatabase.open(
    factory: databaseFactoryFfi,
    path: path,
  );
  try {
    final restarted = LocalResumeStore(openDatabase: () async => reopened);
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
      'payloadUtf8BytesAtStart': utf8.encode(jsonEncode(initial)).length,
      'payloadUtf8BytesAfterSamples': utf8.encode(saved).length,
      'logicalRowPayloadBytesWrittenAcrossEightSamples': rewrittenPayloadBytes,
      'closedSqliteFileBytes': await File(path).length(),
      'writeIncludingReplayValidationSerializationAndSqliteCommit': statistics(
        writeTimes,
      ),
      'jsonDecodeAndJournalReplayOnly': statistics(decodeTimes),
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  final destination = Platform.environment['BOOKFIN_JOURNAL_GROWTH_EVIDENCE'];
  test(
    'measure retained journal cost without removing records or changing production behavior',
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
          'Eight measured writes after two warmups per profile, not a soak or hardening campaign',
          'Logical row payload bytes are not filesystem, flash, or WAL write amplification',
          'No network synchronization, compaction, checkpoints, pruning, or production code changes',
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
