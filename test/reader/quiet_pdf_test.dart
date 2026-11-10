// A PDF opens quietly on its original pages. Reflow is a view that the
// person chooses. It recognizes a page by itself only when the page has no
// usable text layer, and says nothing about it unless reflow failed on the
// shown page.
import 'dart:async';

import 'package:bookfin/catalog/glass.dart' show CoverGlass;
import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/page_geometry.dart';
import 'package:bookfin/reader/pdf.dart';
import 'package:bookfin/reader/pdf_text_view.dart';
import 'package:bookfin/reader/pdf_viewport.dart';
import 'package:bookfin/reader/platform_io.dart';
import 'package:bookfin/reader/screen.dart';
import 'package:bookfin/reader/session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback/playback_test.dart' show account, LocalFiles, MemoryResume;
import 'pdf_document_test.dart' show pdfSource;
import 'pdf_navigation_test.dart' show HeldPdf;
import 'pdf_session_test.dart' show book, edition;
import 'pdf_viewport_test.dart' show drawn;
import 'reader_settings.dart';

/// Recognition that answers each page only when the test says so. It
/// records the pages that it was asked to recognize.
class OnDemandRecognition implements PdfTextSupply {
  @override
  Future<PageGeometry?> geometry(
    PdfBook book,
    int page,
    PdfText extracted, {
    bool background = false,
  }) => throw StateError('The viewport asked the supply for words.');
  @override
  Future<({PdfText text, TextAttachment? attachment})> attachedText(
    PdfBook book,
    int page,
    PdfText extracted,
    PageGeometry geometry,
  ) => throw StateError('The viewport asked the supply for attached text.');
  final requests = <int>[];
  final _pages = <int, Completer<PdfText>>{};
  var cancels = 0;
  @override
  final ValueNotifier<bool> recognizing = ValueNotifier(false);
  @override
  void bind(PdfTextLease lease) {}
  @override
  void cancel() {
    cancels++;
    recognizing.value = false;
  }

  /// Answers the recognition of [page] with [text].
  void finish(int page, PdfText text) =>
      _pages.putIfAbsent(page, Completer.new).complete(text);

  @override
  Future<PdfText> text(PdfBook book, int page, PdfText extracted) {
    if (extracted.status == PdfTextStatus.candidate) {
      return Future.value(extracted);
    }
    requests.add(page);
    recognizing.value = true;
    return _pages
        .putIfAbsent(page, Completer.new)
        .future
        .whenComplete(() => recognizing.value = false);
  }

  @override
  Future<void> close() async {}
}

/// A two-page PDF whose original pages draw at once and whose text layer
/// on every page is [layer].
class LayeredPdf extends HeldPdf {
  LayeredPdf(this.layer, {this.textSupply}) {
    rendering.complete(
      PdfRaster(1, 1, Uint8List.fromList([255, 255, 255, 255])),
    );
  }
  final PdfText layer;
  @override
  final PdfTextSupply? textSupply;
  @override
  Future<PdfText> textLayer(int sourcePage) async => layer;
}

PdfText pageText(String text) => PdfText(
  source: text,
  text: text,
  sourceOffsets: List.generate(text.length, (index) => index),
  status: PdfTextStatus.candidate,
  digest: 'digest of $text',
);

const noLayer = PdfText(
  source: '',
  text: '',
  sourceOffsets: [],
  status: PdfTextStatus.absent,
);

final textLayer = pageText('The river runs to the sea.');

/// The text that the reader shows inside the page area, apart from the
/// reflowed page text itself.
List<String> notices(WidgetTester tester, {String? page}) => [
  for (final text in tester.widgetList<Text>(
    find.descendant(of: find.byType(PdfViewport), matching: find.byType(Text)),
  ))
    if ((text.data ?? text.textSpan?.toPlainText()) case final shown?)
      if (shown != page) shown,
];

/// The reflowed text of the shown page.
final reflowed = find.descendant(
  of: find.byType(PdfViewport),
  matching: find.byType(PdfTextView),
);

/// Opens [pdf] in a new reader session and shows the reader screen, and
/// waits until its first original page is drawn.
Future<ReaderSession> openPdf(WidgetTester tester, PdfBook pdf) async {
  final downloads = LocalFiles()..files[pdfSource.key] = Uri.file('/book.pdf');
  final reader = ReaderSession(
    downloads: downloads,
    store: MemoryResume(),
    load: loadPublication,
    loadDocument: (_, _) async => pdf,
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    reader.dispose();
    downloads.dispose();
  });
  await reader.bind(account(), [book]);
  await reader.open(book, edition);
  await tester.pumpWidget(
    MaterialApp(
      home: ReaderScreen(reader: reader, onNightChanged: (_) {}),
    ),
  );
  await drawn(tester);
  return reader;
}

Future<void> chooseReflow(WidgetTester tester) =>
    chooseSetting(tester, 'Reflow text', settle: tester.pump);

