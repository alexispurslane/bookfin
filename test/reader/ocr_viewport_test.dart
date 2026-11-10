import 'dart:async';

import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/ocr.dart';
import 'package:bookfin/reader/page_geometry.dart';
import 'package:bookfin/reader/pdf.dart';
import 'package:bookfin/reader/platform_io.dart';
import 'package:bookfin/reader/screen.dart';
import 'package:bookfin/reader/session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pdf_viewport_host.dart';

import '../playback/playback_test.dart' show account, LocalFiles, MemoryResume;
import 'ocr_test.dart' show englishPage;
import 'pdf_document_test.dart' show pdfSource;
import 'pdf_navigation_test.dart' show HeldPdf;
import 'pdf_session_test.dart' show book, edition;

class HeldRecognition implements PdfTextSupply {
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
  final ValueNotifier<bool> recognizing = ValueNotifier(false);
  final result = Completer<PdfText>();
  var active = false;
  var canceled = false;
  @override
  void bind(PdfTextLease lease) {}
  @override
  void cancel() {
    if (!active || result.isCompleted) return;
    canceled = true;
    recognizing.value = false;
    result.complete(
      const PdfText(
        source: '',
        text: '',
        sourceOffsets: [],
        status: PdfTextStatus.absent,
      ),
    );
  }

  @override
  Future<PdfText> text(PdfBook book, int page, PdfText extracted) {
    active = true;
    recognizing.value = true;
    return result.future;
  }

  @override
  Future<void> close() async {
    cancel();
  }
}

class ViewportPdf extends HeldPdf {
  ViewportPdf({this.textSupply, this.recognized}) {
    rendering.complete(
      PdfRaster(1, 1, Uint8List.fromList([255, 255, 255, 255])),
    );
  }
  @override
  final PdfTextSupply? textSupply;
  final PdfText? recognized;
  static const _empty = PdfText(
    source: '',
    text: '',
    sourceOffsets: [],
    status: PdfTextStatus.absent,
  );

  /// A scan has no text layer.
  @override
  Future<PdfText> textLayer(int sourcePage) async => _empty;
  @override
  Future<PdfText> text(int sourcePage) =>
      textSupply?.text(this, sourcePage, _empty) ??
      Future.value(recognized ?? _empty);
}

void main() {
  testWidgets(
    'choosing the original page while a scan is recognized keeps the full '
    'reader controls usable',
    (tester) async {
      final supply = HeldRecognition();
      final pdf = ViewportPdf(textSupply: supply);
      final downloads = LocalFiles()
        ..files[pdfSource.key] = Uri.file('/scan.pdf');
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
        supply.recognizing.dispose();
      });
      await reader.bind(account(), [book]);
      await reader.open(book, edition);
      reader.setPdfView(PdfPageView.pageWords);
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(reader: reader, onNightChanged: (_) {}),
        ),
      );
      await tester.pump();
      expect(supply.active, isTrue);
      reader.setPdfView(PdfPageView.original);
      await tester.pump();
      expect(supply.canceled, isTrue, reason: 'The screen cancels it.');
      expect(find.byType(ErrorWidget), findsNothing);
      expect(find.byTooltip('Next page'), findsOneWidget);
      expect((reader.visibleAddress as PdfAddress).sourcePage, 1);
      expect((reader.visibleAddress as PdfAddress).character, 0);
    },
  );

  testWidgets(
    'recognition stops when the person chooses the original page, which '
    'stays visible',
    (tester) async {
      final supply = HeldRecognition();
      final pdf = ViewportPdf(textSupply: supply);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PdfViewportHost(
              book: pdf,
              fontSize: 20,
              onReady: (_, _) {},
              onAddress: (_) {},
              view: PdfPageView.pageWords,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
      expect(find.bySemanticsLabel('Original source page 1'), findsOneWidget);
      expect(supply.active, isTrue);
      await tester.tap(find.byTooltip('Original page'));
      await tester.pump();
      expect(supply.canceled, isTrue);
      expect(find.bySemanticsLabel('Original source page 1'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      supply.recognizing.dispose();
    },
  );

  testWidgets(
    'recognized text feeds the existing reflow, search and source-page navigation',
    (tester) async {
      final pdf = ViewportPdf(
        recognized: decodeRecognizedPage(englishPage).text,
      );
      late DocumentNavigator navigation;
      PdfAddress? address;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PdfViewportHost(
              book: pdf,
              fontSize: 20,
              onReady: (value, _) => navigation = value,
              onAddress: (value) => address = value,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Page words'));
      // Reflow asks for the text for reading after the frame.
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.bySemanticsLabel('The quiet garden.'), findsOneWidget);
      final report = await navigation.search('garden', 1);
      expect(report.hits, hasLength(2));
      final hit = report.hits.last.address as PdfAddress;
      expect(hit.sourcePage, 2);
      expect(hit.character, 'The quiet '.length);
      await navigation.display(hit);
      await tester.pump();
      expect(address!.sourcePage, 2);
      expect(pdf.restore(pdf.save(address!))!.resource, 'page:2');
      await tester.pumpWidget(const SizedBox());
    },
  );

  group('search notes skipped pages only when they may hold text', () {
    Future<ReaderSearchReport> searchWithFirstPage(
      WidgetTester tester,
      PdfText first,
    ) async {
      final pdf = _PagedPdf(first, decodeRecognizedPage(englishPage).text);
      late DocumentNavigator navigation;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PdfViewportHost(
              book: pdf,
              fontSize: 20,
              onReady: (value, _) => navigation = value,
              onAddress: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
      final report = await navigation.search('garden', 1);
      await tester.pumpWidget(const SizedBox());
      return report;
    }

    testWidgets('a cover whose text is out of order is skipped quietly', (
      tester,
    ) async {
      final report = await searchWithFirstPage(
        tester,
        const PdfText(
          source: 'palgrave',
          text: 'palgrave',
          sourceOffsets: [0, 1, 2, 3, 4, 5, 6, 7],
          status: PdfTextStatus.unreliable,
        ),
      );
      expect(report.hits, hasLength(1));
      expect(report.error, isNull);
    });

    testWidgets('a picture page without text is skipped quietly', (
      tester,
    ) async {
      final report = await searchWithFirstPage(
        tester,
        const PdfText(
          source: '',
          text: '',
          sourceOffsets: [],
          status: PdfTextStatus.absent,
        ),
      );
      expect(report.error, isNull);
    });

    testWidgets('a page whose recognition failed is counted in the note', (
      tester,
    ) async {
      final report = await searchWithFirstPage(
        tester,
        const PdfText(
          source: '',
          text: '',
          sourceOffsets: [],
          status: PdfTextStatus.failed,
          reason: 'Text recognition failed on this page.',
        ),
      );
      expect(report.hits, hasLength(1));
      expect(report.error, contains('1 source page'));
    });
  });
}

/// A two-page PDF whose first page gives [first] and whose second page
/// gives [second] as its text for reading.
class _PagedPdf extends ViewportPdf {
  _PagedPdf(this.first, this.second);
  final PdfText first;
  final PdfText second;
  @override
  Future<PdfText> text(int sourcePage) async =>
      sourcePage == 1 ? first : second;
}
