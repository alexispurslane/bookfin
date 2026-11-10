import 'dart:async';
import 'dart:io';

import 'package:bookfin/catalog/glass.dart' show CoverGlass;
import 'package:bookfin/foundation/theme.dart';
import 'package:bookfin/playback/store.dart';
import 'package:bookfin/reader/book_crop.dart';
import 'package:bookfin/reader/book_map.dart';
import 'package:bookfin/reader/column_layout.dart';
import 'package:bookfin/reader/pdf.dart';
import 'package:bookfin/reader/pdf_viewport.dart';
import 'package:bookfin/reader/platform_io.dart';
import 'package:bookfin/reader/screen.dart';
import 'package:bookfin/reader/session.dart';
import 'package:bookfin/reader/survey_files.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart' as native;
import 'package:shared_preferences/shared_preferences.dart';

import '../playback/playback_test.dart' show account, LocalFiles, MemoryResume;
import 'book_crop_test.dart' show analyzedPage, bookOf;
import 'book_survey_test.dart' show UnreadSurvey;
import 'column_running_lines_test.dart' show headerAndFolio;
import 'native_reader.dart' show finishReader, settleReader;
import 'ocr_hop_test.dart' show runInWorker;
import 'pdf_crop_test.dart'
    show WatchedBook, advance, aspectOf, imageAspect, shownImage;
import 'pdf_document_test.dart' show pdfSource;
import 'pdf_session_test.dart' show book, edition;
import 'running_lines_test.dart' show lineTexts, marginsBook, wordsOf;

class ControlledDraws extends WatchedBook {
  ControlledDraws(super.margins);

  bool failNext = false;
  bool hold = false;
  final pending = <({int page, double width, Completer<PdfRaster> result})>[];

  @override
  Future<PdfRaster> render(int sourcePage, double width) {
    if (failNext) {
      failNext = false;
      return Future.error(Exception('The page could not be drawn.'));
    }
    if (!hold) return super.render(sourcePage, width);
    final result = Completer<PdfRaster>();
    pending.add((page: sourcePage, width: width, result: result));
    return result.future;
  }

