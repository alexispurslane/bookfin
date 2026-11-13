// Behavior of the word view inside the PDF viewport: waiting for words and
// for text, places before and after the text arrives, turns across screens
// and source pages, and failures. See docs/plans/pdf-word-image-reflow.md,
// "The text under the images" and "Waiting, turns, the scrub deck and the
// scrub bar".
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bookfin/foundation/hop.dart';
import 'package:bookfin/foundation/theme.dart';
import 'package:bookfin/reader/column_layout.dart';
import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/ocr.dart';
import 'package:bookfin/reader/page_analysis.dart';
import 'package:bookfin/reader/page_geometry.dart';
import 'package:bookfin/reader/pdf.dart';
import 'package:bookfin/reader/pdf_text_view.dart';
import 'package:bookfin/reader/pdf_viewport.dart';
import 'package:bookfin/reader/pdf_word_view.dart';
import 'package:bookfin/reader/word_bands.dart';
import 'package:bookfin/reader/word_pages.dart';
import 'package:bookfin/reader/word_selection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart' as native;

import 'ocr_hop_test.dart' show runInWorker;
import 'page_analysis_test.dart' show footnotePage;
import 'page_geometry_test.dart' show hocrFixture, layoutFixture;
import 'word_pages_test.dart' show marginsBook, screenPieces;

/// A text supply for scanned pages whose recognized text arrives only when
/// [textArrives] completes. [layout] gives a page's words, and [read] its
/// recognized text and, for a page's words, their ranges of that text. It
/// shows recognition progress while a request for text waits, and logs
/// each request in [asked].
class HeldRecognition implements PdfTextSupply {
  HeldRecognition({required this.layout, required this.read});

  /// The supply of the Gibbon footnote page.
  factory HeldRecognition.gibbon() => HeldRecognition(
    layout: (_) async => pageGeometryFromLayout(layoutFixture('footnote-page')),
    read: (_, geometry) async {
      final recognized = decodeRecognizedPage(hocrFixture('footnote-page'));
      return (
        text: recognized.text,
        attachment: geometry == null
            ? null
            : attachText((geometry: geometry, words: recognized.words)),
      );
    },
  );

  final Future<PageGeometry?> Function(int page) layout;
  final Future<({PdfText text, TextAttachment? attachment})> Function(
    int page,
    PageGeometry? geometry,
  )
  read;
  final textArrives = Completer<void>();

  /// Whether recognition fails once [textArrives] completes.
  var failText = false;

  /// Whether the layout pass finds no words.
  var failLayout = false;
  Future<void>? layoutWait;

  final asked = <String>[];
  var _waiting = 0;
  @override
  final ValueNotifier<bool> recognizing = ValueNotifier(false);
  @override
  void bind(PdfTextLease lease) {}
  @override
  void cancel() {}
  @override
  Future<void> close() async {}

  @override
  Future<PageGeometry?> geometry(
    PdfBook book,
    int page,
    PdfText extracted, {
    bool background = false,
  }) async {
    asked.add('layout $page');
    await layoutWait;
    return failLayout ? null : layout(page);
  }

  Future<({PdfText text, TextAttachment? attachment})> _held(
    int page,
    PageGeometry? geometry,
  ) async {
    asked.add('text $page');
    _waiting++;
    recognizing.value = true;
    try {
      await textArrives.future;
      if (failText) {
        return (
          text: const PdfText(
            source: '',
            text: '',
            sourceOffsets: [],
            status: PdfTextStatus.failed,
            reason: 'The text of this page could not be recognized.',
          ),
          attachment: null,
        );
      }
      return await read(page, geometry);
    } finally {
      recognizing.value = --_waiting > 0;
    }
  }

  @override
  Future<PdfText> text(PdfBook book, int page, PdfText extracted) async =>
      (await _held(page, null)).text;

  @override
  Future<({PdfText text, TextAttachment? attachment})> attachedText(
    PdfBook book,
    int page,
    PdfText extracted,
    PageGeometry geometry,
  ) => _held(page, geometry);
}

/// [book] as another reader shows it: [layer] gives the text layer of each
/// page, and [textSupply] the rest. Without [layer], every page is a scan.
class CopiedPdf extends PdfBook {
  CopiedPdf(this.book, {this.layer, this.textSupply}) : super(hop: book.hop);
  final PdfBook book;
  final Future<PdfText> Function(int page)? layer;
  @override
  final PdfTextSupply? textSupply;
  Object? bandFailure;
  Future<void>? bandsWait;
  int waitingBands = 0;
  int finishedBands = 0;
  @override
  String get originalDigest => 'copy-${book.originalDigest}';
  @override
  String get identity => 'copy';
  @override
  String get engine => book.engine;
  @override
  String get policy => book.policy;
  @override
  String get format => 'pdf';
  @override
  int get pageCount => book.pageCount;
  @override
  bool accepts(ReaderAddress address) => book.accepts(address);
  @override
  ReaderAddress decodeAddress(Map<String, dynamic> value) =>
      book.decodeAddress(value);
  @override
  Future<void> dispose() async {}
  @override
  Future<PdfText> textLayer(int sourcePage) =>
      layer?.call(sourcePage) ??
      Future.value(
        const PdfText(
          source: '',
          text: '',
          sourceOffsets: [],
          status: PdfTextStatus.absent,
        ),
      );
  @override
  Future<PdfRaster> render(int sourcePage, double width) =>
      book.render(sourcePage, width);
  @override
  Future<ui.Image> renderPart(
    int sourcePage,
    int pixelsPerPageUnit,
    ui.Rect area,
  ) async {
    final waiting = bandsWait;
    if (waiting != null) waitingBands++;
    await waiting;
    if (bandFailure != null) throw bandFailure!;
    final image = await book.renderPart(sourcePage, pixelsPerPageUnit, area);
    finishedBands++;
    return image;
  }
}

class HeldWordPdf extends CopiedPdf {
  HeldWordPdf(super.book, {this.geometryWait}) : super(layer: book.textLayer);

  final Future<void> Function(int page)? geometryWait;
  final noGeometry = <int>{};

  @override
  Future<PageGeometry?> geometry(
    int sourcePage, {
    bool background = false,
  }) async {
    await geometryWait?.call(sourcePage);
    if (noGeometry.contains(sourcePage)) return null;
    return book.geometry(sourcePage, background: background);
  }

  @override
  Future<({PdfText text, TextAttachment? attachment})> attachedText(
    int sourcePage,
    PageGeometry geometry,
  ) => book.attachedText(sourcePage, geometry);
}

/// What a viewport reported to its owner.
class Reports {
  final places = <PdfAddress>[];
  DocumentNavigator? navigator;
}

