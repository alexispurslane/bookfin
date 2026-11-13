// The Original view shows each PDF page cropped to its book crop (tb-valc).
// See docs/plans/pdf-word-image-reflow.md, "The Original view".
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bookfin/reader/book_crop.dart';
import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/pdf.dart';
import 'package:bookfin/reader/pdf_viewport.dart';
import 'package:bookfin/reader/survey_files.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart' as native;

import 'book_crop_test.dart' show SplicedBook, analyzedPage, bookOf;
import 'book_survey_test.dart' show UnreadSurvey;
import 'ocr_hop_test.dart' show runInWorker;
import 'pdf_viewport_test.dart' show drawn;
import 'running_lines_test.dart' show marginsBook;

/// The margins book, page for page, which records the width of each page
/// that it draws.
class WatchedBook extends SplicedBook {
  WatchedBook(PdfBook margins)
    : super([for (var page = 1; page <= 13; page++) (margins, page)]);

  /// Each page drawn, with the width that it was asked for, in order.
  final draws = <(int, double)>[];

  @override
  Future<PdfRaster> render(int sourcePage, double width) {
    draws.add((sourcePage, width));
    return super.render(sourcePage, width);
  }

  /// How many times source page [page] was drawn.
  int drawsOf(int page) => draws.where((draw) => draw.$1 == page).length;
}

/// Where ink lies in a picture of a page, in its pixels: its box, and the
/// median distance from the top of one line of ink to the top of the next.
typedef PageInk = ({Rect box, double pitch});

/// The ink of the [width] by [height] pixels [bytes], four bytes a pixel,
/// whose green channel is the second byte. [rows] limits the rows that
/// count.
PageInk inkOf(Uint8List bytes, int width, int height, {(int, int)? rows}) {
  final (from, to) = rows ?? (0, height);
  var left = width, top = height, right = 0, bottom = 0;
  final lineTops = <int>[];
  var inLine = false;
  for (var y = from; y < to; y++) {
    var inked = false;
    for (var x = 0; x < width; x++) {
      if (bytes[(y * width + x) * 4 + 1] < 128) {
        inked = true;
        if (x < left) left = x;
        if (x >= right) right = x + 1;
      }
    }
    if (inked) {
      if (y < top) top = y;
      bottom = y + 1;
      if (!inLine) lineTops.add(y);
    }
    inLine = inked;
  }
  final pitches = [
    for (var line = 1; line < lineTops.length; line++)
      lineTops[line] - lineTops[line - 1],
  ]..sort();
  return (
    box: Rect.fromLTRB(
      left.toDouble(),
      top.toDouble(),
      right.toDouble(),
      bottom.toDouble(),
    ),
    pitch: pitches.isEmpty ? 0 : pitches[pitches.length ~/ 2].toDouble(),
  );
}

/// The ink of [image].
Future<PageInk> imageInk(WidgetTester tester, ui.Image image) async {
  final data = (await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
  ))!;
  return inkOf(data.buffer.asUint8List(), image.width, image.height);
}

/// The page image that the viewport shows.
ui.Image shownImage(WidgetTester tester) => tester
    .widget<RawImage>(
      find.descendant(
        of: find.byType(PdfViewport),
        matching: find.byType(RawImage),
      ),
    )
    .image!;

/// Where the viewport draws its page image on the screen.
Rect shownRect(WidgetTester tester) => tester.getRect(
  find.descendant(
    of: find.byType(PdfViewport),
    matching: find.byType(RawImage),
  ),
);

/// [box], in the pixels of a picture of [size], as a box on the screen
/// where the picture fills [shown].
Rect onScreen(Rect box, Size size, Rect shown) => Rect.fromLTRB(
  shown.left + box.left / size.width * shown.width,
  shown.top + box.top / size.height * shown.height,
  shown.left + box.right / size.width * shown.width,
  shown.top + box.bottom / size.height * shown.height,
);

double aspectOf(PageBox box) => (box.right - box.left) / (box.bottom - box.top);

double imageAspect(ui.Image image) => image.width / image.height;