  Future<void> complete(int index) async {
    final draw = pending[index];
    draw.result.complete(await super.render(draw.page, draw.width));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  native.Pdfrx.pdfiumModulePath = Platform.environment['PDFIUM_LIBRARY'];
  native.Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;
  late PdfBook margins;
  late KeptSurvey kept;

  setUpAll(() async {
    margins = await PdfRuntime.instance.open(
      await File(marginsBook).readAsBytes(),
      'e' * 64,
      hop: runInWorker,
    );
    final pages = bookOf([
      for (var page = 1; page <= 13; page++) await analyzedPage(margins, page),
    ]);
    kept = (pages: pages, profile: bookProfile(pages));
  });

  tearDownAll(() async {
    await margins.dispose();
    await PdfRuntime.instance.shutdown();
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  final trim = find.widgetWithText(SwitchListTile, 'Trim margins');

  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Reading settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await settleReader(
      tester,
      () => !tester.binding.hasScheduledFrame,
      reason: 'the settings sheet did not settle',
    );
  }

  Future<void> toggle(WidgetTester tester) async {
    expect(trim, findsOneWidget);
    await tester.ensureVisible(trim);
    await tester.tap(trim);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await settleReader(
      tester,
      () => !tester.binding.hasScheduledFrame,
      reason: 'the trim choice did not settle',
    );
  }

  Future<
    ({ReaderSession reader, WatchedBook pdf, Future<void> Function() close})
  >
  open(
    WidgetTester tester, {
    ReadingStore? store,
    double systemScale = 1,
    WatchedBook? source,
  }) async {
    tester.view
      ..physicalSize = const Size(1080, 2400)
      ..devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final downloads = LocalFiles()
      ..files[pdfSource.key] = Uri.file('/margins.pdf');
    final pdf = source ?? WatchedBook(margins);
    final survey = UnreadSurvey()..reading.complete(kept);
    final reader = ReaderSession(
      downloads: downloads,
      store: store ?? MemoryResume(),
      load: loadPublication,
      loadDocument: (_, _) async => pdf,
      surveyStore: (_, {required book, hop = runInWorker}) => survey,
    );
    var closed = false;
    Future<void> close() async {
      if (closed) return;
      closed = true;
      await tester.pumpWidget(const SizedBox());
      await finishReader(tester, reader.flush());
      reader.dispose();
      await finishReader(tester, pdf.survey.close());
      downloads.dispose();
    }

    addTearDown(close);
    await finishReader(tester, reader.bind(account(), [book]));
    await finishReader(tester, reader.open(book, edition));
    await tester.pumpWidget(
      MaterialApp(
        theme: bookfinTheme(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(systemScale)),
          child: child!,
        ),
        home: ReaderScreen(reader: reader, onNightChanged: (_) {}),
      ),
    );
    await settleReader(
      tester,
      () => reader.ready && pdf.survey.profile != null,
      reason: 'the PDF and its kept crop did not open',
    );
    await finishReader(tester, reader.goToContents('page:5'));
    await settleReader(
      tester,
      () => find
          .descendant(
            of: find.byType(PdfViewport),
            matching: find.byType(RawImage),
          )
          .evaluate()
          .isNotEmpty,
      reason: 'source page 5 did not draw',
    );
    return (reader: reader, pdf: pdf, close: close);
  }

  testWidgets('a new install offers Trim margins on under Pages in the glass '
      'Reading settings', (tester) async {
    await open(tester);
    await openSettings(tester);
    expect(trim, findsOneWidget);
    expect(tester.widget<SwitchListTile>(trim).value, isTrue);
    expect(
      find.ancestor(of: trim, matching: find.byType(CoverGlass)),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(trim).dy,
      greaterThan(tester.getBottomLeft(find.text('Pages')).dy),
    );
  });

  testWidgets(
    'the trim choice and text size survive a session and store restart',
    (tester) async {
      final first = await open(tester, store: LocalResumeStore().reading);
      await openSettings(tester);
      await toggle(tester);
      await tester.tap(find.byTooltip('Larger text'));
      await finishReader(tester, first.reader.flush());
      await first.close();

      final restarted = await open(tester, store: LocalResumeStore().reading);
      await openSettings(tester);
      expect(tester.widget<SwitchListTile>(trim).value, isFalse);
      expect(restarted.reader.fontSize, 22);
      final full = await tester.runAsync(() => margins.render(5, 400));
      expect(
        imageAspect(shownImage(tester)),
        closeTo(full!.width / full.height, 0.01),
      );
    },
  );

  testWidgets('switching off and on redraws the shown page without moving its '
      'place or adding a reading move', (tester) async {
    final opened = await open(tester);
    final crop = opened.pdf.survey.cropOf(5)!;
    final place = opened.reader.visibleAddress;
    final moves = opened.reader.history;
    expect(imageAspect(shownImage(tester)), closeTo(aspectOf(crop), 0.01));
    await openSettings(tester);
    await toggle(tester);
    final full = await tester.runAsync(() => margins.render(5, 400));
    await settleReader(
      tester,
      () =>
          (imageAspect(shownImage(tester)) - full!.width / full.height).abs() <
          0.01,
      reason: 'the full printed page did not replace the crop',
    );
    await toggle(tester);
    await settleReader(
      tester,
      () => (imageAspect(shownImage(tester)) - aspectOf(crop)).abs() < 0.01,
      reason: 'the crop did not replace the full printed page',
    );
    expect(opened.reader.visibleAddress, place);
    expect(opened.reader.history, moves);
  });

  testWidgets('changing Trim margins discards old deck cards and new cards '
      'follow the choice', (tester) async {
    final opened = await open(tester);
    final reader = opened.reader;
    const target = BookTarget(fraction: 4 / 13, part: 4, progress: 0);
    Future<void> deck() async {
      reader.previews.start(target, width: 400);
      await settleReader(
        tester,
        () => reader.previews.deck.value?.front.page != null,
        reason: 'the deck did not draw its front card',
      );
    }

    await openSettings(tester);
    await deck();
    expect(
      imageAspect(reader.previews.deck.value!.front.page!.image),
      closeTo(aspectOf(opened.pdf.survey.cropOf(5)!), 0.01),
    );
    await toggle(tester);
    expect(reader.previews.deck.value, isNull);
    await deck();
    final full = await tester.runAsync(() => margins.render(5, 400));
    expect(
      imageAspect(reader.previews.deck.value!.front.page!.image),
      closeTo(full!.width / full.height, 0.01),
    );
    await toggle(tester);
    expect(reader.previews.deck.value, isNull);
    await deck();
    expect(
      imageAspect(reader.previews.deck.value!.front.page!.image),
      closeTo(aspectOf(opened.pdf.survey.cropOf(5)!), 0.01),
    );
    reader.previews.close();
  });

  testWidgets('a failed trim redraw keeps the readable page and offers a retry '
      'that applies the saved choice', (tester) async {
    final pdf = ControlledDraws(margins);
    final opened = await open(tester, source: pdf);
    final cropped = shownImage(tester);
    final place = opened.reader.visibleAddress;
    final moves = opened.reader.history;
    pdf.failNext = true;
    await openSettings(tester);
    await toggle(tester);
    expect(opened.reader.trimMargins, isFalse);
    Navigator.of(tester.element(find.byType(ReaderScreen))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(shownImage(tester), same(cropped));
    expect(find.textContaining('could not be drawn'), findsOneWidget);
    expect(find.text('Retry source page'), findsOneWidget);

    pdf.hold = true;
    await tester.tap(find.text('Retry source page'));
    await tester.pump();
    expect(pdf.pending, hasLength(1));
    expect(shownImage(tester), same(cropped));
    await finishReader(tester, pdf.complete(0));
    await settleReader(
      tester,
      () => shownImage(tester) != cropped,
      reason: 'retry did not replace the readable crop',
    );
    final full = await tester.runAsync(() => margins.render(5, 400));
    expect(
      imageAspect(shownImage(tester)),
      closeTo(full!.width / full.height, 0.01),
    );
    expect(find.textContaining('could not be drawn'), findsNothing);
    expect(find.text('Retry source page'), findsNothing);
    expect(opened.reader.visibleAddress, place);
    expect(opened.reader.history, moves);
  });

  testWidgets('a late trim redraw cannot replace the newer choice', (
    tester,
  ) async {
    final pdf = ControlledDraws(margins);
    await open(tester, source: pdf);
    final original = shownImage(tester);
    final crop = pdf.survey.cropOf(5)!;
    await openSettings(tester);
    pdf.hold = true;
    await toggle(tester);
    expect(pdf.pending, hasLength(1));
    await toggle(tester);
    expect(pdf.pending, hasLength(2));
    await finishReader(tester, pdf.complete(1));
    await settleReader(
      tester,
      () => shownImage(tester) != original,
      reason: 'the newest trim redraw did not finish first',
    );
    final newest = shownImage(tester);
    expect(imageAspect(newest), closeTo(aspectOf(crop), 0.01));
    await finishReader(tester, pdf.complete(0));
    await advance(tester, const Duration(milliseconds: 100));
    expect(shownImage(tester), same(newest));
    expect(find.text('Retry source page'), findsNothing);
  });

  testWidgets('word columns still drop running headers and folios with Trim '
      'margins off', (tester) async {
    final opened = await open(tester);
    final page = (await tester.runAsync(() => opened.pdf.reflowPage(5)))!;
    final settings = ColumnSettings(
      width: 360,
      fontSize: 20,
      screenHeight: 700,
    );
    final before = (await tester.runAsync(() => page.column(settings)))!;
    final reading = (await tester.runAsync(() => analyzedPage(opened.pdf, 5)))!;
    final running = headerAndFolio(5, lineTexts(reading)!);
    expect(running, hasLength(2));
    for (final line in running) {
      for (final word in wordsOf(reading.geometry, line)) {
        expect(before.pieceItems, isNot(contains(word)));
      }
    }
    await openSettings(tester);
    await toggle(tester);
    final after = (await tester.runAsync(() => page.column(settings)))!;
    expect(after.pieceItems, before.pieceItems);
    expect(after.pieces, before.pieces);
    expect(after.screenStarts, before.screenStarts);
  });

  testWidgets('Trim margins stays readable and tappable at the largest system '
      'text size', (tester) async {
    await open(tester, systemScale: 3.2);
    await openSettings(tester);
    expect(trim, findsOneWidget);
    await tester.ensureVisible(trim);
    expect(tester.takeException(), isNull);
    expect(tester.getSize(trim).height, greaterThanOrEqualTo(48));
    expect(
      tester
          .getSize(
            find.descendant(of: trim, matching: find.text('Trim margins')),
          )
          .width,
      lessThan(tester.getSize(trim).width),
    );
    await toggle(tester);
    expect(tester.widget<SwitchListTile>(trim).value, isFalse);
    expect(tester.takeException(), isNull);
  });
}
