// Times the work of a record-store hop on the calling isolate, inline and
// through Isolate.run, as `compute` runs it. Run generate.py first.
import 'dart:convert';
import 'dart:isolate';

import 'gen/database.dart';
import 'gen/journal.dart';
import 'gen/store.dart';

const account = 'alice';
const settings = <String, dynamic>{
  'version': 3,
  'selected': 'book',
  'speed': 1.0,
  'backward': 10,
  'forward': 30,
};

Map<String, dynamic> position(int milliseconds) => {
  'edition': 'book',
  'source': 'audio',
  'revision': 'v1',
  'milliseconds': milliseconds,
};

Map<String, dynamic> event(String id, int milliseconds) => {
  'id': id,
  'at': '2026-11-07T12:00:00Z',
  'kind': 'pause',
  'bookTitle': 'Hop fixture',
  'editionLabel': 'Audio',
  'before': position(milliseconds),
  'after': position(milliseconds + 1000),
};

Map<String, dynamic> place(int milliseconds) => {
  'source': 'audio',
  'revision': 'v1',
  'sources': 'recording',
  'milliseconds': milliseconds,
  'pendingOffline': false,
};

/// A journal of [count] actions as listening makes them: every other one
/// moves the place, and the others add a history entry.
RecordJournal journalOf(int count) {
  final journal = RecordJournal(account, 'phone');
  final resume = jsonEncode([
    'audio',
    'resumes',
    jsonEncode(['book', 'recording']),
  ]);
  for (var index = 0; index < count; index++) {
    if (index.isEven) {
      journal.change(resume, {...place(index * 1000), 'edition': 'book'});
    } else {
      journal.change(
        jsonEncode(['audio', 'history', 'h$index']),
        event('h$index', index * 1000),
      );
    }
  }
  return journal;
}

AccountRows rowsOf(RecordJournal journal) {
  final actions = (journal.encode()['actions'] as List)
      .cast<Map<String, dynamic>>();
  return (
    malformed: false,
    metadata: jsonEncode(metadataOf(settings)),
    replica: journal.replica,
    cursor: 0,
    identities: [for (final action in actions) RecordJournal.identity(action)],
    payloads: [for (final action in actions) jsonEncode(action)],
    pending: journal.pending.toList(),
    versions: {
      for (final entry in journal.current.entries)
        entry.key: jsonEncode(entry.value),
    },
    coverage: Map.of(journal.coverage),
  );
}

/// Saved text in the format before the journal with [count] records.
String textOf(int count) => jsonEncode({
  ...settings,
  'history': [
    for (var index = 1; index < count; index++) event('h$index', index * 1000),
  ],
  'bookmarks': <dynamic>[],
  'resumes': {
    if (count > 0) 'book': [place(0)],
  },
});

double median(List<int> values) => (values..sort())[values.length ~/ 2] * 1.0;

const runs = 201;
const warmup = 50;

/// Microseconds on this isolate to run [work] here.
double inline<M>(Object Function(M) work, M input) {
  final times = <int>[];
  for (var run = 0; run < warmup + runs; run++) {
    final watch = Stopwatch()..start();
    work(input);
    if (run >= warmup) times.add(watch.elapsedMicroseconds);
  }
  return median(times);
}

/// Microseconds on this isolate to hand [work] to another isolate and take
/// its result back: the synchronous start of Isolate.run, which copies the
/// input, plus the time from the worker's end to this isolate's resumption.
Future<double> hop<M>(Object Function(M) work, M input) async {
  final times = <int>[];
  for (var run = 0; run < warmup + runs; run++) {
    final watch = Stopwatch()..start();
    final result = Isolate.run(() {
      final value = work(input);
      return (value, DateTime.now().microsecondsSinceEpoch);
    });
    final start = watch.elapsedMicroseconds;
    final (_, ended) = await result;
    final resumed = DateTime.now().microsecondsSinceEpoch;
    if (run >= warmup) times.add(start + (resumed - ended));
  }
  return median(times);
}

Future<void> main() async {
  print('A saved text without records, by length in characters:');
  print('chars  text-inline text-hop');
  for (final value in <Map<String, dynamic>>[
    {},
    {'version': 3},
    {'version': 3, 'selected': 'book', 'speed': 1.0},
    settings,
  ]) {
    final text = (account: account, text: jsonEncode(value), database: true);
    print(
      [
        '${text.text.length}'.padLeft(5),
        inline(restoreText, text).toStringAsFixed(0).padLeft(12),
        (await hop(restoreText, text)).toStringAsFixed(0).padLeft(8),
      ].join(' '),
    );
  }
  print('');
  print(
    'items  chars  rows-inline rows-hop  views-inline views-hop  text-inline text-hop',
  );
  for (final count in [0, 1, 2, 3, 4, 6, 8, 12, 16]) {
    final journal = journalOf(count);
    final rows = (account: account, rows: rowsOf(journal));
    final views = (
      metadata: metadataOf(settings),
      versions: {
        for (final entry in journal.versionsByRecord.entries)
          entry.key: [...entry.value],
      },
    );
    final text = (account: account, text: textOf(count), database: true);
    print(
      [
        '$count'.padLeft(5),
        '${text.text.length}'.padLeft(6),
        inline(restoreRows, rows).toStringAsFixed(0).padLeft(12),
        (await hop(restoreRows, rows)).toStringAsFixed(0).padLeft(8),
        inline(viewsOfVersions, views).toStringAsFixed(0).padLeft(13),
        (await hop(viewsOfVersions, views)).toStringAsFixed(0).padLeft(9),
        inline(restoreText, text).toStringAsFixed(0).padLeft(12),
        (await hop(restoreText, text)).toStringAsFixed(0).padLeft(8),
      ].join(' '),
    );
  }
}
