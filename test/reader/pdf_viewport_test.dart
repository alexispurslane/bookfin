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
import 'reader_settings.dart';

/// A text supply that fails the test when anything asks it to act. It only
/// shows whether recognition runs.
class RefusingSupply implements PdfTextSupply {
  RefusingSupply({bool recognizing = false})
    : recognizing = ValueNotifier(recognizing);
  @override
  final ValueNotifier<bool> recognizing;
  @override
  void bind(PdfTextLease lease) => throw StateError('bind');
  @override
  void cancel() =>
      throw StateError('The viewport canceled recognition itself.');
  @override
  Future<PdfText> text(PdfBook book, int page, PdfText extracted) =>
      throw StateError('The viewport asked the supply for text.');
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
  @override
  Future<void> close() => throw StateError('close');
}

/// A scanned PDF with a drawn original page and no text layer. Its text for
/// reading is [pending] while that is set, and otherwise has no text.
class ScannedPdf extends HeldPdf {
  ScannedPdf(this.textSupply) {
    rendering.complete(
      PdfRaster(1, 1, Uint8List.fromList([255, 255, 255, 255])),
    );
  }
  @override
  final PdfTextSupply textSupply;
  Future<PdfText>? pending;
  final requests = <int>[];
  @override
  Future<PdfText> textLayer(int sourcePage) async => const PdfText(
    source: '',
    text: '',
    sourceOffsets: [],
    status: PdfTextStatus.absent,
  );
  @override
  Future<PdfText> text(int sourcePage) {
    requests.add(sourcePage);
    return pending ??
        Future.value(
          const PdfText(
            source: '',
            text: '',
            sourceOffsets: [],
            status: PdfTextStatus.absent,
          ),
        );
  }
}

/// A text PDF whose original page is already drawn.
class DrawnPdf extends HeldPdf {
  DrawnPdf() {
    rendering.complete(PdfRaster(1, 1, Uint8List(4)));
  }
}

/// A PDF with a drawn original page whose page text arrives only when
/// [textArrives] completes.
class LateTextPdf extends DrawnPdf {
  final textArrives = Completer<void>();
  @override
  Future<PdfText> textLayer(int sourcePage) async {
    await textArrives.future;
    return super.textLayer(sourcePage);
  }
}

/// What a viewport reported to its owner.
class Reports {
  final addresses = <PdfAddress>[];
  var cancels = 0;
  DocumentNavigator? navigator;
}

Widget viewport(
  PdfBook book,
  Reports reports, {
  bool reflow = false,
  PdfAddress? initial,
}) => MaterialApp(
  home: Scaffold(
    body: PdfViewport(
      book: book,
      fontSize: 20,
      initial: initial,
      reflow: reflow,
      onReady: (navigator, _) => reports.navigator = navigator,
      onAddress: reports.addresses.add,
      onCancelRecognition: () => reports.cancels++,
      onTap: () {},
      onTurn: (_) {},
    ),
  ),
);

/// Lets the original page decode, which needs real time, until [shown]
/// finds the page.
Future<void> drawn(WidgetTester tester, {Finder? shown}) async {
  final page = shown ?? find.byType(RawImage);
  for (var attempt = 0; attempt < 300; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (page.evaluate().isNotEmpty) return;
  }
  fail('The page was not shown.');
}

/// Whether a dark see-through layer lies over the page, apart from the
/// tint of a glass pane.
bool dimmed() => find
    .descendant(
      of: find.byType(PdfViewport),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is ColoredBox &&
            widget.color.a > 0 &&
            widget.color.a < 1 &&
            widget.color.computeLuminance() < .05,
      ),
    )
    .evaluate()
    .any(
      (element) => element.findAncestorWidgetOfExactType<CoverGlass>() == null,
    );

PdfTextView textScreen(WidgetTester tester) =>
    tester.widget<PdfTextView>(find.byType(PdfTextView));