/// Lets time pass for [time], on the test's clock and on the real one.
Future<void> advance(WidgetTester tester, Duration time) async {
  const step = Duration(milliseconds: 10);
  for (var spent = Duration.zero; spent < time; spent += step) {
    await tester.runAsync(() => Future<void>.delayed(step));
    await tester.pump(step);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  native.Pdfrx.pdfiumModulePath = Platform.environment['PDFIUM_LIBRARY'];
  native.Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;

  late PdfBook margins;

  /// The survey of the margins book that a reopen reads: every page and
  /// the book profile.
  late KeptSurvey kept;

  setUpAll(() async {
    margins = await PdfRuntime.instance.open(
      marginsBook,
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

  /// The boxes of the running header and the folio of source page [page].
  List<PageBox> runningLinesOf(int page) {
    final surveyed = kept.pages[page - 1];
    return [
      for (final edge in surveyed.edges.edges)
        if (kept.profile!.templates.matches(page, edge)) edge.box,
    ];
  }

  /// The margins book, whose kept survey [store] reads.
  late WatchedBook book;
  late UnreadSurvey store;

  /// The turns that the viewport asked for.
  late List<bool> turns;
  DocumentNavigator? navigator;

  Future<void> show(WidgetTester tester, int page) async {
    tester.view
      ..physicalSize = const Size(1080, 2400)
      ..devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    // The reader's session starts the survey as the book opens.
    book.survey.start(store, from: page);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PdfViewport(
            book: book,
            fontSize: 20,
            initial: PdfAddress(page, 0),
            view: PdfPageView.original,
            onReady: (shown, _) => navigator = shown,
            onAddress: (_) {},
            onRefinedAddress: (_) {},
            onCancelRecognition: () {},
            onTap: () {},
            onTurn: turns.add,
          ),
        ),
      ),
    );
  }

  Finder original(int page) =>
      find.bySemanticsLabel('Original source page $page');

  setUp(() {
    book = WatchedBook(margins);
    store = UnreadSurvey();
    turns = [];
    navigator = null;
  });

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    if (!store.reading.isCompleted) store.reading.complete(null);
    // The survey runs on the test's clock, so its close needs both clocks.
    var closed = false;
    unawaited(book.survey.close().whenComplete(() => closed = true));
    while (!closed) {
      await advance(tester, const Duration(milliseconds: 10));
    }
  }

  group('the Original view shows each page cropped to its book crop', () {
    testWidgets('a body page shows only its content, without its margins, '
        'running header and folio, drawn at the screen\'s full width', (
      tester,
    ) async {
      store.reading.complete(kept);
      await show(tester, 5);
      await drawn(tester, shown: original(5));

      final crop = book.survey.cropOf(5)!;
      final image = shownImage(tester);
      expect(imageAspect(image), closeTo(aspectOf(crop), 0.01));
      expect(image.width, closeTo(1080, 2));
      final running = runningLinesOf(5);
      expect(running, hasLength(2), reason: 'Page 5 has a header and a folio.');
      for (final line in running) {
        expect(
          line.bottom <= crop.top || line.top >= crop.bottom,
          isTrue,
          reason: 'A running line lies outside the shown part.',
        );
      }

      // The shown picture is the crop of the printed page.
      final page = await tester.runAsync(() => margins.render(5, 1600));
      final scale = page!.width.toDouble();
      final printed = inkOf(
        page.bgra,
        page.width,
        page.height,
        rows: ((crop.top * scale).ceil(), (crop.bottom * scale).floor()),
      ).box;
      final shown = (await imageInk(tester, image)).box;
      final cropWidth = crop.right - crop.left;
      double across(double x) => crop.left + x / image.width * cropWidth;
      double down(double y) => crop.top + y / image.width * cropWidth;
      const tolerance = 0.004;
      expect(across(shown.left), closeTo(printed.left / scale, tolerance));
      expect(across(shown.right), closeTo(printed.right / scale, tolerance));
      expect(down(shown.top), closeTo(printed.top / scale, tolerance));
      expect(down(shown.bottom), closeTo(printed.bottom / scale, tolerance));
      await close(tester);
    });

    testWidgets('two body pages of one side show their text at the same size '
        'and place, larger than on the printed page', (tester) async {
      store.reading.complete(kept);
      await show(tester, 3);
      await drawn(tester, shown: original(3));
      final third = shownImage(tester);
      final thirdRect = shownRect(tester);
      final thirdInk = await imageInk(tester, third);
      await tester.runAsync(() => navigator!.display(PdfAddress(5, 0)));
      await drawn(tester, shown: original(5));
      final fifth = shownImage(tester);
      final fifthRect = shownRect(tester);
      final fifthInk = await imageInk(tester, fifth);

      Size size(ui.Image image) =>
          Size(image.width.toDouble(), image.height.toDouble());
      final a = onScreen(thirdInk.box, size(third), thirdRect);
      final b = onScreen(fifthInk.box, size(fifth), fifthRect);
      expect(fifthRect, thirdRect);
      expect(b.left, closeTo(a.left, 1));
      expect(b.top, closeTo(a.top, 1));
      final scale = thirdRect.width / third.width;
      expect(thirdInk.pitch, greaterThan(0));
      expect(fifthInk.pitch * scale, closeTo(thirdInk.pitch * scale, 1));

      // On the printed page, fitted to the same screen, the text is narrower.
      final page = (await tester.runAsync(() => margins.render(3, 1600)))!;
      final printed = inkOf(page.bgra, page.width, page.height).box;
      final area = tester.getRect(find.byType(PdfViewport));
      final fit = applyBoxFit(
        BoxFit.contain,
        Size(page.width.toDouble(), page.height.toDouble()),
        area.size,
      ).destination;
      final printedWidth = printed.width / page.width * fit.width;
      expect(a.width, greaterThan(printedWidth * 1.15));
      await close(tester);
    });

    testWidgets('a page with a wide table shows all of its table', (
      tester,
    ) async {
      store.reading.complete(kept);
      await show(tester, 10);
      await drawn(tester, shown: original(10));
      final crop = book.survey.cropOf(10)!;
      expect(imageAspect(shownImage(tester)), closeTo(aspectOf(crop), 0.01));

      // All ink between the header and the folio lies in the shown part.
      final running = runningLinesOf(10);
      expect(running, hasLength(2));
      final page = (await tester.runAsync(() => margins.render(10, 1600)))!;
      final scale = page.width.toDouble();
      final content = inkOf(
        page.bgra,
        page.width,
        page.height,
        rows: (
          (running.first.bottom * scale).ceil() + 1,
          (running.last.top * scale).floor() - 1,
        ),
      ).box;
      // Crops are kept as 32-bit floats.
      const rounding = 1e-4;
      expect(content.left / scale, greaterThanOrEqualTo(crop.left - rounding));
      expect(content.right / scale, lessThanOrEqualTo(crop.right + rounding));
      expect(content.top / scale, greaterThanOrEqualTo(crop.top - rounding));
      expect(content.bottom / scale, lessThanOrEqualTo(crop.bottom + rounding));
      final body = book.survey.cropOf(12)!;
      expect(crop.right - crop.left, greaterThan(body.right - body.left));
      await close(tester);
    });

    testWidgets('pinch zoom works on a cropped page up to 6 times, and a '
        'swipe on the zoomed page moves it instead of turning', (tester) async {
      store.reading.complete(kept);
      await show(tester, 3);
      await drawn(tester, shown: original(3));
      final crop = book.survey.cropOf(3)!;
      expect(imageAspect(shownImage(tester)), closeTo(aspectOf(crop), 0.01));
      Matrix4 zoom() => tester
          .widget<Transform>(
            find
                .descendant(
                  of: find.byType(InteractiveViewer),
                  matching: find.byType(Transform),
                )
                .first,
          )
          .transform;

      final middle = tester.getCenter(find.byType(PdfViewport));
      // Two fingers spread apart zoom the page in. Two pinches pass 6 times.
      for (var pinch = 0; pinch < 2; pinch++) {
        final first = await tester.startGesture(
          middle - const Offset(20, 0),
          pointer: 10 + pinch * 2,
        );
        final second = await tester.startGesture(
          middle + const Offset(20, 0),
          pointer: 11 + pinch * 2,
        );
        for (var step = 1; step <= 12; step++) {
          await first.moveBy(const Offset(-15, 0));
          await second.moveBy(const Offset(15, 0));
          await tester.pump();
        }
        await first.up();
        await second.up();
        await tester.pumpAndSettle();
        if (pinch == 0) expect(zoom().getMaxScaleOnAxis(), greaterThan(2));
      }
      expect(zoom().getMaxScaleOnAxis(), closeTo(6, 0.01));

      final before = zoom().getTranslation().x;
      await tester.dragFrom(middle, const Offset(-150, 0));
      await tester.pumpAndSettle();
      expect(turns, isEmpty);
      expect(zoom().getTranslation().x, lessThan(before - 50));
      expect(original(3), findsOneWidget);
      await close(tester);
    });
  });

  group('a page never changes its crop while it shows', () {
    testWidgets('an initial page starts drawing when the 300 ms crop wait '
        'expires, even if the kept survey is still unread', (tester) async {
      await show(tester, 3);
      await tester.pump(const Duration(milliseconds: 299));
      expect(book.drawsOf(3), 0);
      await tester.pump(const Duration(milliseconds: 1));
      expect(book.drawsOf(3), 1);
      expect(store.reading.isCompleted, isFalse);
      await drawn(tester, shown: original(3));
      expect(
        imageAspect(shownImage(tester)),
        closeTo(1 / kept.pages[2].height, 0.01),
      );
      await close(tester);
    });

    testWidgets('a page opened by a jump waits for a crop that arrives within '
        '300 ms, and shows cropped from its first frame', (tester) async {
      await show(tester, 3);
      await advance(tester, const Duration(milliseconds: 100));
      store.reading.complete(kept);
      await drawn(tester, shown: original(3));
      expect(
        imageAspect(shownImage(tester)),
        closeTo(aspectOf(book.survey.cropOf(3)!), 0.01),
      );
      expect(book.drawsOf(3), 1, reason: 'No uncropped page drew first.');
      await close(tester);
    });

    testWidgets('a page opened by a jump shows uncropped when its crop does '
        'not arrive within 300 ms, and keeps its look when the crop '
        'arrives', (tester) async {
      await show(tester, 3);
      await advance(tester, const Duration(milliseconds: 350));
      await drawn(tester, shown: original(3));
      final uncropped = shownImage(tester);
      expect(book.survey.cropOf(3), isNull);
      expect(imageAspect(uncropped), closeTo(1 / kept.pages[2].height, 0.01));

      store.reading.complete(kept);
      await advance(tester, const Duration(milliseconds: 100));
      expect(book.survey.cropOf(3), isNotNull);
      expect(shownImage(tester), same(uncropped));
      await close(tester);
    });

    testWidgets('a page turned to before its crop is known shows uncropped at '
        'once and keeps its look; the crop applies from the next page', (
      tester,
    ) async {
      await show(tester, 3);
      await advance(tester, const Duration(milliseconds: 350));
      await drawn(tester, shown: original(3));

      // The turn shows its page without waiting on the test's clock.
      unawaited(navigator!.move(true));
      await drawn(tester, shown: original(4));
      final fourth = shownImage(tester);
      expect(imageAspect(fourth), closeTo(1 / kept.pages[3].height, 0.01));

      store.reading.complete(kept);
      await advance(tester, const Duration(milliseconds: 50));
      expect(shownImage(tester), same(fourth));

      unawaited(navigator!.move(true));
      await drawn(tester, shown: original(5));
      expect(
        imageAspect(shownImage(tester)),
        closeTo(aspectOf(book.survey.cropOf(5)!), 0.01),
      );
      await close(tester);
    });
  });

  testWidgets('a deck card is cropped when its page\'s crop is known, and is '
      'drawn whole at once when it is not', (tester) async {
    await show(tester, 1);
    await advance(tester, const Duration(milliseconds: 350));
    await drawn(tester, shown: original(1));
    final whole = (await tester.runAsync(
      () => navigator!.preview(
        (part: 4, progress: 0),
        300,
        Completer<void>().future,
      ),
    ))!;
    expect(imageAspect(whole.image), closeTo(1 / kept.pages[4].height, 0.01));

    store.reading.complete(kept);
    await advance(tester, const Duration(milliseconds: 50));
    final card = (await tester.runAsync(
      () => navigator!.preview(
        (part: 4, progress: 0),
        300,
        Completer<void>().future,
      ),
    ))!;
    expect(
      imageAspect(card.image),
      closeTo(aspectOf(book.survey.cropOf(5)!), 0.01),
    );
    expect(card.image.width, closeTo(300, 2));
    whole.image.dispose();
    card.image.dispose();
    await close(tester);
  });
}