void main() {
  group('a PDF opens on its original page', () {
    testWidgets('a scanned PDF opens on its original page without any '
        'prompt and without recognition', (tester) async {
      final recognition = OnDemandRecognition();
      addTearDown(recognition.recognizing.dispose);
      await openPdf(tester, LayeredPdf(noLayer, textSupply: recognition));
      await drawn(tester);
      expect(find.bySemanticsLabel('Original source page 1'), findsOneWidget);
      expect(recognition.requests, isEmpty);
      expect(notices(tester), isEmpty);
      expect(find.byType(TextButton), findsNothing);
      expect(
        find.descendant(
          of: find.byType(PdfViewport),
          matching: find.byType(CoverGlass),
        ),
        findsNothing,
      );
    });

    testWidgets('a text PDF opens on its original page with no notice', (
      tester,
    ) async {
      await openPdf(tester, LayeredPdf(textLayer));
      expect(find.bySemanticsLabel('Original source page 1'), findsOneWidget);
      expect(notices(tester), isEmpty);
    });

    testWidgets('turning the original page of a scanned PDF recognizes '
        'nothing', (tester) async {
      final recognition = OnDemandRecognition();
      addTearDown(recognition.recognizing.dispose);
      final reader = await openPdf(
        tester,
        LayeredPdf(noLayer, textSupply: recognition),
      );
      // The turn would wait for recognition, so the test does not wait for
      // the turn.
      unawaited(reader.move(true));
      await drawn(
        tester,
        shown: find.bySemanticsLabel('Original source page 2'),
      );
      expect(recognition.requests, isEmpty);
      expect(notices(tester), isEmpty);
    });
  });

  group('reflow works by itself', () {
    testWidgets('switching a text PDF to reflow shows its text without '
        'recognition', (tester) async {
      final recognition = OnDemandRecognition();
      addTearDown(recognition.recognizing.dispose);
      await openPdf(tester, LayeredPdf(textLayer, textSupply: recognition));
      await chooseReflow(tester);
      await drawn(tester, shown: reflowed);
      expect(find.bySemanticsLabel(textLayer.text), findsOneWidget);
      expect(recognition.requests, isEmpty);
    });

    testWidgets('no notice covers a reflowed page', (tester) async {
      await openPdf(tester, LayeredPdf(textLayer));
      await chooseReflow(tester);
      await drawn(tester, shown: reflowed);
      expect(notices(tester, page: textLayer.text), isEmpty);
      expect(
        find.descendant(
          of: find.byType(PdfViewport),
          matching: find.byType(CoverGlass),
        ),
        findsNothing,
      );
    });

    testWidgets('switching a scanned page to reflow recognizes it without '
        'asking, and then shows its text', (tester) async {
      final recognition = OnDemandRecognition();
      addTearDown(recognition.recognizing.dispose);
      await openPdf(tester, LayeredPdf(noLayer, textSupply: recognition));
      await chooseReflow(tester);
      expect(recognition.requests, [1]);
      // While the page is recognized, its original page shows, and nothing
      // asks the person anything or covers the page.
      expect(find.bySemanticsLabel('Original source page 1'), findsOneWidget);
      expect(notices(tester), isEmpty);
      expect(find.byType(TextButton), findsNothing);
      expect(
        find.descendant(
          of: find.byType(PdfViewport),
          matching: find.byType(CoverGlass),
        ),
        findsNothing,
      );
      recognition.finish(1, pageText('The quiet garden.'));
      await drawn(tester, shown: reflowed);
      expect(find.bySemanticsLabel('The quiet garden.'), findsOneWidget);
      expect(notices(tester, page: 'The quiet garden.'), isEmpty);
    });

    testWidgets('a page whose text layer is out of order is recognized in '
        'reflow without asking', (tester) async {
      final recognition = OnDemandRecognition();
      addTearDown(recognition.recognizing.dispose);
      const scrambled = PdfText(
        source: 'eht revir',
        text: 'eht revir',
        sourceOffsets: [0, 1, 2, 3, 4, 5, 6, 7, 8],
        status: PdfTextStatus.unreliable,
      );
      await openPdf(tester, LayeredPdf(scrambled, textSupply: recognition));
      await chooseReflow(tester);
      expect(recognition.requests, [1]);
      recognition.finish(1, pageText('The river.'));
      await drawn(tester, shown: reflowed);
      expect(find.bySemanticsLabel('The river.'), findsOneWidget);
    });

    testWidgets('when reflow failed on the shown page, one quiet line takes '
        'the place of the text over the original page', (tester) async {
      final recognition = OnDemandRecognition();
      addTearDown(recognition.recognizing.dispose);
      await openPdf(tester, LayeredPdf(noLayer, textSupply: recognition));
      await chooseReflow(tester);
      recognition.finish(
        1,
        const PdfText(
          source: '',
          text: '',
          sourceOffsets: [],
          status: PdfTextStatus.failed,
          reason: 'Text recognition failed on this page.',
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(notices(tester), ['Text recognition failed on this page.']);
      expect(find.bySemanticsLabel('Original source page 1'), findsOneWidget);
      expect(find.byType(TextButton), findsNothing);
      expect(
        find.descendant(
          of: find.byType(PdfViewport),
          matching: find.byType(CoverGlass),
        ),
        findsNothing,
      );
      // The original view says nothing about reflow.
      await chooseSetting(tester, 'Original page', settle: tester.pump);
      expect(notices(tester), isEmpty);
    });

    testWidgets('choosing the original page while a page is recognized '
        'stops waiting for it and keeps the place', (tester) async {
      final recognition = OnDemandRecognition();
      addTearDown(recognition.recognizing.dispose);
      final reader = await openPdf(
        tester,
        LayeredPdf(noLayer, textSupply: recognition),
      );
      await chooseReflow(tester);
      expect(recognition.cancels, 0);
      await chooseSetting(tester, 'Original page', settle: tester.pump);
      expect(recognition.cancels, 1);
      expect(find.bySemanticsLabel('Original source page 1'), findsOneWidget);
      expect((reader.visibleAddress! as PdfAddress).sourcePage, 1);
      expect(notices(tester), isEmpty);
    });
  });

  testWidgets('the search sheet shows its field and results with no notice '
      'about how matching works', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderSearchPanel(
            searching: false,
            hits: const [],
            error: null,
            onSearch: (_) {},
            onOpenHit: (_) {},
          ),
        ),
      ),
    );
    final shown = [
      for (final text in tester.widgetList<Text>(find.byType(Text))) ?text.data,
    ];
    expect(shown.where((text) => text.contains('match')), isEmpty);
  });
}
