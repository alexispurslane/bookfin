import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:bookfin/downloads/derived_files.dart';
import 'package:bookfin/downloads/downloads.dart';
import 'package:bookfin/reader/book_crop.dart';
import 'package:bookfin/reader/running_lines.dart';
import 'package:bookfin/reader/survey_files.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

const book = 'b0b0';

/// A made-up page [number]: a body page with a running header that the
/// templates of [profileOf] match, a folio, and text between them.
SurveyedPage pageOf(int number) => SurveyedPage(
  edges: (
    sourcePage: number,
    bodyLineHeight: 0.024,
    body: number % 7 != 0,
    edges: [
      (
        line: 0,
        box: (left: 0.2, top: 0.05, right: 0.8, bottom: 0.07),
        text: 'A Short Book',
        gap: 0.04,
      ),
      (
        line: 30,
        box: (left: 0.1, top: 1.3, right: 0.12, bottom: 1.32),
        text: null,
        gap: double.infinity,
      ),
    ],
    regions: [
      (region: 0, box: (left: 0.06, top: 0.03, right: 0.07, bottom: 0.05)),
      (region: 2, box: (left: 0.4, top: 1.36, right: 0.6, bottom: 1.39)),
    ],
  ),
  height: 1.414,
  core: number % 11 == 0
      ? null
      : (left: 0.1 + number % 2 / 50, top: 0.1, right: 0.85, bottom: 1.2),
);

BookProfile profileOf() => BookProfile(
  templates: RunningTemplates(
    lineHeight: 0.024,
    texts: [
      (
        signature: 'a short book',
        box: (left: 0.2, top: 0.05, right: 0.8, bottom: 0.07),
      ),
    ],
    folioOffsets: [-1, 4],
    shapes: [(side: 0, box: (left: 0.1, top: 1.3, right: 0.12, bottom: 1.32))],
    regions: [
      (side: 1, box: (left: 0.06, top: 0.03, right: 0.07, bottom: 0.05)),
    ],
  ),
  boxes: [(left: 0.08, top: 0.09, right: 0.86, bottom: 1.21), null],
);

/// A survey of the pages [numbers], with the profile of [profileOf] when
/// [frozen].
KeptSurvey surveyOf(Iterable<int> numbers, {bool frozen = true}) => (
  pages: [for (final number in numbers) pageOf(number)],
  profile: frozen ? profileOf() : null,
);

/// A lease of the download [original] that is always available.
SurveyLease leaseOf(File original, {String digest = book}) =>
    (use) => use(VerifiedFile(original.uri, digest), () => true);

/// Runs [work] on [input] where it is called.
Future<R> inPlace<M, R>(FutureOr<R> Function(M) work, M input) async =>
    work(input);

