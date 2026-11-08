import 'dart:async';

import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/ocr.dart';
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
  bool get canRetry => true;
  @override
  final ValueNotifier<bool> recognizing = ValueNotifier(false);
  final result = Completer<PdfText>();
  var active = false;
  var canceled = false;
  @override
  void bind(PdfTextLease lease) {}
  @override
  void retry(int page) {}
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
  @override
  Future<PdfText> text(int sourcePage) {
    const empty = PdfText(
      source: '',
      text: '',
      sourceOffsets: [],
      status: PdfTextStatus.absent,
    );
    return textSupply?.text(this, sourcePage, empty) ??
        Future.value(recognized ?? empty);
  }
}

void main() {
  testWidgets(
    'canceling unsettled scan text keeps the full reader controls usable',
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
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(reader: reader, onNightChanged: (_) {}),
        ),
      );
      await tester.pump();
      expect(find.text('Recognizing English text…'), findsOneWidget);
      await tester.tap(find.text('Stop waiting'));
      await tester.pump();
      expect(supply.canceled, isTrue, reason: 'The screen cancels it.');
      expect(find.byType(ErrorWidget), findsNothing);
      expect(find.byTooltip('Next page'), findsOneWidget);
      expect(find.text('Retry recognition'), findsOneWidget);
      expect((reader.visibleAddress as PdfAddress).sourcePage, 1);
      expect((reader.visibleAddress as PdfAddress).character, 0);
    },
  );

  testWidgets(
    'English recognition can be canceled while its original page remains visible',
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
      expect(find.text('Recognizing English text…'), findsOneWidget);
      await tester.tap(find.text('Stop waiting'));
      await tester.pump();
      expect(supply.canceled, isTrue);
      expect(find.bySemanticsLabel('Original source page 1'), findsOneWidget);
      expect(
        find.textContaining('Other languages are not supported.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      supply.recognizing.dispose();
    },
  );

  testWidgets(
    'recognized text feeds the existing reflow, search and source-page navigation',
    (tester) async {
      final pdf = ViewportPdf(recognized: decodeRecognizedPage(englishPage));
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
      await tester.tap(find.byTooltip('Reflow text'));
      await tester.pump();
      expect(find.text('The quiet garden.'), findsOneWidget);
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
}
