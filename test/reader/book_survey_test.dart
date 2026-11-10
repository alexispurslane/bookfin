import 'dart:async';
import 'dart:io';

import 'package:bookfin/downloads/downloads.dart';
import 'package:bookfin/foundation/hop.dart';
import 'package:bookfin/reader/book_crop.dart';
import 'package:bookfin/reader/book_survey.dart';
import 'package:bookfin/reader/pdf.dart';
import 'package:bookfin/reader/survey_files.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart' as native;

import 'book_crop_test.dart' show SplicedBook, analyzedPage, bookOf;
import 'ocr_hop_test.dart' show runInWorker;
import 'page_analysis_test.dart' show DrawnPage, DrawnPdf;
import 'running_lines_test.dart' show marginsBook;

/// The steps of a survey of a book of [pageCount] pages that opens at
/// [from], until it rests. Each page is a body page unless [outliers] holds
/// it, and [skipped] pages fail.
List<SurveyStep> stepsOf(
  int pageCount, {
  int from = 1,
  Set<int> outliers = const {},
  Set<int> skipped = const {},
  Map<int, bool>? surveyed,
  bool frozen = false,
}) {
  final pages = <int, bool>{...?surveyed};
  final failed = <int>{};
  final steps = <SurveyStep>[];
  while (steps.length < 10000) {
    final step = nextSurveyStep(
      pageCount: pageCount,
      from: from,
      surveyed: pages,
      skipped: failed,
      frozen: frozen,
    );
    steps.add(step);
    switch (step) {
      case SurveyPage(:final page):
        if (skipped.contains(page)) {
          failed.add(page);
        } else {
          pages[page] = !outliers.contains(page);
        }
      case FreezeProfile():
        frozen = true;
      case SurveyRested():
        return steps;
    }
  }
  fail('The survey did not rest.');
}

/// The pages of [steps] before the profile froze.
List<int> sampleOf(List<SurveyStep> steps) => [
  for (final step in steps.takeWhile((step) => step is! FreezeProfile))
    if (step case SurveyPage(:final page)) page,
];

/// The pages of [steps] after the profile froze.
List<int> restOf(List<SurveyStep> steps) => [
  for (final step in steps.skipWhile((step) => step is! FreezeProfile))
    if (step case SurveyPage(:final page)) page,
];

/// A lease of the download [original] that is always available.
SurveyLease leaseOf(File original, String digest) =>
    (use) => use(VerifiedFile(original.uri, digest), () => true);

/// A kept survey whose read ends when the test completes [reading]. It
/// keeps nothing.
class UnreadSurvey implements SurveyFiles {
  final reading = Completer<KeptSurvey?>();
  @override
  String get book => 'unread';
  @override
  IsolateHop get hop => runInWorker;
  @override
  Future<KeptSurvey?> read() => reading.future;
  @override
  Future<void> write(KeptSurvey survey) async {}
}

/// A made-up scanned page of 30 prose lines whose text starts [left] pixels
/// from the left edge, as a page of a printed book with mirrored margins.
DrawnPage proseAt(int left) => DrawnPage([
  for (var line = 0; line < 30; line++)
    [
      for (var word = 0; word < 8; word++)
        [
          left + word * 140,
          200 + line * 64,
          left + word * 140 + 120,
          240 + line * 64,
        ],
    ],
]);

/// A drawn book whose renders wait until the test lets them through.
class HeldRenders extends DrawnPdf {
  HeldRenders(super.pages) : super(hop: runInWorker);
  final waiting = <({int page, Completer<void> release})>[];
  var holding = true;
  @override
  Future<PdfRaster> render(int sourcePage, double width) async {
    if (holding) {
      final release = Completer<void>();
      waiting.add((page: sourcePage, release: release));
      await release.future;
    }
    return super.render(sourcePage, width);
  }
}