void main() {
  late Directory root;
  late File original;
  late File kept;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('bookfin-survey-');
    original = await File('${root.path}/complete').writeAsString('%PDF-');
    kept = File('${DerivedBookFiles.surveyDirectory(original).path}/survey');
  });
  tearDown(() => root.delete(recursive: true));

  SurveyFiles files({String digest = book}) => SurveyFiles(
    leaseOf(original, digest: digest),
    book: book,
    hop: inPlace,
  );

  /// Keeps [survey] as a survey does: a read, then a write.
  Future<void> keep(KeptSurvey survey) async {
    final store = files();
    await store.read();
    await store.write(survey);
  }

  /// The crops that [survey] gives each of its pages, or nothing before it
  /// froze.
  List<Object> cropsOf(KeptSurvey survey) => [
    for (final page in survey.pages)
      [
        page.sourcePage,
        page.body,
        survey.profile == null ? null : cropOf(page, survey.profile!),
        survey.profile == null
            ? null
            : [
                for (final edge in page.edges.edges)
                  survey.profile!.templates.matches(page.sourcePage, edge),
                for (final region in page.edges.regions)
                  survey.profile!.templates.matchesRegion(
                    page.sourcePage,
                    region,
                  ),
              ],
      ],
  ];

  test('a kept survey reads back with the same pages, crops and running '
      'lines', () async {
    final written = surveyOf(List.generate(40, (index) => index + 1));
    await keep(written);
    final read = (await files().read())!;
    expect(cropsOf(read), cropsOf(written));
    expect(read.profile!.boxes, written.profile!.boxes);
  });

  test(
    'a survey that has not frozen yet reads back without a profile',
    () async {
      await keep(surveyOf([3, 4, 5], frozen: false));
      final read = (await files().read())!;
      expect(read.profile, isNull);
      expect([for (final page in read.pages) page.sourcePage], [3, 4, 5]);
    },
  );

  test('a kill during a write leaves the old or the new survey, never a '
      'broken one', () async {
    final path = original.path;
    await keep(surveyOf([1, 2]));
    final random = math.Random(20261110);
    for (var round = 0; round < 12; round++) {
      final exit = ReceivePort();
      final isolate = await Isolate.spawn(
        (_) async {
          final lease = leaseOf(File(path));
          final store = SurveyFiles(lease, book: book, hop: inPlace);
          await store.read();
          await store.write(
            surveyOf(List.generate(6000, (index) => index + 1)),
          );
        },
        null,
        onExit: exit.sendPort,
      );
      await Future<void>.delayed(Duration(microseconds: random.nextInt(40000)));
      isolate.kill(priority: Isolate.immediate);
      await exit.first;

      final read = await files().read();
      expect(read!.pages.length, anyOf(2, 6000), reason: 'round $round');
      expect(
        await File('${kept.path}.unreadable').exists(),
        isFalse,
        reason: 'round $round',
      );
      await keep(surveyOf([1, 2]));
    }
  });

  group('an unreadable survey', () {
    late List<FlutterErrorDetails> reports;
    late FlutterExceptionHandler? handler;
    setUp(() {
      reports = [];
      handler = FlutterError.onError;
      FlutterError.onError = reports.add;
    });
    tearDown(() => FlutterError.onError = handler);

    for (final (name, bytes) in [
      (
        'cut short',
        '{"format":${SurveyFiles.format},"book":"b0b0","pages":[[1,0.0'
            .codeUnits,
      ),
      (
        'of the wrong shape',
        '{"format":${SurveyFiles.format},"book":"b0b0","pages":7}'.codeUnits,
      ),
      ('not text', [0xff, 0xfe, 0x00, 0x13]),
    ]) {
      test('$name is kept aside and reported, and the next write does not '
          'replace it', () async {
        await kept.parent.create();
        await kept.writeAsBytes(bytes);
        final store = files();
        expect(await store.read(), isNull);
        expect(reports, hasLength(1));
        expect(await File('${kept.path}.unreadable').readAsBytes(), bytes);

        await store.write(surveyOf([1]));
        expect(await File('${kept.path}.unreadable').readAsBytes(), bytes);
        expect((await files().read())!.pages.single.sourcePage, 1);
      });
    }
  });

  test('a survey of another book is not used, and a write replaces it, '
      'without a report', () async {
    final other = SurveyFiles(leaseOf(original), book: 'other', hop: inPlace);
    await other.read();
    await other.write(surveyOf([1, 2, 3]));
    final store = files();
    expect(await store.read(), isNull);
    await store.write(surveyOf([4]));
    expect((await files().read())!.pages.single.sourcePage, 4);
    expect(await File('${kept.path}.unreadable').exists(), isFalse);
  });

  test('a store that never reached the download keeps nothing, so it never '
      'replaces a survey that it did not read', () async {
    await keep(surveyOf([1, 2, 3]));
    var available = false;
    final store = SurveyFiles(
      (use) async {
        if (available) await use(VerifiedFile(original.uri, book), () => true);
      },
      book: book,
      hop: inPlace,
    );
    expect(await store.read(), isNull);
    available = true;
    await store.write(surveyOf([9]));
    expect((await files().read())!.pages, hasLength(3));
  });

  test('a download that now holds another PDF keeps the survey of the open '
      'book out of it', () async {
    final store = files(digest: 'changed');
    expect(await store.read(), isNull);
    await store.write(surveyOf([1]));
    expect(await kept.exists(), isFalse);
  });
}