void main() {
  group('the viewport reports recognition choices to its owner', () {
    testWidgets(
      'while the shown page is recognized in reflow, its original page shows '
      'under a thin progress line, and nothing dims or covers it',
      (tester) async {
        final supply = RefusingSupply(recognizing: true);
        addTearDown(supply.recognizing.dispose);
        final pdf = ScannedPdf(supply)..pending = Completer<PdfText>().future;
        final reports = Reports();
        await tester.pumpWidget(viewport(pdf, reports, reflow: true));
        await drawn(tester);
        expect(
          find.bySemanticsLabel('Recognizing the text of this page'),
          findsOneWidget,
        );
        expect(dimmed(), isFalse);
        expect(find.byType(CoverGlass), findsNothing);
        expect(find.bySemanticsLabel('Original source page 1'), findsOneWidget);
        expect(reports.cancels, 0, reason: 'Opening a page cancels nothing.');
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets('choosing the original page while the shown page is '
        'recognized reports that its text is no longer wanted', (tester) async {
      final supply = RefusingSupply(recognizing: true);
      addTearDown(supply.recognizing.dispose);
      final pdf = ScannedPdf(supply)..pending = Completer<PdfText>().future;
      final reports = Reports();
      await tester.pumpWidget(viewport(pdf, reports, reflow: true));
      await drawn(tester);
      await tester.pumpWidget(viewport(pdf, reports));
      await tester.pump();
      expect(reports.cancels, 1);
      expect(
        find.bySemanticsLabel('Recognizing the text of this page'),
        findsNothing,
      );
      expect(find.bySemanticsLabel('Original source page 1'), findsOneWidget);
      expect(reports.addresses.last.sourcePage, 1);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('leaving a page whose text is still pending reports that its '
        'recognition is no longer wanted', (tester) async {
      final supply = RefusingSupply(recognizing: true);
      addTearDown(supply.recognizing.dispose);
      final pdf = ScannedPdf(supply)..pending = Completer<PdfText>().future;
      final reports = Reports();
      await tester.pumpWidget(viewport(pdf, reports, reflow: true));
      await drawn(tester);
      // The next page's text never arrives either, so the turn stays open.
      unawaited(reports.navigator!.move(true));
      await tester.pump();
      expect(reports.cancels, 1);
      expect(pdf.requests, [1, 2]);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the original view never asks for the text for reading', (
      tester,
    ) async {
      final supply = RefusingSupply();
      addTearDown(supply.recognizing.dispose);
      final pdf = ScannedPdf(supply)..pending = Completer<PdfText>().future;
      final reports = Reports();
      await tester.pumpWidget(viewport(pdf, reports));
      await drawn(tester);
      await reports.navigator!.move(true);
      await drawn(
        tester,
        shown: find.bySemanticsLabel('Original source page 2'),
      );
      expect(pdf.requests, isEmpty);
      expect(reports.cancels, 0);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('the reflow choice belongs to the viewport owner', () {
    testWidgets(
      'the viewport has no reflow buttons of its own and shows the choice '
      'of its owner',
      (tester) async {
        final pdf = DrawnPdf();
        final reports = Reports();
        await tester.pumpWidget(viewport(pdf, reports));
        await drawn(tester);
        expect(find.text('Reflow text'), findsNothing);
        expect(find.text('Original page'), findsNothing);
        expect(find.bySemanticsLabel('Original source page 1'), findsOneWidget);
        await tester.pumpWidget(viewport(pdf, reports, reflow: true));
        await tester.pumpAndSettle();
        expect(find.byType(PdfTextView), findsOneWidget);
        expect(find.text('Original page'), findsNothing);
        await tester.pumpWidget(viewport(pdf, reports));
        await drawn(tester);
        expect(find.byType(PdfTextView), findsNothing);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'switching between the original page and reflow keeps the reading '
      'place',
      (tester) async {
        final pdf = DrawnPdf();
        final text = await pdf.text(1);
        final saved = pdf.addressFor(1, text, 2000);
        final reports = Reports();
        await tester.pumpWidget(viewport(pdf, reports, initial: saved));
        await drawn(tester);
        expect(reports.addresses.last.character, 2000);
        await tester.pumpWidget(
          viewport(pdf, reports, initial: saved, reflow: true),
        );
        await tester.pumpAndSettle();
        final shown = textScreen(tester);
        expect(shown.screen, greaterThan(0));
        final reflowed = reports.addresses.last.character;
        expect(
          reflowed,
          shown.screens.firstCharacter(shown.screen),
          reason: 'Reflow starts at the screen that holds the place.',
        );
        expect(reflowed, lessThanOrEqualTo(2000));
        expect(
          shown.screens.firstCharacter(shown.screen + 1),
          greaterThan(2000),
        );
        await tester.pumpWidget(viewport(pdf, reports, initial: saved));
        await tester.pumpAndSettle();
        expect(find.byType(PdfTextView), findsNothing);
        expect(reports.addresses.last.character, reflowed);
        await tester.pumpWidget(
          viewport(pdf, reports, initial: saved, reflow: true),
        );
        await tester.pumpAndSettle();
        expect(reports.addresses.last.character, reflowed);
        expect(
          reports.addresses.map((address) => address.sourcePage),
          everyElement(1),
        );
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'a viewport that opens in reflow shows the page text at the saved place',
      (tester) async {
        final pdf = DrawnPdf();
        final saved = pdf.addressFor(1, await pdf.text(1), 2000);
        final reports = Reports();
        await tester.pumpWidget(
          viewport(pdf, reports, initial: saved, reflow: true),
        );
        await tester.pumpAndSettle();
        final shown = textScreen(tester);
        expect(shown.screen, greaterThan(0));
        expect(
          reports.addresses.last.character,
          shown.screens.firstCharacter(shown.screen),
        );
        expect(reports.addresses.last.character, lessThanOrEqualTo(2000));
        expect(
          shown.screens.firstCharacter(shown.screen + 1),
          greaterThan(2000),
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
  });

  testWidgets(
    'every place inside one reflowed page names the digest that came with '
    'its page text',
    (tester) async {
      final pdf = DrawnPdf();
      final reports = Reports();
      await tester.pumpWidget(viewport(pdf, reports, reflow: true));
      await tester.pumpAndSettle();
      for (var step = 1; step <= 6; step++) {
        await reports.navigator!.move(true);
        await tester.pump();
      }
      expect(
        reports.addresses.map((address) => address.character).toSet().length,
        greaterThan(5),
      );
      expect(
        reports.addresses.map((address) => address.representation).toSet(),
        {'fixture/fixture/extracted/fixture-text'},
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Reflow text in the reader stays chosen after the reader closes and '
    'reopens',
    (tester) async {
      final downloads = LocalFiles()
        ..files[pdfSource.key] = Uri.file('/text.pdf');
      final reader = ReaderSession(
        downloads: downloads,
        store: MemoryResume(),
        load: loadPublication,
        loadDocument: (_, _) async => DrawnPdf(),
      );
      addTearDown(() {
        reader.dispose();
        downloads.dispose();
      });
      final reflowed = find.descendant(
        of: find.byType(PdfViewport),
        matching: find.byType(PdfTextView),
      );
      Future<void> showReader({required Finder shown}) async {
        await reader.open(book, edition);
        await tester.pumpWidget(
          MaterialApp(
            home: ReaderScreen(reader: reader, onNightChanged: (_) {}),
          ),
        );
        await drawn(tester, shown: shown);
      }

      await reader.bind(account(), [book]);
      await showReader(shown: find.byType(RawImage));
      await chooseSetting(tester, 'Reflow text', settle: tester.pump);
      await drawn(tester, shown: reflowed);
      expect(reader.reflow, isTrue);
      await tester.pumpWidget(const SizedBox());
      expect(reader.document, isNull, reason: 'Closing closes the book.');
      await showReader(shown: reflowed);
      expect(reflowed, findsOneWidget);
      await chooseSetting(tester, 'Original page', settle: tester.pump);
      await drawn(tester);
      expect(reflowed, findsNothing);
      expect(find.bySemanticsLabel('Original source page 1'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Reflow text chosen while the page text loads shows the original page '
    'until the text arrives, and then the text',
    (tester) async {
      final pdf = LateTextPdf();
      final downloads = LocalFiles()
        ..files[pdfSource.key] = Uri.file('/text.pdf');
      final reader = ReaderSession(
        downloads: downloads,
        store: MemoryResume(),
        load: loadPublication,
        loadDocument: (_, _) async => pdf,
      );
      addTearDown(() {
        reader.dispose();
        downloads.dispose();
      });
      final reflowed = find.descendant(
        of: find.byType(PdfViewport),
        matching: find.byType(PdfTextView),
      );
      await reader.bind(account(), [book]);
      await reader.open(book, edition);
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(reader: reader, onNightChanged: (_) {}),
        ),
      );
      await drawn(tester);
      await chooseSetting(tester, 'Reflow text', settle: tester.pump);
      expect(reader.reflow, isTrue);
      expect(reflowed, findsNothing);
      expect(find.bySemanticsLabel('Original source page 1'), findsOneWidget);
      pdf.textArrives.complete();
      await drawn(tester, shown: reflowed);
      expect(find.bySemanticsLabel('Original source page 1'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
