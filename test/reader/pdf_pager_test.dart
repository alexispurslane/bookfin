import 'dart:async';

import 'package:bookfin/reader/pdf.dart';
import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/pdf_pager.dart';
import 'package:bookfin/reader/pdf_viewport.dart';
import 'package:bookfin/reader/pdf_text_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback/playback_test.dart' show account, MemoryResume;
import 'native_reader.dart' show finishReader;
import 'pdf_place_test.dart'
    show HeldScan, read, sessionOn, settle, showOriginal, restarted;
import 'pdf_session_test.dart' show book, edition;

class _CountedScan extends HeldScan {
  final textRequests = <int>[];
  @override
  Future<PdfText> text(int page) {
    textRequests.add(page);
    return super.text(page);
  }
}

Widget _view(PdfPager pager, {ValueChanged<bool>? onTurn}) => MaterialApp(
  home: Scaffold(
    body: PdfViewport(
      pager: pager,
      fontSize: 20,
      onLayout: pager.layout,
      onWordLayout: pager.words.lay,
      onAppeared: pager.appeared,
      onRetry: pager.retryPage,
      onTouch: pager.words.touch,
      onCopy: (_) {},
      onTap: () {},
      onTurn: onTurn ?? (_) {},
    ),
  ),
);

void main() {
  test(
    'opening a PDF attaches its navigation and contents before a view exists',
    () async {
      final reader = sessionOn(MemoryResume(), HeldScan());
      await reader.bind(account(), [book]);
      await reader.open(book, edition);

      expect(reader.ready, isTrue);
      expect(reader.contents.map((entry) => entry.href), [
        'page:1',
        'page:2',
        'page:3',
        'page:4',
        'page:5',
      ]);
      expect(reader.visibleAddress, isNull);
      reader.checkInvariants();
    },
  );

  testWidgets(
    'turning a PDF page updates the shown place without replacing the document contents',
    (tester) async {
      final scan = HeldScan()
        ..recognize(1)
        ..recognize(2);
      final reader = await read(
        tester,
        scan,
        MemoryResume(),
        view: PdfPageView.text,
      );
      final contents = reader.contents;
      var documentChanges = 0;
      var placeChanges = 0;
      reader.documentChanges.addListener(() => documentChanges++);
      reader.placeChanges.addListener(() => placeChanges++);

      await finishReader(tester, reader.move(true));
      await settle(tester);

      expect(reader.visibleAddress?.page, 2);
      expect(
        tester.widget<PdfTextView>(find.byType(PdfTextView)).screens.text,
        contains('Page 2 of the scan'),
      );
      reader.pdfPager!.checkInvariants();
      expect(placeChanges, greaterThan(0));
      expect(documentChanges, 0);
      expect(identical(reader.contents, contents), isTrue);
    },
  );
  testWidgets(
    'removing and replacing the view keeps the pending place and page request in the session',
    (tester) async {
      final scan = _CountedScan()..recognize(1);
      final store = MemoryResume();
      final reader = sessionOn(store, scan);
      await reader.bind(account(), [book]);
      await reader.open(book, edition);
      await reader.setPdfView(PdfPageView.text);
      final pager = reader.pdfPager!;
      await tester.pumpWidget(_view(pager));
      await settle(tester);
      unawaited(reader.move(true));
      await showOriginal(tester, 2);
      // No report-clock advance between this frame and removing the view.
      await tester.pumpWidget(const SizedBox());
      await reader.flush();
      final next = await restarted(store);
      await next.open(book, edition);
      expect((next.initialAddress as PdfAddress).sourcePage, 2);
      expect(identical(reader.pdfPager, pager), isTrue);
      expect(scan.textRequests, [1, 2]);

      scan.recognize(2);
      await tester.pump();
      await tester.pumpWidget(_view(pager));
      await settle(tester);
      expect(scan.textRequests, [1, 2]);
      expect(reader.visibleAddress?.quote, contains('Page 2'));
      expect(
        tester.widget<PdfTextView>(find.byType(PdfTextView)).screens.text,
        contains('Page 2'),
      );
      pager.checkInvariants();
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'an unmounted view cannot finish a navigation or report its requested page',
    (tester) async {
      final scan = HeldScan()
        ..recognize(1)
        ..recognize(2);
      final reader = sessionOn(MemoryResume(), scan);
      await reader.bind(account(), [book]);
      await reader.open(book, edition);
      await reader.setPdfView(PdfPageView.text);
      final pager = reader.pdfPager!;
      await tester.pumpWidget(_view(pager));
      await settle(tester);
      await tester.pumpWidget(const SizedBox());
      var completed = false;
      final jump = reader.goToContents('page:2').then((_) => completed = true);
      await tester.pump(const Duration(milliseconds: 100));
      await reader.flush();
      expect(completed, isFalse);
      expect(reader.visibleAddress?.page, 1);

      await tester.pumpWidget(_view(pager));
      await finishReader(tester, jump);
      expect(reader.visibleAddress?.page, 2);
      expect(completed, isTrue);
      pager.checkInvariants();
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('a viewport swipe reports intent without moving its pager', (
    tester,
  ) async {
    final reader = sessionOn(MemoryResume(), HeldScan()..recognize(1));
    await reader.bind(account(), [book]);
    await reader.open(book, edition);
    final pager = reader.pdfPager!;
    final turns = <bool>[];
    await tester.pumpWidget(_view(pager, onTurn: turns.add));
    await showOriginal(tester, 1);
    await tester.drag(find.byType(PdfViewport), const Offset(-250, 0));
    await tester.pump();
    expect(turns, [true]);
    expect(pager.page, 1);
    pager.checkInvariants();
    await tester.pumpWidget(const SizedBox());
  });
}