/// Waits until [holds] is true, failing after 20 seconds.
Future<void> until(bool Function() holds, String what) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (!holds()) {
    if (DateTime.now().isAfter(deadline)) fail('Never: $what.');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  native.Pdfrx.pdfiumModulePath = Platform.environment['PDFIUM_LIBRARY'];
  native.Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;
  tearDownAll(() => PdfRuntime.instance.shutdown());

  group('the order of the survey', () {
    test('starts with the shown page and the next page', () {
      final steps = stepsOf(100, from: 40);
      expect(steps.take(2), const [SurveyPage(40), SurveyPage(41)]);
    });

    test('then samples up to 32 pages of each side spread over the whole '
        'book, and freezes the profile', () {
      final steps = stepsOf(200, from: 40);
      // The shown page and the next page count in the sample too.
      final sample = sampleOf(steps);
      expect(steps.whereType<FreezeProfile>(), hasLength(1));
      for (final side in [0, 1]) {
        final pages = [
          for (final page in sample)
            if (page % 2 == side) page,
        ]..sort();
        expect(pages, hasLength(lessThanOrEqualTo(33)));
        expect(pages.length, greaterThanOrEqualTo(32));
        expect(pages.first, lessThanOrEqualTo(8));
        expect(pages.last, greaterThanOrEqualTo(192));
        for (var index = 1; index < pages.length; index++) {
          expect(pages[index] - pages[index - 1], lessThanOrEqualTo(8));
        }
      }
    });

    test('a book of at most 32 pages a side samples every page', () {
      final steps = stepsOf(13, from: 5);
      expect(sampleOf(steps)..sort(), List.generate(13, (page) => page + 1));
      expect(restOf(steps), isEmpty);
    });

    test('a page of the sample that is no body page is replaced by the next '
        'page of its side', () {
      final plain = sampleOf(stepsOf(200));
      final target = plain.firstWhere((page) => page > 50);
      final sample = sampleOf(stepsOf(200, outliers: {target}));
      expect(sample, contains(target + 2));
      expect(plain, isNot(contains(target + 2)));
    });

    test('after the freeze, the rest follows in order from the shown page, '
        'then from the start', () {
      final steps = stepsOf(200, from: 101);
      final rest = restOf(steps);
      final after = rest.takeWhile((page) => page > 101).toList();
      expect(after, orderedEquals([...after]..sort()));
      expect(
        rest.skip(after.length),
        orderedEquals([...rest.skip(after.length)]..sort()),
      );
      expect(rest.skip(after.length).first, lessThan(101));
    });

    test('runs every page once, and asks for no skipped page again', () {
      final steps = stepsOf(150, from: 77, skipped: {3, 80, 140});
      final pages = [
        for (final step in steps)
          if (step case SurveyPage(:final page)) page,
      ];
      expect(pages.toSet(), hasLength(pages.length));
      expect(pages.toSet(), Set.of(List.generate(150, (page) => page + 1)));
      expect(steps.last, const SurveyRested());
    });

    test('a kept survey goes on where it stopped', () {
      final first = stepsOf(200, from: 10);
      final pages = [
        for (final step in first.take(90))
          if (step case SurveyPage(:final page)) page,
      ];
      final frozen = first.take(90).contains(const FreezeProfile());
      final again = stepsOf(
        200,
        from: 150,
        surveyed: {for (final page in pages) page: true},
        frozen: frozen,
      );
      final later = [
        for (final step in again)
          if (step case SurveyPage(:final page)) page,
      ];
      expect(later.take(2), [150, 151]);
      expect({...pages, ...later}, hasLength(200));
      expect(pages.toSet().intersection(later.toSet()), isEmpty);
    });

    test('a failed page of the sample is replaced by the next page of its '
        'side, and the profile freezes', () {
      final plain = sampleOf(stepsOf(200));
      final target = plain.firstWhere((page) => page > 50);
      final steps = stepsOf(200, skipped: {target});
      expect(sampleOf(steps), contains(target + 2));
      expect(steps.whereType<FreezeProfile>(), hasLength(1));
    });

    test('a failed page that leaves the sample short keeps the profile from '
        'freezing in this session, and the rest is still surveyed', () {
      // In a book of at most 32 pages a side, every page is in the sample.
      final steps = stepsOf(20, from: 5, skipped: {12});
      expect(steps.whereType<FreezeProfile>(), isEmpty);
      final pages = [
        for (final step in steps)
          if (step case SurveyPage(:final page)) page,
      ];
      expect(pages.toSet(), Set.of(List.generate(20, (page) => page + 1)));
      expect(steps.last, const SurveyRested());
    });
  });

  group('the survey of a book', () {
    late Directory root;
    late File original;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('bookfin-book-survey-');
      original = await File('${root.path}/complete').writeAsString('%PDF-');
    });
    tearDown(() => root.delete(recursive: true));

    SurveyFiles storeOf(PdfBook book) => SurveyFiles(
      leaseOf(original, book.originalDigest),
      book: book.originalDigest,
      hop: book.hop,
    );

    Future<PdfBook> margins() async {
      final book = await PdfRuntime.instance.open(
        await File(marginsBook).readAsBytes(),
        'e' * 64,
        hop: runInWorker,
      );
      addTearDown(book.dispose);
      return book;
    }

    /// Whether every page of [book] has its crop.
    bool cropped(PdfBook book) => [
      for (var page = 1; page <= book.pageCount; page++)
        book.survey.cropOf(page),
    ].every((crop) => crop != null);

    test(
      'gives every page of the margins book the crop of the book crop',
      () async {
        final book = await margins();
        book.survey.start(storeOf(book), from: 5);
        await until(() => cropped(book), 'every page has its crop');

        final pages = bookOf([
          for (var page = 1; page <= book.pageCount; page++)
            await analyzedPage(book, page),
        ]);
        final profile = bookProfile(pages);
        expect(book.survey.profile!.boxes, profile.boxes);
        for (final page in pages) {
          expect(book.survey.cropOf(page.sourcePage), cropOf(page, profile));
        }
        book.survey.checkInvariants();
        await book.survey.close();
      },
    );

    test('tells its listeners when crops become known', () async {
      final book = await margins();
      var told = 0;
      book.survey.crops.addListener(() => told++);
      book.survey.start(storeOf(book), from: 1);
      await until(() => cropped(book), 'every page has its crop');
      expect(told, greaterThan(0));
      await book.survey.close();
    });

    test('a reopen goes on where the survey stopped and analyzes no page '
        'twice', () async {
      final margins = await PdfRuntime.instance.open(
        await File(marginsBook).readAsBytes(),
        'e' * 64,
        hop: runInWorker,
      );
      addTearDown(margins.dispose);
      List<(PdfBook, int)> pages() => [
        for (var page = 1; page <= 13; page++) (margins, page),
      ];
      final first = SplicedBook(pages());
      first.survey.start(storeOf(first), from: 3);
      await until(() => first.analyzed.length >= 5, '5 pages were analyzed');
      await first.survey.close();
      final before = first.analyzed.toList();
      expect(before.length, lessThan(13));

      final second = SplicedBook(pages());
      second.survey.start(storeOf(second), from: 9);
      await until(() => cropped(second), 'every page has its crop');
      await second.survey.close();
      if (!before.contains(9)) expect(second.analyzed.first, 9);
      expect([...before, ...second.analyzed]..sort(), [
        for (var page = 1; page <= 13; page++) page,
      ]);
    });

    test('pauses while the app is in the background: no page starts until it '
        'resumes', () async {
      final book = HeldRenders([
        for (var page = 1; page <= 6; page++) proseAt(page.isOdd ? 260 : 200),
      ]);
      book.survey.start(storeOf(book), from: 1);
      await until(() => book.waiting.isNotEmpty, 'the first page draws');
      book.survey.pause();
      book.holding = false;
      book.waiting.single.release.complete();
      await until(() => book.renders.isNotEmpty, 'the first page draws');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(book.renders, [1]);

      book.survey.resume();
      await until(() => cropped(book), 'every page has its crop');
      expect(book.renders.toSet(), {1, 2, 3, 4, 5, 6});
      expect(book.renders, hasLength(6));
      await book.survey.close();
    });

    test('a closed book surveys no more pages', () async {
      final book = HeldRenders([
        for (var page = 1; page <= 6; page++) proseAt(200),
      ]);
      book.survey.start(storeOf(book), from: 1);
      await until(() => book.waiting.isNotEmpty, 'the first page draws');
      final closed = book.survey.close();
      book.holding = false;
      book.waiting.single.release.complete();
      await closed;
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(book.renders, [1]);
    });

    test('the profile does not change after it freezes, and later pages get '
        'their own crops', () async {
      // 70 pages: more than the sample of 32 pages a side. The pages that the
      // survey reaches after the sample set their text further left than
      // any page of the sample.
      final rest = restOf(stepsOf(70)).toSet();
      expect(rest, isNotEmpty);
      final book = DrawnPdf([
        for (var page = 1; page <= 70; page++)
          proseAt(rest.contains(page) ? 60 : (page.isOdd ? 260 : 200)),
      ], hop: runInWorker);
      BookProfile? frozen;
      book.survey.crops.addListener(() => frozen ??= book.survey.profile);
      book.survey.start(storeOf(book), from: 1);
      await until(() => cropped(book), 'every page has its crop');
      await book.survey.close();

      expect(identical(book.survey.profile, frozen), isTrue);
      final late = [for (final page in rest) book.survey.cropOf(page)!];
      for (final crop in late) {
        expect(crop.left, lessThan(frozen!.boxes[0]!.left));
        expect(crop.left, lessThan(frozen!.boxes[1]!.left));
      }
      book.survey.checkInvariants();
    });

    test('a reopened book gives the crops that the survey kept, before any '
        'page is analyzed again', () async {
      final book = await margins();
      book.survey.start(storeOf(book), from: 1);
      await until(() => cropped(book), 'every page has its crop');
      final crops = [
        for (var page = 1; page <= 13; page++) book.survey.cropOf(page),
      ];
      await book.survey.close();

      final again = SplicedBook([
        for (var page = 1; page <= 13; page++) (book, page),
      ]);
      again.survey.start(storeOf(book), from: 1);
      await until(() => cropped(again), 'the kept crops are read');
      expect([
        for (var page = 1; page <= 13; page++) again.survey.cropOf(page),
      ], crops);
      expect(again.analyzed, isEmpty);
      await again.survey.close();
    });
  });

  group('the survey and the shown page', () {
    late Directory root;
    late File original;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('bookfin-shown-survey-');
      original = await File('${root.path}/complete').writeAsString('%PDF-');
    });
    tearDown(() => root.delete(recursive: true));

    SurveyFiles storeOf(PdfBook book) => SurveyFiles(
      leaseOf(original, book.originalDigest),
      book: book.originalDigest,
      hop: book.hop,
    );

    test(
      'the page that the reader shows and the page after it are surveyed '
      'before the rest, so the next page has its crop before a turn',
      () async {
        final rest = restOf(stepsOf(70));
        final shown = rest.firstWhere((page) => page > 20);
        final book = HeldRenders([
          for (var page = 1; page <= 70; page++)
            proseAt(page.isOdd ? 260 : 200),
        ]);
        book.survey.start(storeOf(book), from: 1);
        while (book.survey.profile == null) {
          await until(() => book.waiting.isNotEmpty, 'a page draws');
          book.waiting.removeAt(0).release.complete();
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        expect(book.survey.cropOf(shown), isNull);
        final before = book.renders.length;
        final next = book.survey.cropWithin(
          shown + 1,
          const Duration(seconds: 20),
        );

        book.survey.follow(shown);
        book.holding = false;
        for (final held in book.waiting) {
          held.release.complete();
        }
        expect(await next, isNotNull);
        // The page whose analysis ran when the reader turned finishes first.
        final after = book.renders.skip(before).toList();
        expect(after.take(3), containsAllInOrder([shown, shown + 1]));
        expect(after.indexOf(shown), lessThanOrEqualTo(1));
        await book.survey.close();
      },
    );

    test('a reopened book gives a page the kept crop that it reads within '
        'the wait', () async {
      List<DrawnPage> pages() => [
        for (var page = 1; page <= 4; page++) proseAt(page.isOdd ? 260 : 200),
      ];
      final first = DrawnPdf(pages(), hop: runInWorker);
      first.survey.start(storeOf(first), from: 1);
      await until(
        () => first.survey.cropOf(3) != null,
        'the first open surveys the book',
      );
      final kept = first.survey.cropOf(3);
      await first.survey.close();

      final again = HeldRenders(pages());
      again.survey.start(storeOf(again), from: 3);
      expect(
        await again.survey.cropWithin(3, const Duration(seconds: 20)),
        kept,
      );
      expect(again.renders, isEmpty);
      await again.survey.close();
    });

    test(
      'a crop that is not known within the wait gives the page none',
      () async {
        final book = HeldRenders([
          for (var page = 1; page <= 4; page++) proseAt(200),
        ]);
        final store = UnreadSurvey();
        book.survey.start(store, from: 1);
        final watch = Stopwatch()..start();
        expect(
          await book.survey.cropWithin(1, const Duration(milliseconds: 300)),
          isNull,
        );
        expect(
          watch.elapsed,
          greaterThanOrEqualTo(const Duration(milliseconds: 300)),
        );
        store.reading.complete(null);
        book.holding = false;
        for (final held in book.waiting) {
          held.release.complete();
        }
        await book.survey.close();
      },
    );

    test('a book without a kept profile gives no crop at once, so its first '
        'page does not wait', () async {
      final book = HeldRenders([
        for (var page = 1; page <= 4; page++) proseAt(200),
      ]);
      final unstarted = book.survey.cropWithin(1, const Duration(seconds: 20));
      book.survey.start(storeOf(book), from: 1);
      final started = book.survey.cropWithin(1, const Duration(seconds: 20));
      final watch = Stopwatch()..start();
      expect(await unstarted, isNull);
      expect(await started, isNull);
      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
      book.holding = false;
      for (final held in book.waiting) {
        held.release.complete();
      }
      await book.survey.close();
    });
  });

  group('a background analysis', () {
    test('starts only after the reader\'s own analysis ends', () async {
      final book = HeldRenders([
        for (var page = 1; page <= 3; page++) proseAt(200),
      ]);
      final shown = book.reflowPage(3);
      await until(() => book.waiting.isNotEmpty, 'the shown page draws');
      final background = book.reflowPage(1, background: true);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect([for (final held in book.waiting) held.page], [3]);
      book.waiting.single.release.complete();
      await shown;
      await until(() => book.waiting.length == 2, 'the background page draws');
      expect(book.waiting.last.page, 1);
      book.waiting.last.release.complete();
      expect(await background, isNotNull);
    });

    test('is joined by the reader\'s request for its page, which draws and '
        'analyzes the page once', () async {
      final book = HeldRenders([
        for (var page = 1; page <= 3; page++) proseAt(200),
      ]);
      final background = book.reflowPage(2, background: true);
      await until(() => book.waiting.isNotEmpty, 'the page draws');
      final shown = book.reflowPage(2);
      book.holding = false;
      book.waiting.single.release.complete();
      final pages = await Future.wait([background, shown]);
      expect(identical(pages[0]!.analysis, pages[1]!.analysis), isTrue);
      expect(book.renders, [2]);
      // The reader's page is kept, so a later request draws nothing.
      await book.reflowPage(2);
      expect(book.renders, [2]);
      book.checkInvariants();
    });

    test('leaves the pages that the reader keeps in place', () async {
      final book = DrawnPdf([
        for (var page = 1; page <= 20; page++) proseAt(200),
      ], hop: runInWorker);
      await book.reflowPage(1);
      for (var page = 2; page <= 20; page++) {
        await book.reflowPage(page, background: true);
      }
      await book.reflowPage(1);
      expect(book.renders.where((page) => page == 1), hasLength(1));
    });
  });
}
