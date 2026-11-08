import 'dart:async';

import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/pdf.dart';
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

/// A text supply that fails the test when anything asks it to act. It only
/// shows whether recognition runs and whether a retry is possible.
class RefusingSupply implements PdfTextSupply {
  RefusingSupply({bool recognizing = false})
    : recognizing = ValueNotifier(recognizing);
  @override
  final ValueNotifier<bool> recognizing;
  @override
  bool get canRetry => true;
  @override
  void bind(PdfTextLease lease) => throw StateError('bind');
  @override
  void cancel() =>
      throw StateError('The viewport canceled recognition itself.');
  @override
  void retry(int page) =>
      throw StateError('The viewport retried recognition itself.');
  @override
  Future<PdfText> text(PdfBook book, int page, PdfText extracted) =>
      throw StateError('The viewport asked the supply for text.');
  @override
  Future<void> close() => throw StateError('close');
}

/// A scanned PDF with a drawn original page. Its page text is [pending]
/// while that is set, and otherwise has no extracted text.
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

/// A text PDF that counts how often it computes the digest of a page text.
class CountingPdf extends HeldPdf {
  CountingPdf() {
    rendering.complete(PdfRaster(1, 1, Uint8List(4)));
  }
  var digests = 0;
  @override
  String digest(String source) {
    digests++;
    return super.digest(source);
  }
}

/// What a viewport reported to its owner.
class Reports {
  final reflows = <bool>[];
  final retries = <int>[];
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
      onReflow: reports.reflows.add,
      onCancelRecognition: () => reports.cancels++,
      onRetryRecognition: reports.retries.add,
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

ScrollController reflowScroll(WidgetTester tester) => tester
    .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
    .controller!;

void main() {
  group('the viewport reports recognition choices to its owner', () {
    testWidgets(
      'Cancel recognition reports up, and the original page stays with a '
      'canceled note',
      (tester) async {
        final supply = RefusingSupply(recognizing: true);
        addTearDown(supply.recognizing.dispose);
        final pdf = ScannedPdf(supply)..pending = Completer<PdfText>().future;
        final reports = Reports();
        await tester.pumpWidget(viewport(pdf, reports));
        await drawn(tester);
        expect(find.text('Recognizing English text…'), findsOneWidget);
        expect(reports.cancels, 0, reason: 'Opening a page cancels nothing.');
        await tester.tap(find.text('Cancel recognition'));
        await tester.pump();
        expect(reports.cancels, 1);
        expect(find.bySemanticsLabel('Original source page 1'), findsOneWidget);
        expect(find.textContaining('Recognition canceled.'), findsOneWidget);
        expect(reports.addresses.last.sourcePage, 1);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets('leaving a page whose text is still pending reports that its '
        'recognition is no longer wanted', (tester) async {
      final supply = RefusingSupply(recognizing: true);
      addTearDown(supply.recognizing.dispose);
      final pdf = ScannedPdf(supply)..pending = Completer<PdfText>().future;
      final reports = Reports();
      await tester.pumpWidget(viewport(pdf, reports));
      await drawn(tester);
      // The next page's text never arrives either, so the turn stays open.
      unawaited(reports.navigator!.move(true));
      await tester.pump();
      expect(reports.cancels, 1);
      expect(pdf.requests, [1, 2]);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
      'Retry recognition reports the shown page, then asks the document for '
      'its text again',
      (tester) async {
        final supply = RefusingSupply();
        addTearDown(supply.recognizing.dispose);
        final pdf = ScannedPdf(supply);
        final reports = Reports();
        await tester.pumpWidget(viewport(pdf, reports));
        await drawn(tester);
        await tester.tap(find.text('Retry recognition'));
        await tester.pump();
        expect(reports.retries, [1]);
        expect(pdf.requests, [1, 1]);
        await tester.pumpWidget(const SizedBox());
      },
    );
  });

  group('the reflow choice belongs to the viewport owner', () {
    testWidgets(
      'Reflow text and Original page report the choice and leave the view '
      'to the owner',
      (tester) async {
        final pdf = CountingPdf();
        final reports = Reports();
        await tester.pumpWidget(viewport(pdf, reports));
        await drawn(tester);
        await tester.tap(find.text('Reflow text'));
        await tester.pump();
        expect(reports.reflows, [true]);
        expect(find.byType(SingleChildScrollView), findsNothing);
        expect(find.bySemanticsLabel('Original source page 1'), findsOneWidget);
        await tester.pumpWidget(viewport(pdf, reports, reflow: true));
        await tester.pumpAndSettle();
        expect(find.byType(SingleChildScrollView), findsOneWidget);
        await tester.tap(find.text('Original page'));
        await tester.pump();
        expect(reports.reflows, [true, false]);
        expect(find.byType(SingleChildScrollView), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'switching between the original page and reflow keeps the reading '
      'place',
      (tester) async {
        final pdf = CountingPdf();
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
        expect(reflowScroll(tester).offset, greaterThan(0));
        final reflowed = reports.addresses.last.character;
        expect(
          reflowed,
          inInclusiveRange(2000 - 80, 2000),
          reason: 'Reflow starts at the line that holds the place.',
        );
        await tester.pumpWidget(viewport(pdf, reports, initial: saved));
        await tester.pumpAndSettle();
        expect(find.byType(SingleChildScrollView), findsNothing);
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
        final pdf = CountingPdf();
        final saved = pdf.addressFor(1, await pdf.text(1), 2000);
        final reports = Reports();
        await tester.pumpWidget(
          viewport(pdf, reports, initial: saved, reflow: true),
        );
        await tester.pumpAndSettle();
        expect(reflowScroll(tester).offset, greaterThan(0));
        expect(
          reports.addresses.last.character,
          inInclusiveRange(2000 - 80, 2000),
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
  });

  testWidgets(
    'scrolling inside one reflowed page computes its text digest once',
    (tester) async {
      final pdf = CountingPdf();
      final reports = Reports();
      await tester.pumpWidget(viewport(pdf, reports, reflow: true));
      await tester.pumpAndSettle();
      final scroll = reflowScroll(tester);
      for (var step = 1; step <= 6; step++) {
        scroll.jumpTo(scroll.position.maxScrollExtent * step / 6);
        await tester.pump();
      }
      expect(
        reports.addresses.map((address) => address.character).toSet().length,
        greaterThan(5),
      );
      expect(
        reports.addresses.map((address) => address.representation).toSet(),
        hasLength(1),
      );
      expect(pdf.digests, 1);
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
        loadDocument: (_, _) async => CountingPdf(),
      );
      addTearDown(() {
        reader.dispose();
        downloads.dispose();
      });
      final reflowed = find.descendant(
        of: find.byType(PdfViewport),
        matching: find.byType(SingleChildScrollView),
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
      await tester.tap(find.text('Reflow text'));
      await drawn(tester, shown: reflowed);
      expect(reader.reflow, isTrue);
      await tester.pumpWidget(const SizedBox());
      expect(reader.document, isNull, reason: 'Closing closes the book.');
      await showReader(shown: reflowed);
      expect(reflowed, findsOneWidget);
      await tester.tap(find.text('Original page'));
      await drawn(tester);
      expect(reflowed, findsNothing);
      expect(find.bySemanticsLabel('Original source page 1'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