/// The character where [screen] of [column] starts: the start of the range
/// of its first word that names text, or null when none does.
int? firstCharacter(
  ReflowColumn column,
  int screen,
  TextAttachment ranges,
  PageAnalysis analysis,
) {
  final first = column.lineStarts[column.screenStarts[screen]];
  final end = column.lineStarts[column.screenStarts[screen + 1]];
  for (var piece = first; piece < end; piece++) {
    for (var word = 0; word < analysis.wordRegions.length; word++) {
      final shown = column.region(piece) >= 0
          ? analysis.wordRegions[word] == column.region(piece)
          : word == column.word(piece);
      if (shown && ranges[word * 2] < ranges[word * 2 + 1]) {
        return ranges[word * 2];
      }
    }
  }
  return null;
}

Future<void> settle(
  WidgetTester tester,
  bool Function() holds,
  String what,
) async {
  final clock = Stopwatch()..start();
  while (!holds()) {
    if (clock.elapsed > const Duration(seconds: 20)) fail('Never: $what.');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 5));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  native.Pdfrx.pdfiumModulePath = Platform.environment['PDFIUM_LIBRARY'];
  native.Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;
  tearDownAll(() => PdfRuntime.instance.shutdown());

  Future<PdfBook> open(
    WidgetTester tester,
    String path, {
    PdfTextSupply? textSupply,
    IsolateHop? hop,
  }) async {
    final book = (await tester.runAsync(
      () async => PdfRuntime.instance.open(
        path,
        path.hashCode.toRadixString(16).padLeft(64, '0'),
        textSupply: textSupply,
        hop: hop ?? runInWorker,
      ),
    ))!;
    // A failed test closes its book too, so pdfium can shut down.
    addTearDown(() async {
      if (textSupply case final HeldRecognition held) {
        if (!held.textArrives.isCompleted) held.textArrives.complete();
      }
      await tester.pumpWidget(const SizedBox());
      var closed = false;
      unawaited(book.dispose().then((_) => closed = true));
      await settle(tester, () => closed, 'the PDF releases its native work');
    });
    return book;
  }

  /// Shows [book] in a reflowing viewport on a Pixel 8's screen, and
  /// returns what it reports.
  Future<Reports> show(
    WidgetTester tester,
    PdfBook book, {
    PdfAddress? initial,
    double fontSize = 40,
    Reports? reports,
    EdgeInsets padding = EdgeInsets.zero,
    PdfPageView view = PdfPageView.pageWords,
    double devicePixelRatio = 2.625,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = devicePixelRatio;
    addTearDown(tester.view.reset);
    final reported = reports ?? Reports();
    await tester.pumpWidget(
      MaterialApp(
        theme: bookfinTheme(Brightness.light),
        home: Scaffold(
          body: Padding(
            padding: padding,
            child: PdfViewport(
              book: book,
              fontSize: fontSize,
              initial: initial,
              view: view,
              onReady: (navigator, _) => reported.navigator = navigator,
              onAddress: reported.places.add,
              onRefinedAddress: reported.places.add,
              onCancelRecognition: () => book.textSupply?.cancel(),
              onTap: () {},
              onTurn: (forward) => unawaited(reported.navigator!.move(forward)),
            ),
          ),
        ),
      ),
    );
    return reported;
  }

  /// The word screen that shows, or null.
  WordScreen? shown(WidgetTester tester) {
    final view = find.byType(WordScreenView);
    if (view.evaluate().isEmpty) return null;
    tester
        .widget<PdfWordView>(find.byType(PdfWordView))
        .screens
        .checkInvariants();
    return tester.widget<WordScreenView>(view).screen.value;
  }

  bool progressLine() =>
      find.byType(LinearProgressIndicator).evaluate().isNotEmpty;

  /// Waits until screen [screen] of source page [page] shows.
  Future<WordScreen> showsScreen(
    WidgetTester tester,
    int page,
    int screen,
  ) async {
    await settle(tester, () {
      final words = shown(tester);
      return words != null && words.page == page && words.screen == screen;
    }, 'screen $screen of page $page shows');
    return shown(tester)!;
  }

  /// The reflow page of [page] of [book] with its attached text.
  Future<(ReflowPage, AttachedText)> attached(
    WidgetTester tester,
    PdfBook book,
    int page,
  ) async => (await tester.runAsync(() async {
    final reflow = (await book.reflowPage(page))!;
    return (reflow, await reflow.attachedText());
  }))!;

  /// Unmounts the viewport, which frees its band images.
  Future<void> close(WidgetTester tester, PdfBook book) =>
      tester.pumpWidget(const SizedBox());

  Completer<void> hold() {
    final arrives = Completer<void>();
    addTearDown(() {
      if (!arrives.isCompleted) arrives.complete();
    });
    return arrives;
  }

  testWidgets('a source-page turn keeps the readable word screen until '
      'the replacement bands arrive without showing Original', (tester) async {
    final born = await open(tester, marginsBook);
    final book = HeldWordPdf(born);
    final reports = await show(tester, book, initial: PdfAddress(3, 0));
    final before = await showsScreen(tester, 3, 0);
    final place = reports.places.last;
    final bandsArrive = hold();
    book.bandsWait = bandsArrive.future;

    unawaited(reports.navigator!.move(false));
    await settle(
      tester,
      () => book.waitingBands > 0,
      'the previous page waits',
    );

    expect(shown(tester), same(before));
    expect(find.bySemanticsLabel('Original source page 2'), findsNothing);
    expect(reports.places.last, same(place));
    final screens = tester
        .widget<PdfWordView>(find.byType(PdfWordView))
        .screens;
    expect(screens.showing.value, isFalse);
    screens.checkInvariants();

    bandsArrive.complete();
    await settle(tester, () => shown(tester)?.page == 2, 'page two shows');
    expect(reports.places.last.sourcePage, 2);
    await close(tester, book);
  });

  testWidgets('returning to a cached column keeps the current word screen '
      'while the evicted pixels render again', (tester) async {
    final born = await open(tester, marginsBook);
    final book = HeldWordPdf(born);
    final reports = await show(tester, book, initial: PdfAddress(3, 0));
    final third = await showsScreen(tester, 3, 0);
    unawaited(reports.navigator!.move(false));
    await settle(tester, () => shown(tester)?.page == 2, 'page two shows');
    final before = shown(tester)!;
    final place = reports.places.last;
    final bandsArrive = hold();
    book.bandsWait = bandsArrive.future;

    unawaited(reports.navigator!.move(true));
    await settle(tester, () => book.waitingBands > 0, 'cached page bands wait');

    expect(shown(tester), same(before));
    expect(find.bySemanticsLabel('Original source page 3'), findsNothing);
    expect(reports.places.last, same(place));
    bandsArrive.complete();
    final returned = await showsScreen(tester, 3, 0);
    expect(returned.column, same(third.column));
    expect(reports.places.last.sourcePage, 3);
    await close(tester, book);
  });

  testWidgets('an abandoned screen cannot replace the readable screen while '
      'another source page still waits for geometry', (tester) async {
    final born = await open(tester, marginsBook);
    final geometryArrives = hold();
    final book = HeldWordPdf(
      born,
      geometryWait: (page) async {
        if (page == 2) await geometryArrives.future;
      },
    );
    final reports = await show(tester, book, initial: PdfAddress(3, 0));
    await showsScreen(tester, 3, 0);
    final bandsArrive = hold();
    book.bandsWait = bandsArrive.future;
    unawaited(reports.navigator!.move(true));
    final before = await showsScreen(tester, 3, 1);
    await settle(tester, () => book.waitingBands > 0, 'the screen ahead waits');
    unawaited(reports.navigator!.move(true));
    await tester.pump();
    final screens = tester
        .widget<PdfWordView>(find.byType(PdfWordView))
        .screens;
    final place = reports.places.last;

    unawaited(reports.navigator!.display(PdfAddress(2, 0)));
    await tester.pump();
    final finished = book.finishedBands;
    final pending = book.waitingBands;
    bandsArrive.complete();
    await settle(
      tester,
      () => book.finishedBands >= finished + pending,
      'the abandoned bands finish',
    );
    await tester.pump();

    final afterAbandoned = screens.screen.value;
    final visibleAfterAbandoned = shown(tester);
    final placeAfterAbandoned = reports.places.last;
    screens.checkInvariants();
    geometryArrives.complete();
    await showsScreen(tester, 2, 0);
    expect(afterAbandoned, same(before));
    expect(visibleAfterAbandoned, same(before));
    expect(placeAfterAbandoned, same(place));
    await close(tester, book);
  });

  testWidgets('a size change while another source page is pending keeps '
      'the readable page until that target is ready at the new size', (
    tester,
  ) async {
    final born = await open(tester, marginsBook);
    final book = HeldWordPdf(born);
    final reports = await show(tester, book, initial: PdfAddress(3, 0));
    final before = await showsScreen(tester, 3, 0);
    final place = reports.places.last;
    final bandsArrive = hold();
    book.bandsWait = bandsArrive.future;
    unawaited(reports.navigator!.move(false));
    await settle(tester, () => book.waitingBands > 0, 'page two bands wait');
    final waiting = book.waitingBands;

    await show(tester, book, reports: reports, fontSize: 30);
    await settle(
      tester,
      () => book.waitingBands > waiting,
      'new size bands wait',
    );

    expect(shown(tester), same(before));
    expect(reports.places.last, same(place));
    expect(find.bySemanticsLabel('Original source page 2'), findsNothing);
    bandsArrive.complete();
    await settle(
      tester,
      () => shown(tester)?.page == 2 && shown(tester)?.settings.fontSize == 30,
      'page two shows at size thirty',
    );
    final after = shown(tester)!;
    expect(after.screen, after.column.column.screenCount - 1);
    expect(reports.places.last.sourcePage, 2);
    await close(tester, book);
  });

  testWidgets('rapid source-page direction changes never show the abandoned '
      'page or Original when its held bands finish', (tester) async {
    final born = await open(tester, marginsBook);
    final book = HeldWordPdf(born);
    final reports = await show(tester, book, initial: PdfAddress(3, 0));
    await showsScreen(tester, 3, 0);
    final screens = tester
        .widget<PdfWordView>(find.byType(PdfWordView))
        .screens;
    final bandsArrive = hold();
    book.bandsWait = bandsArrive.future;
    final reported = reports.places.length;
    final pages = <int>[];
    void record() => pages.add(screens.screen.value!.page);
    screens.screen.addListener(record);
    addTearDown(() => screens.screen.removeListener(record));

    for (var turn = 0; turn < 2; turn++) {
      final before = shown(tester)!;
      final waiting = book.waitingBands;
      unawaited(reports.navigator!.move(false));
      await settle(tester, () => book.waitingBands > waiting, 'page two waits');
      expect(shown(tester), same(before));
      expect(find.bySemanticsLabel('Original source page 2'), findsNothing);
      var returned = false;
      unawaited(reports.navigator!.move(true).then((_) => returned = true));
      await settle(tester, () => returned, 'the forward turn returns');
      expect(shown(tester)!.page, 3);
      expect(screens.showing.value, isTrue);
    }

    final finished = book.finishedBands;
    final pending = book.waitingBands;
    bandsArrive.complete();
    await settle(
      tester,
      () => book.finishedBands >= finished + pending,
      'all abandoned renders finish',
    );
    expect(pages, isNotEmpty);
    expect(pages, everyElement(3));
    expect(
      reports.places.skip(reported).map((place) => place.sourcePage),
      everyElement(3),
    );
    expect(shown(tester)!.page, 3);
    screens.checkInvariants();
    screens.screen.removeListener(record);
    await close(tester, book);
  });

  testWidgets('a true geometry fallback discards the old word screen so '
      'opening another page cannot resurrect it', (tester) async {
    final born = await open(tester, marginsBook);
    final book = HeldWordPdf(born)..noGeometry.add(2);
    final reports = await show(tester, book, initial: PdfAddress(3, 0));
    final before = await showsScreen(tester, 3, 0);
    unawaited(reports.navigator!.move(false));
    await settle(
      tester,
      () => find.byType(PdfTextView).evaluate().isNotEmpty,
      'page two falls back to text',
    );
    expect(find.byType(WordScreenView), findsNothing);
    expect(reports.places.last.sourcePage, 2);

    final bandsArrive = hold();
    book.bandsWait = bandsArrive.future;
    unawaited(reports.navigator!.display(PdfAddress(4, 0)));
    await settle(tester, () => book.waitingBands > 0, 'page four bands wait');
    final resurrected = shown(tester);
    bandsArrive.complete();
    await showsScreen(tester, 4, 0);

    expect(resurrected, isNull);
    expect(before.bands.every((band) => band.image.debugDisposed), isTrue);
    await close(tester, book);
  });

  testWidgets('touching retained words does not mark an unseen target page '
      'as touched or discard its requested place', (tester) async {
    final born = await open(tester, marginsBook);
    final (_, read) = await attached(tester, born, 2);
    final geometryArrives = hold();
    final supply = HeldRecognition(
      layout: (page) async {
        if (page == 2) await geometryArrives.future;
        return born.geometry(page);
      },
      read: (page, geometry) async => geometry == null
          ? (text: await born.text(page), attachment: null)
          : born.attachedText(page, geometry),
    )..textArrives.complete();
    final book = CopiedPdf(born, textSupply: supply);
    final target = book.addressFor(
      2,
      read.text,
      read.text.source.length * 2 ~/ 3,
    );
    final reports = await show(tester, book, initial: PdfAddress(3, 0));
    final before = await showsScreen(tester, 3, 0);
    unawaited(reports.navigator!.display(target));
    await tester.pump();
    expect(shown(tester), same(before));
    await tester.tap(find.byType(WordScreenView));
    geometryArrives.complete();
    final screens = tester
        .widget<PdfWordView>(find.byType(PdfWordView))
        .screens;
    await settle(tester, () => screens.showing.value, 'the target words show');
    final after = shown(tester)!;
    final (reflow, attachedText) = await attached(tester, book, 2);
    final holding = after.column.column.screenAt(
      target.character,
      attachedText.attachment!,
      reflow.analysis,
    );
    expect(holding, greaterThan(0));
    expect(after.page, 2);
    expect(after.screen, holding);
    await close(tester, book);
  });

  testWidgets('an operational render failure replaces retained words with '
      'the target page text', (tester) async {
    final born = await open(tester, marginsBook);
    final book = HeldWordPdf(born);
    final reports = await show(tester, book, initial: PdfAddress(3, 0));
    await showsScreen(tester, 3, 0);
    book.bandFailure = Exception('The target band could not be drawn.');
    unawaited(reports.navigator!.move(false));
    await settle(
      tester,
      () => find.byType(PdfTextView).evaluate().isNotEmpty,
      'page two falls back to text',
    );
    expect(find.byType(WordScreenView), findsNothing);
    expect(reports.places.last.sourcePage, 2);
    await close(tester, book);
  });

  testWidgets('a target page whose own content does not reflow replaces '
      'retained words with Original', (tester) async {
    final born = await open(tester, marginsBook);
    final supply = HeldRecognition(
      layout: born.geometry,
      read: (page, geometry) async => page == 2
          ? (
              text: const PdfText(
                source: '',
                text: '',
                sourceOffsets: [],
                status: PdfTextStatus.absent,
              ),
              attachment: null,
            )
          : geometry == null
          ? (text: await born.text(page), attachment: null)
          : born.attachedText(page, geometry),
    )..textArrives.complete();
    final book = CopiedPdf(born, textSupply: supply);
    final reports = await show(tester, book, initial: PdfAddress(3, 0));
    final before = await showsScreen(tester, 3, 0);
    unawaited(reports.navigator!.move(false));
    await settle(
      tester,
      () =>
          find.bySemanticsLabel('Original source page 2').evaluate().isNotEmpty,
      'the target content shows as printed',
    );
    expect(find.byType(WordScreenView), findsNothing);
    expect(progressLine(), isFalse);
    expect(before.bands.every((band) => band.image.debugDisposed), isTrue);
    expect(reports.places.last.sourcePage, 2);
    await close(tester, book);
  });

  testWidgets('switching out of word view releases its pixels and switching '
      'back waits on Original until new words are ready', (tester) async {
    final born = await open(tester, marginsBook);
    final book = HeldWordPdf(born);
    final reports = await show(tester, book, initial: PdfAddress(3, 0));
    final before = await showsScreen(tester, 3, 0);
    await show(tester, book, reports: reports, view: PdfPageView.original);
    await settle(
      tester,
      () =>
          find.bySemanticsLabel('Original source page 3').evaluate().isNotEmpty,
      'the selected Original view shows',
    );
    expect(before.bands.every((band) => band.image.debugDisposed), isTrue);
    final bandsArrive = hold();
    book.bandsWait = bandsArrive.future;
    await show(tester, book, reports: reports);
    await settle(tester, () => book.waitingBands > 0, 'reopened words wait');
    expect(shown(tester), isNull);
    expect(find.bySemanticsLabel('Original source page 3'), findsOneWidget);
    bandsArrive.complete();
    final after = await showsScreen(tester, 3, 0);
    expect(after.column, isNot(same(before.column)));
    await close(tester, book);
  });

  testWidgets('reopening a viewport reuses page analysis but not word pixels '
      'and keeps its saved place while the first screen renders', (
    tester,
  ) async {
    final born = await open(tester, marginsBook);
    final book = HeldWordPdf(born);
    final reports = await show(tester, book, initial: PdfAddress(3, 0));
    await showsScreen(tester, 3, 0);
    unawaited(reports.navigator!.move(true));
    final before = await showsScreen(tester, 3, 1);
    final place = reports.places.last;
    final reflow = (await tester.runAsync(() => book.reflowPage(3)))!;
    await close(tester, book);
    expect(before.bands.every((band) => band.image.debugDisposed), isTrue);
    final bandsArrive = hold();
    book.bandsWait = bandsArrive.future;
    final reopened = await show(tester, book, initial: place);
    await settle(tester, () => book.waitingBands > 0, 'the first screen waits');
    await settle(
      tester,
      () =>
          find.bySemanticsLabel('Original source page 3').evaluate().isNotEmpty,
      'the cold-open Original render arrives',
    );
    expect(shown(tester), isNull);
    expect(reopened.places, isEmpty);
    expect(find.bySemanticsLabel('Original source page 3'), findsOneWidget);
    bandsArrive.complete();
    final after = await showsScreen(tester, 3, 1);
    final reused = (await tester.runAsync(() => book.reflowPage(3)))!;
    expect(reused.analysis, same(reflow.analysis));
    expect(after.column, isNot(same(before.column)));
    expect(reopened.places.last.character, place.character);
    await close(tester, book);
  });

  testWidgets('on a scanned page the first word screen shows before '
      'recognition ends, and the progress line stays over it until the text '
      'attaches, with no change of screen', (tester) async {
    final supply = HeldRecognition.gibbon();
    final book = await open(tester, footnotePage, textSupply: supply);
    await show(tester, book);
    final first = await showsScreen(tester, 1, 0);
    expect(supply.textArrives.isCompleted, isFalse);
    expect(progressLine(), isTrue, reason: 'The text is still on its way.');

    supply.textArrives.complete();
    await settle(tester, () => !progressLine(), 'the progress line goes');
    final after = shown(tester)!;
    expect((after.page, after.screen), (1, 0));
    expect(after.column, same(first.column));
    await close(tester, book);
  });

  testWidgets('before the text arrives, a saved place inside a scanned page '
      'opens its first screen and stays saved; when the text attaches and '
      'the person did not move, the screen that holds the place shows', (
    tester,
  ) async {
    final supply = HeldRecognition.gibbon();
    final book = await open(tester, footnotePage, textSupply: supply);
    final text = decodeRecognizedPage(hocrFixture('footnote-page')).text;
    final saved = book.addressFor(1, text, text.source.indexOf('Alemanni'));
    final reports = await show(tester, book, initial: saved);
    await showsScreen(tester, 1, 0);
    expect(
      reports.places.map((place) => place.character),
      everyElement(saved.character),
      reason: 'The saved place is kept, not replaced by the page.',
    );

    supply.textArrives.complete();
    final (reflow, read) = await attached(tester, book, 1);
    final column = shown(tester)!.column.column;
    final holding = column.screenAt(
      saved.character,
      read.attachment!,
      reflow.analysis,
    );
    expect(holding, greaterThan(0));
    await showsScreen(tester, 1, holding);
    final place = reports.places.last;
    expect(place.sourcePage, 1);
    expect(place.representation, saved.representation);
    expect(
      place.character,
      firstCharacter(column, holding, read.attachment!, reflow.analysis),
    );
    await close(tester, book);
  });

  testWidgets('a turn before the text arrives saves the page itself, and the '
      'text then leaves the shown screen in place and names its first word', (
    tester,
  ) async {
    final supply = HeldRecognition.gibbon();
    final book = await open(tester, footnotePage, textSupply: supply);
    final text = decodeRecognizedPage(hocrFixture('footnote-page')).text;
    final saved = book.addressFor(1, text, text.source.indexOf('Alemanni'));
    final reports = await show(tester, book, initial: saved);
    await showsScreen(tester, 1, 0);

    unawaited(reports.navigator!.move(true));
    await showsScreen(tester, 1, 1);
    expect(reports.places.last.character, 0);

    supply.textArrives.complete();
    await settle(tester, () => !progressLine(), 'the progress line goes');
    final (reflow, read) = await attached(tester, book, 1);
    await settle(
      tester,
      () => reports.places.last.character > 0,
      'the shown screen names its first word',
    );
    final words = shown(tester)!;
    expect(words.screen, 1);
    expect(
      reports.places.last.character,
      firstCharacter(words.column.column, 1, read.attachment!, reflow.analysis),
    );
    await close(tester, book);
  });

  testWidgets('a touch while the page waits for word geometry prevents '
      'a later jump to the saved character', (tester) async {
    final layoutArrives = Completer<void>();
    final supply = HeldRecognition.gibbon()..layoutWait = layoutArrives.future;
    addTearDown(() {
      if (!layoutArrives.isCompleted) layoutArrives.complete();
    });
    final book = await open(tester, footnotePage, textSupply: supply);
    final text = decodeRecognizedPage(hocrFixture('footnote-page')).text;
    final saved = book.addressFor(1, text, text.source.indexOf('Alemanni'));
    final reports = await show(tester, book, initial: saved);
    await settle(
      tester,
      () => supply.asked.contains('layout 1'),
      'layout starts',
    );
    await tester.tap(find.byType(PdfViewport));
    layoutArrives.complete();
    await showsScreen(tester, 1, 0);
    expect(
      reports.places.map((place) => place.character),
      everyElement(saved.character),
    );
    supply.textArrives.complete();
    await settle(tester, () => !progressLine(), 'text attaches');
    final (_, read) = await attached(tester, book, 1);
    expect(read.text.status, PdfTextStatus.candidate);
    await settle(
      tester,
      () => reports.places.last.character != saved.character,
      'the shown screen reports its attached character',
    );
    expect(shown(tester)!.screen, 0);
    await close(tester, book);
  });

  testWidgets('a touch before geometry arrives prevents a saved-place jump '
      'when recognized text is already cached', (tester) async {
    final layoutArrives = Completer<void>();
    final supply = HeldRecognition.gibbon()
      ..layoutWait = layoutArrives.future
      ..textArrives.complete();
    addTearDown(() {
      if (!layoutArrives.isCompleted) layoutArrives.complete();
    });
    final book = await open(tester, footnotePage, textSupply: supply);
    final text = decodeRecognizedPage(hocrFixture('footnote-page')).text;
    await show(
      tester,
      book,
      initial: book.addressFor(1, text, text.source.indexOf('Alemanni')),
    );
    await settle(
      tester,
      () => supply.asked.contains('layout 1'),
      'layout starts',
    );
    await tester.tap(find.byType(PdfViewport));
    layoutArrives.complete();
    await settle(tester, () => shown(tester) != null, 'the first screen shows');
    expect(shown(tester)!.screen, 0);
    await close(tester, book);
  });

  testWidgets('text arriving during a pending turn reports the screen '
      'still shown, not the requested screen', (tester) async {
    final supply = HeldRecognition.gibbon();
    final born = await open(tester, footnotePage);
    addTearDown(() {
      if (!supply.textArrives.isCompleted) supply.textArrives.complete();
    });
    final book = CopiedPdf(born, textSupply: supply);
    final reports = await show(tester, book);
    await showsScreen(tester, 1, 0);
    unawaited(reports.navigator!.move(true));
    final before = await showsScreen(tester, 1, 1);
    final bandsArrive = Completer<void>();
    addTearDown(() {
      if (!bandsArrive.isCompleted) bandsArrive.complete();
    });
    book.bandsWait = bandsArrive.future;
    unawaited(reports.navigator!.move(true));
    await tester.pump();
    supply.textArrives.complete();
    await settle(tester, () => !progressLine(), 'the text attaches');
    final (reflow, read) = await attached(tester, book, 1);
    expect(shown(tester)!.screen, 1);
    expect(
      reports.places.last.character,
      firstCharacter(
        before.column.column,
        1,
        read.attachment!,
        reflow.analysis,
      ),
    );
    bandsArrive.complete();
    await showsScreen(tester, 1, 2);
    expect(
      reports.places.last.character,
      firstCharacter(
        before.column.column,
        2,
        read.attachment!,
        reflow.analysis,
      ),
    );
    await close(tester, book);
  });

  for (final change in ['turn', 'size change']) {
    testWidgets('text arriving during a pending $change enables selection '
        'and paragraph reading on the screen still shown', (tester) async {
      final semantics = tester.ensureSemantics();
      final supply = HeldRecognition.gibbon();
      final born = await open(tester, footnotePage);
      final bandsArrive = Completer<void>();
      addTearDown(() {
        if (!supply.textArrives.isCompleted) supply.textArrives.complete();
        if (!bandsArrive.isCompleted) bandsArrive.complete();
      });
      final book = CopiedPdf(born, textSupply: supply);
      final reports = await show(tester, book);
      await showsScreen(tester, 1, 0);
      book.bandsWait = bandsArrive.future;
      unawaited(reports.navigator!.move(true));
      final before = await showsScreen(tester, 1, 1);
      await settle(tester, () => book.waitingBands > 0, 'the next bands wait');
      if (change == 'turn') {
        unawaited(reports.navigator!.move(true));
        await tester.pump();
      } else {
        final waiting = book.waitingBands;
        await show(tester, book, fontSize: 14, reports: reports);
        await settle(
          tester,
          () => book.waitingBands > waiting,
          'the resized bands wait',
        );
      }
      expect(shown(tester), same(before));
      supply.textArrives.complete();
      await settle(tester, () => !progressLine(), 'the text attaches');
      final (_, read) = await attached(tester, book, 1);
      final screens = tester
          .widget<PdfWordView>(find.byType(PdfWordView))
          .screens;
      expect(shown(tester), same(before));
      expect(screens.text.value, isNotNull);
      final text = screens.text.value!;
      expect(text.column, same(before.column.column));
      expect(text.screen, before.screen);
      expect(text.page.attached.text, same(read.text));
      expect(text.page.attached.attachment, same(read.attachment));

      final column = before.column.column;
      final piece = screenPieces(column, before.screen).firstWhere((piece) {
        final word = column.word(piece);
        if (word < 0) return false;
        final first = read.attachment![word * 2];
        final end = read.attachment![word * 2 + 1];
        return RegExp(r'^[A-Za-z]+$')
            .hasMatch(read.text.source.substring(first, end));
      });
      final word = column.word(piece);
      final first = read.attachment![word * 2];
      final end = read.attachment![word * 2 + 1];
      final expected = read.text.source.substring(first, end);
      final rect = column
          .target(piece)
          .shift(Offset(0, -column.screenTop(before.screen)));
      expect(text.rectsFor(first, end), [rect]);
      final labels = <String>[];
      void readLabels(SemanticsNode node) {
        final label = node.getSemanticsData().label;
        if (label.isNotEmpty) labels.add(label);
        node.visitChildren((child) {
          readLabels(child);
          return true;
        });
      }

      readLabels(tester.getSemantics(find.byType(WordSelectable)));
      expect(labels, isNotEmpty);
      expect(labels.join(' '), contains(expected));
      expect(labels.every(read.text.text.contains), isTrue);

      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.longPressAt(
        rect.center + tester.getTopLeft(find.byType(WordScreenView)),
      );
      await tester.pumpAndSettle();
      final selection = tester
          .renderObject<RenderWordSelectable>(find.byType(WordSelectable))
          .selection;
      expect(selection.text, expected);
      expect(selection.rects, [rect]);
      expect(find.text('Copy'), findsOneWidget);
      await tester.tap(find.text('Copy'));
      await tester.pump();
      expect(copied, expected);
      screens.checkInvariants();
      bandsArrive.complete();
      await settle(
        tester,
        () => !identical(shown(tester), before),
        'the requested screen shows',
      );
      screens.checkInvariants();
      semantics.dispose();
      await close(tester, book);
    });
  }

  testWidgets('word images start at whole device pixels when the reader '
      'has a fractional position inside its parent', (tester) async {
    final book = await open(tester, marginsBook);
    await show(
      tester,
      book,
      initial: PdfAddress(3, 0),
      padding: const EdgeInsets.only(left: .13, top: .27),
    );
    await showsScreen(tester, 3, 0);
    final origin = tester.getTopLeft(find.byType(WordScreenView)) * 2.625;
    expect(origin.dx, closeTo(origin.dx.roundToDouble(), 1e-7));
    expect(origin.dy, closeTo(origin.dy.roundToDouble(), 1e-7));
    await close(tester, book);
  });

  testWidgets('retained and replacement pixels each stay aligned to the '
      'device pixel ratio that rendered them', (tester) async {
    final born = await open(tester, marginsBook);
    final book = HeldWordPdf(born);
    const padding = EdgeInsets.only(left: .13, top: .27);
    final reports = await show(
      tester,
      book,
      initial: PdfAddress(3, 0),
      padding: padding,
    );
    final before = await showsScreen(tester, 3, 0);
    final bandsArrive = hold();
    book.bandsWait = bandsArrive.future;
    await show(
      tester,
      book,
      reports: reports,
      padding: padding,
      devicePixelRatio: 3,
    );
    await settle(tester, () => book.waitingBands > 0, 'new-ratio bands wait');
    final retainedOrigin =
        tester.getTopLeft(find.byType(WordScreenView)) * 2.625;
    expect(shown(tester), same(before));
    expect(retainedOrigin.dx, closeTo(retainedOrigin.dx.roundToDouble(), 1e-7));
    expect(retainedOrigin.dy, closeTo(retainedOrigin.dy.roundToDouble(), 1e-7));
    bandsArrive.complete();
    await settle(
      tester,
      () => shown(tester)?.settings.devicePixelRatio == 3,
      'new-ratio words show',
    );
    final replacedOrigin = tester.getTopLeft(find.byType(WordScreenView)) * 3;
    expect(replacedOrigin.dx, closeTo(replacedOrigin.dx.roundToDouble(), 1e-7));
    expect(replacedOrigin.dy, closeTo(replacedOrigin.dy.roundToDouble(), 1e-7));
    await close(tester, book);
  });

  testWidgets('the place of a word screen is its first word, and the book '
      'reopened at that place shows the same screen', (tester) async {
    final book = await open(tester, marginsBook);
    final reports = await show(tester, book, initial: PdfAddress(3, 0));
    await showsScreen(tester, 3, 0);
    unawaited(reports.navigator!.move(true));
    final turned = await showsScreen(tester, 3, 1);
    final (reflow, read) = await attached(tester, book, 3);
    await settle(
      tester,
      () => reports.places.last.character > 0,
      'the place names the screen\'s first word',
    );
    final place = reports.places.last;
    expect(
      place.character,
      firstCharacter(
        turned.column.column,
        1,
        read.attachment!,
        reflow.analysis,
      ),
    );

    await tester.pumpWidget(const SizedBox());
    final reopened = await show(tester, book, initial: place);
    await showsScreen(tester, 3, 1);
    await settle(
      tester,
      () => reopened.places.isNotEmpty,
      'the reopened page reports its place',
    );
    expect(reopened.places.last.character, place.character);
    await close(tester, book);
  });

  testWidgets('a place saved in the text view opens the word view on the '
      'screen that holds it, and a word screen\'s place opens the text view '
      'at that character', (tester) async {
    final book = await open(tester, marginsBook);
    final (reflow, read) = await attached(tester, book, 3);
    final source = read.text.source;
    // The text view names the character at the top of its viewport, which
    // can be inside a word.
    final inText = book.addressFor(3, read.text, source.length * 2 ~/ 3 + 1);
    final reports = await show(tester, book, initial: inText);
    await settle(tester, () => shown(tester) != null, 'the words show');
    final column = shown(tester)!.column.column;
    final holding = column.screenAt(
      inText.character,
      read.attachment!,
      reflow.analysis,
    );
    expect(holding, greaterThan(0));
    await showsScreen(tester, 3, holding);
    final inWords = reports.places.last;
    expect(inWords.character, lessThanOrEqualTo(inText.character));

    await tester.pumpWidget(const SizedBox());
    // A copy whose pages have no word geometry shows the text view.
    final asText = CopiedPdf(book, layer: book.textLayer);
    final textReports = await show(tester, asText, initial: inWords);
    await settle(
      tester,
      () => textReports.places.isNotEmpty,
      'the text view reports its place',
    );
    expect(find.byType(WordScreenView), findsNothing);
    expect(textReports.places.first.character, inWords.character);
    expect(
      find.text('The saved place does not match the text of this page.'),
      findsNothing,
    );
    await close(tester, book);
  });

  testWidgets('a turn past a page\'s last screen shows the next page\'s '
      'first screen, and a turn back from a first screen shows the previous '
      'page\'s last screen', (tester) async {
    final book = await open(tester, marginsBook);
    final reports = await show(tester, book, initial: PdfAddress(3, 0));
    await showsScreen(tester, 3, 0);

    unawaited(reports.navigator!.move(false));
    await settle(
      tester,
      () => shown(tester)?.page == 2,
      'the previous page shows',
    );
    final previous = shown(tester)!;
    expect(previous.screen, previous.column.column.screenCount - 1);
    expect(previous.screen, greaterThan(0));

    unawaited(reports.navigator!.move(true));
    final third = await showsScreen(tester, 3, 0);
    final last = third.column.column.screenCount - 1;
    for (var screen = 1; screen <= last; screen++) {
      unawaited(reports.navigator!.move(true));
      await showsScreen(tester, 3, screen);
    }
    unawaited(reports.navigator!.move(true));
    await showsScreen(tester, 4, 0);
    expect(reports.places.last.sourcePage, 4);
    await close(tester, book);
  });

  testWidgets('a vertical drag on a word screen changes nothing', (
    tester,
  ) async {
    final book = await open(tester, marginsBook);
    final reports = await show(tester, book, initial: PdfAddress(3, 0));
    await showsScreen(tester, 3, 0);
    unawaited(reports.navigator!.move(true));
    await showsScreen(tester, 3, 1);
    await settle(tester, () => reports.places.last.character > 0, 'placed');
    final before = reports.places.length;

    await tester.drag(find.byType(WordScreenView), const Offset(0, -400));
    await tester.drag(find.byType(WordScreenView), const Offset(0, 400));
    for (var frame = 0; frame < 20; frame++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }
    expect((shown(tester)!.page, shown(tester)!.screen), (3, 1));
    expect(reports.places, hasLength(before));
    await close(tester, book);
  });

  testWidgets('a text size step keeps the shown first word on the shown '
      'screen', (tester) async {
    final book = await open(tester, marginsBook);
    final reports = await show(tester, book, initial: PdfAddress(3, 0));
    await showsScreen(tester, 3, 0);
    unawaited(reports.navigator!.move(true));
    await showsScreen(tester, 3, 1);
    await settle(tester, () => reports.places.last.character > 0, 'placed');
    final place = reports.places.last;

    await show(
      tester,
      book,
      initial: PdfAddress(3, 0),
      fontSize: 30,
      reports: reports,
    );
    final (reflow, read) = await attached(tester, book, 3);
    await settle(
      tester,
      () => shown(tester)?.settings.fontSize == 30,
      'the smaller text shows',
    );
    final smaller = shown(tester)!;
    expect(
      smaller.screen,
      smaller.column.column.screenAt(
        place.character,
        read.attachment!,
        reflow.analysis,
      ),
    );
    await close(tester, book);
  });

  testWidgets('overlapping size changes preserve the word that remained '
      'visible instead of a screen that never appeared', (tester) async {
    final supply = HeldRecognition.gibbon()..textArrives.complete();
    final born = await open(tester, footnotePage);
    final book = CopiedPdf(born, textSupply: supply);
    final reports = await show(tester, book);
    await showsScreen(tester, 1, 0);
    unawaited(reports.navigator!.move(true));
    final before = await showsScreen(tester, 1, 1);
    final bandsArrive = Completer<void>();
    addTearDown(() {
      if (!bandsArrive.isCompleted) bandsArrive.complete();
    });
    book.bandsWait = bandsArrive.future;
    await show(tester, book, fontSize: 14, reports: reports);
    await settle(tester, () => book.waitingBands > 0, 'smaller bands wait');
    expect(shown(tester), same(before));
    final count = reports.places.length;
    book.bandsWait = null;
    await show(tester, book, fontSize: 40, reports: reports);
    await settle(
      tester,
      () => reports.places.length > count,
      'size 40 returns',
    );
    expect(shown(tester)!.screen, before.screen);
    expect(shown(tester)!.column, same(before.column));
    bandsArrive.complete();
    await close(tester, book);
  });

  testWidgets('a size change during a pending turn preserves the displayed '
      'word rather than the turn that has not appeared', (tester) async {
    final supply = HeldRecognition.gibbon()..textArrives.complete();
    final born = await open(tester, footnotePage);
    final book = CopiedPdf(born, textSupply: supply);
    final reports = await show(tester, book);
    await showsScreen(tester, 1, 0);
    final (reflow, read) = await attached(tester, book, 1);
    final bandsArrive = Completer<void>();
    addTearDown(() {
      if (!bandsArrive.isCompleted) bandsArrive.complete();
    });
    book.bandsWait = bandsArrive.future;
    unawaited(reports.navigator!.move(true));
    final before = await showsScreen(tester, 1, 1);
    final character = firstCharacter(
      before.column.column,
      before.screen,
      read.attachment!,
      reflow.analysis,
    )!;
    await settle(tester, () => book.waitingBands > 0, 'the turn waits');
    unawaited(reports.navigator!.move(true));
    await tester.pump();
    expect(shown(tester), same(before));
    await show(tester, book, fontSize: 60, reports: reports);
    await settle(tester, () => book.waitingBands > 1, 'larger bands wait');
    bandsArrive.complete();
    await settle(
      tester,
      () => shown(tester)?.settings.fontSize == 60,
      'the larger screen shows',
    );
    final after = shown(tester)!;
    expect(
      after.screen,
      after.column.column.screenAt(
        character,
        read.attachment!,
        reflow.analysis,
      ),
    );
    await close(tester, book);
  });

  testWidgets('the scrub deck\'s preview of a page starts no layout pass and '
      'no recognition', (tester) async {
    final born = await open(tester, marginsBook);
    late final HeldRecognition supply;
    supply = HeldRecognition(
      layout: born.geometry,
      read: (page, geometry) => born.attachedText(page, geometry!),
    )..textArrives.complete();
    final scanned = CopiedPdf(born, textSupply: supply);
    final reports = await show(tester, scanned, initial: PdfAddress(2, 0));
    await showsScreen(tester, 2, 0);
    await settle(tester, () => !progressLine(), 'the text attached');
    supply.asked.clear();

    final preview = await tester.runAsync(
      () => reports.navigator!.preview(
        (part: 6, progress: 0),
        300,
        Completer<void>().future,
      ),
    );
    preview!.image.dispose();
    expect(supply.asked, isEmpty);
    await close(tester, born);
  });

  for (final stage in [
    'geometry',
    'analysis',
    'column',
    'bands',
    'attachment',
    'selection text',
  ]) {
    testWidgets('an internal $stage error reaches the initial word-screen '
        'wait instead of selecting fallback', (tester) async {
      final failure = AssertionError('Broken $stage invariant');
      final normal = HeldRecognition.gibbon();
      final supply = HeldRecognition(
        layout: stage == 'geometry'
            ? (_) async => throw failure
            : normal.layout,
        read: stage == 'attachment'
            ? (_, _) async => throw failure
            : normal.read,
      )..textArrives.complete();
      Future<R> failingWork<M, R>(FutureOr<R> Function(M) work, M input) =>
          (stage == 'analysis' && work == analyzePage) ||
              (stage == 'column' && work == planWordColumn) ||
              (stage == 'selection text' && work == prepareWordText)
          ? Future.error(failure)
          : runInWorker(work, input);
      final born = await open(tester, footnotePage, hop: failingWork);
      final bandsArrive = Completer<void>();
      addTearDown(() {
        if (!bandsArrive.isCompleted) bandsArrive.complete();
      });
      final book = CopiedPdf(born, textSupply: supply)
        ..bandFailure = stage == 'bands' ? failure : null
        ..bandsWait = stage == 'attachment' || stage == 'selection text'
            ? bandsArrive.future
            : null;
      var fallbacks = 0;
      final screens = PdfWordScreens(
        book,
        onPlace: (_) {},
        onGiveUp: () => fallbacks++,
      );
      addTearDown(screens.dispose);
      screens.lay((
        width: 370.0,
        fontSize: 40.0,
        screenHeight: 850.0,
        devicePixelRatio: 2.625,
      ));
      Object? reported;
      var settled = false;
      screens.open(PdfAddress(1, 0));
      unawaited(
        screens
            .shows(1)
            .then(
              (_) => settled = true,
              onError: (Object error, StackTrace stack) {
                reported = error;
                settled = true;
              },
            ),
      );
      await settle(
        tester,
        () => settled,
        'the initial word-screen wait settles',
      );
      expect(reported, same(failure));
      expect(fallbacks, 0);
    });
  }

  testWidgets('an internal error rendering ahead is propagated rather than '
      'treated as a retryable band failure', (tester) async {
    final failure = AssertionError('Broken ahead-band invariant');
    final born = await open(tester, footnotePage);
    final supply = HeldRecognition.gibbon()..textArrives.complete();
    final book = CopiedPdf(born, textSupply: supply);
    final pages = PdfWordPages(book);
    addTearDown(pages.dispose);
    pages.shown.addListener(() => book.bandFailure = failure);
    await tester.runAsync(() async {
      await expectLater(
        pages.show(1, (
          width: 370.0,
          fontSize: 40.0,
          screenHeight: 850.0,
          devicePixelRatio: 2.625,
        ), 0),
        throwsA(same(failure)),
      );
    });
    expect(pages.shown.value, isNotNull);
    pages.checkInvariants();
  });

  testWidgets('an internal band error remains reported after a later '
      'screen request replaces it', (tester) async {
    final failure = AssertionError('Broken replaced-band invariant');
    final born = await open(tester, footnotePage);
    final supply = HeldRecognition.gibbon()..textArrives.complete();
    final bandsArrive = Completer<void>();
    addTearDown(() {
      if (!bandsArrive.isCompleted) bandsArrive.complete();
    });
    final book = CopiedPdf(born, textSupply: supply)
      ..bandsWait = bandsArrive.future;
    final pages = PdfWordPages(book);
    addTearDown(pages.dispose);
    Object? reported;
    var settled = false;
    unawaited(
      pages
          .show(1, (
            width: 370.0,
            fontSize: 14.0,
            screenHeight: 850.0,
            devicePixelRatio: 2.625,
          ), 0)
          .then(
            (_) => settled = true,
            onError: (Object error, StackTrace stack) {
              reported = error;
              settled = true;
            },
          ),
    );
    await settle(tester, () => book.waitingBands > 0, 'old bands wait');
    book.bandsWait = null;
    await tester.runAsync(
      () => pages.show(1, (
        width: 370.0,
        fontSize: 40.0,
        screenHeight: 850.0,
        devicePixelRatio: 2.625,
      ), 0),
    );
    book.bandFailure = failure;
    bandsArrive.complete();
    await settle(tester, () => settled, 'the replaced request settles');
    expect(reported, same(failure));
    pages.checkInvariants();
  });

  testWidgets('a scanned page whose layout pass finds no words shows its '
      'original page under the progress line until its text arrives, and '
      'then its text', (tester) async {
    final supply = HeldRecognition.gibbon()..failLayout = true;
    final book = await open(tester, footnotePage, textSupply: supply);
    await show(tester, book);
    await settle(
      tester,
      () => find.byType(RawImage).evaluate().isNotEmpty,
      'the original page shows',
    );
    expect(progressLine(), isTrue);
    expect(find.byType(WordScreenView), findsNothing);

    supply.textArrives.complete();
    await settle(
      tester,
      () => find.bySemanticsLabel(RegExp('hostile')).evaluate().isNotEmpty,
      'the text view shows',
    );
    expect(progressLine(), isFalse);
    await close(tester, book);
  });

  testWidgets('a text layer page whose analysis fails shows its text', (
    tester,
  ) async {
    Future<R> failingAnalysis<M, R>(FutureOr<R> Function(M) work, M input) =>
        work == analyzePage
        ? Future.error(Exception('The analysis failed.'))
        : runInWorker(work, input);
    final book = await open(tester, marginsBook, hop: failingAnalysis);
    final layer = (await tester.runAsync(() => book.textLayer(3)))!;
    final word = layer.text.trim().split(RegExp(r'\s+')).first;
    await show(tester, book, initial: PdfAddress(3, 0));
    await settle(
      tester,
      () => find
          .bySemanticsLabel(RegExp(RegExp.escape(word)))
          .evaluate()
          .isNotEmpty,
      'the text view shows',
    );
    expect(find.byType(WordScreenView), findsNothing);
    await close(tester, book);
  });

  testWidgets('when recognition fails after the words show, the words stay '
      'and the progress line goes', (tester) async {
    final supply = HeldRecognition.gibbon()..failText = true;
    final book = await open(tester, footnotePage, textSupply: supply);
    await show(tester, book);
    await showsScreen(tester, 1, 0);
    expect(progressLine(), isTrue);

    supply.textArrives.complete();
    await settle(tester, () => !progressLine(), 'the progress line goes');
    expect((shown(tester)!.page, shown(tester)!.screen), (1, 0));
    await close(tester, book);
  });

  testWidgets('a band failure keeps the original page while text is pending '
      'and falls back to that text when it arrives', (tester) async {
    final born = await open(tester, marginsBook);
    final supply = HeldRecognition(
      layout: born.geometry,
      read: (page, geometry) async => geometry == null
          ? (text: await born.text(page), attachment: null)
          : born.attachedText(page, geometry),
    );
    addTearDown(() {
      if (!supply.textArrives.isCompleted) supply.textArrives.complete();
    });
    final book = CopiedPdf(born, textSupply: supply)
      ..bandFailure = Exception('A band could not be drawn.');
    await show(tester, book, initial: PdfAddress(3, 0));
    await settle(
      tester,
      () => supply.asked.where((request) => request == 'text 3').length == 2,
      'the failed band requests fallback text',
    );
    expect(find.bySemanticsLabel('Original source page 3'), findsOneWidget);
    expect(progressLine(), isTrue);
    supply.textArrives.complete();
    await settle(
      tester,
      () => find.byType(PdfTextView).evaluate().isNotEmpty,
      'fallback text appears',
    );
    expect(find.byType(WordScreenView), findsNothing);
    expect(progressLine(), isFalse);
    await close(tester, born);
  });
}
