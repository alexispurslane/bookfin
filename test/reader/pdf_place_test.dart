// The reading place of a PDF page whose text is still on its way
// (boo-f9xa). Recognition of a scanned page takes seconds, and the page
// shows meanwhile, so the page is the saved place before its text arrives.
import 'dart:async';
import 'dart:convert';

import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/playback/records.dart';
import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/pdf.dart';
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
import 'pdf_viewport_test.dart' show Reports, viewport;

/// A scanned PDF of five pages with drawn original pages and no text layer.
/// The text for reading of each page arrives only when the test recognizes
/// the page with [recognize].
class HeldScan extends HeldPdf {
  HeldScan() {
    rendering.complete(
      PdfRaster(1, 1, Uint8List.fromList([255, 255, 255, 255])),
    );
  }
  final _recognition = <int, Completer<PdfText>>{};

  Completer<PdfText> _of(int page) => _recognition[page] ??= Completer();

  /// The words that recognition reads on [page].
  static String words(int page) =>
      'Page $page of the scan begins with these recognized words.';

  /// Ends the recognition of [page] with its words.
  void recognize(int page) {
    final source = words(page);
    _of(page).complete(
      PdfText(
        source: source,
        text: source,
        sourceOffsets: List.generate(source.length, (index) => index),
        status: PdfTextStatus.candidate,
        recognition: 'fixture-ocr',
        digest: 'scan-$page',
      ),
    );
  }

  @override
  int get pageCount => 5;
  @override
  bool accepts(ReaderAddress address) =>
      address is PdfAddress && address.sourcePage <= 5;
  @override
  Future<PdfText> textLayer(int sourcePage) async => const PdfText(
    source: '',
    text: '',
    sourceOffsets: [],
    status: PdfTextStatus.absent,
  );
  @override
  Future<PdfText> text(int sourcePage) => _of(sourcePage).future;
}

/// Lets the reports and the saves that wait in microtasks run.
Future<void> settle(WidgetTester tester) async {
  for (var frame = 0; frame < 3; frame++) {
    await tester.pump();
  }
}

/// A reading session on one phone store.
ReaderSession sessionOn(MemoryResume store, HeldScan scan) {
  final downloads = LocalFiles()..files[pdfSource.key] = Uri.file('/scan.pdf');
  final reader = ReaderSession(
    downloads: downloads,
    store: store,
    load: loadPublication,
    loadDocument: (_, _) async => scan,
  );
  addTearDown(() {
    reader.dispose();
    downloads.dispose();
  });
  return reader;
}

/// Opens [scan] in the reader's Text view, as the reader screen shows it.
Future<ReaderSession> read(
  WidgetTester tester,
  HeldScan scan,
  MemoryResume store,
) async {
  final reader = sessionOn(store, scan);
  await reader.bind(account(), [book]);
  await reader.open(book, edition);
  await reader.setPdfView(PdfPageView.text);
  await tester.pumpWidget(
    MaterialApp(
      home: ReaderScreen(reader: reader, onNightChanged: (_) {}),
    ),
  );
  addTearDown(() => tester.pumpWidget(const SizedBox()));
  await settle(tester);
  return reader;
}

/// What a session that starts after Android stopped Bookfin reads from
/// [store]. Nothing closed or flushed the earlier session.
Future<ReaderSession> restarted(MemoryResume store) async {
  final reader = sessionOn(store, HeldScan());
  await reader.bind(account(), [book]);
  return reader;
}

/// The source page that the saved [place] names.
int pageOf(TextPosition place) =>
    (jsonDecode(place.anchor) as Map<String, dynamic>)['page'] as int;

/// A phone store that counts its saves of reading records.
class CountingStore extends MemoryResume {
  var saves = 0;
  @override
  Future<void> saveReading(String accountKey, ReadingChanges changes) {
    saves++;
    return super.saveReading(accountKey, changes);
  }
}

void main() {
  group('the viewport reports the page that shows before its text arrives', () {
    testWidgets('a turn to a scanned page in the text view reports that page '
        'before its recognition ends', (tester) async {
      final scan = HeldScan()..recognize(1);
      final reports = Reports();
      await tester.pumpWidget(viewport(scan, reports, view: PdfPageView.text));
      await settle(tester);
      unawaited(reports.navigator!.move(true));
      await settle(tester);
      expect(reports.addresses.last.sourcePage, 2);
      expect(reports.addresses.last.character, 0);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the place of a turned-to page is first the page itself and '
        'then the place that its recognized text names', (tester) async {
      final scan = HeldScan()..recognize(1);
      final reports = Reports();
      await tester.pumpWidget(viewport(scan, reports, view: PdfPageView.text));
      await settle(tester);
      final before = reports.addresses.length;
      unawaited(reports.navigator!.move(true));
      await settle(tester);
      scan.recognize(2);
      await settle(tester);
      final turned = reports.addresses.skip(before).toList();
      expect(turned.map((address) => address.sourcePage), everyElement(2));
      expect(turned.first.representation, isNull);
      expect(turned.first.quote, isEmpty);
      expect(turned.last.representation, 'fixture/fixture/fixture-ocr/scan-2');
      expect(turned.last.character, 0);
      expect(turned.last.quote, HeldScan.words(2));
      expect(
        reports.refined,
        isNot(contains(turned.first)),
        reason: 'The page itself is a shown place, not a refinement.',
      );
      expect(reports.refined.last.sourcePage, 2);
      expect(
        reports.refined.last.representation,
        'fixture/fixture/fixture-ocr/scan-2',
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('after two fast turns the place is the last page, before any '
        'text arrives', (tester) async {
      final scan = HeldScan()..recognize(1);
      final reports = Reports();
      await tester.pumpWidget(viewport(scan, reports, view: PdfPageView.text));
      await settle(tester);
      final before = reports.addresses.length;
      unawaited(reports.navigator!.move(true));
      await tester.pump();
      unawaited(reports.navigator!.move(true));
      await settle(tester);
      expect(
        reports.addresses.skip(before).map((address) => address.sourcePage),
        [2, 3],
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the late text of an earlier page does not move the place '
        'back', (tester) async {
      final scan = HeldScan()..recognize(1);
      final reports = Reports();
      await tester.pumpWidget(viewport(scan, reports, view: PdfPageView.text));
      await settle(tester);
      unawaited(reports.navigator!.move(true));
      await tester.pump();
      unawaited(reports.navigator!.move(true));
      await settle(tester);
      scan.recognize(2);
      await settle(tester);
      expect(reports.addresses.last.sourcePage, 3);
      expect(
        reports.addresses.where(
          (address) => address.representation?.endsWith('scan-2') ?? false,
        ),
        isEmpty,
        reason: 'The text of page 2 names no place once page 3 shows.',
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a page without words in the word view reports its place '
        'before its recognition ends', (tester) async {
      final scan = HeldScan()..recognize(1);
      final reports = Reports();
      await tester.pumpWidget(
        viewport(scan, reports, view: PdfPageView.pageWords),
      );
      await settle(tester);
      unawaited(reports.navigator!.move(true));
      await settle(tester);
      expect(reports.addresses.last.sourcePage, 2);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('the session saves the page that shows before its text arrives', () {
    testWidgets('a book that Android stops during recognition reopens at the '
        'turned-to page', (tester) async {
      final store = MemoryResume();
      final scan = HeldScan()..recognize(1);
      final reader = await read(tester, scan, store);
      expect(reader.position!.sourcePage, 1);
      unawaited(reader.move(true));
      await settle(tester);
      // Android stops Bookfin here: page 2 shows and is not recognized yet.
      final next = await restarted(store);
      await next.open(book, edition);
      expect((next.initialAddress as PdfAddress).sourcePage, 2);
    });

    testWidgets('a bookmark added during recognition marks the page that '
        'shows', (tester) async {
      final scan = HeldScan()..recognize(1);
      final reader = await read(tester, scan, MemoryResume());
      unawaited(reader.move(true));
      await settle(tester);
      await reader.addBookmark(title: 'While it was recognized');
      expect(reader.bookmarks.single.position.sourcePage, 2);
      expect(reader.bookmarkHere?.title, 'While it was recognized');
    });

    testWidgets('a jump to a scanned page saves its move with the place, '
        'before recognition ends', (tester) async {
      final store = MemoryResume();
      final scan = HeldScan()..recognize(1);
      final reader = await read(tester, scan, store);
      unawaited(reader.goToContents('page:3'));
      await settle(tester);
      expect(reader.history.first.kind, HistoryAction.chapter);
      expect(reader.history.first.after.sourcePage, 3);
      expect(reader.undoOffer?.action.id, reader.history.first.id);
      // The place that the jump left stays in reach after a stop: the saved
      // place is page 3, and the move still names page 1.
      final next = await restarted(store);
      expect(pageOf(next.history.first.before), 1);
      expect(pageOf(next.history.first.after), 3);
      await next.open(book, edition);
      expect((next.initialAddress as PdfAddress).sourcePage, 3);
    });

    testWidgets('the recognized text names the end of the jump and adds no '
        'move', (tester) async {
      final store = MemoryResume();
      final scan = HeldScan()..recognize(1);
      final reader = await read(tester, scan, store);
      unawaited(reader.goToContents('page:3'));
      await settle(tester);
      final moves = reader.history.length;
      final jump = reader.history.first.id;
      scan.recognize(3);
      await settle(tester);
      expect(reader.history, hasLength(moves));
      expect(reader.history.first.id, jump);
      expect(
        reader.describe(reader.history.first.after).quote,
        HeldScan.words(3),
        reason: 'History shows the words where the jump ended.',
      );
      expect(reader.history.first.before.sourcePage, 1);
      expect(reader.undoOffer?.action.id, jump);
      expect(
        samePlace(reader.undoOffer!.action.after, reader.position!),
        isTrue,
      );
      reader.checkInvariants();
      final next = await restarted(store);
      expect(next.history, hasLength(moves));
      expect(next.describe(next.history.first.after).quote, HeldScan.words(3));
    });

    testWidgets('the visit of a scanned book starts with one Opened entry '
        'that does not move', (tester) async {
      final scan = HeldScan();
      final reader = await read(tester, scan, MemoryResume());
      expect(reader.history.single.kind, HistoryAction.open);
      scan.recognize(1);
      await settle(tester);
      final opened = reader.history.single;
      expect(opened.kind, HistoryAction.open);
      expect(opened.moved, isFalse);
      expect(reader.describe(opened.after).quote, HeldScan.words(1));
    });

    testWidgets('Undo to a page under recognition records one undo move and '
        'ends the offer once', (tester) async {
      final scan = HeldScan()..recognize(3);
      final reader = await read(tester, scan, MemoryResume());
      await reader.goToContents('page:3');
      await settle(tester);
      expect(reader.undoOffer, isNotNull);
      List<HistoryAction> kinds() => [
        for (final move in reader.history) move.kind,
      ];
      unawaited(reader.undoMove());
      await settle(tester);
      expect(reader.position!.sourcePage, 1);
      expect(reader.undoOffer, isNull);
      expect(kinds(), [
        HistoryAction.undo,
        HistoryAction.chapter,
        HistoryAction.open,
      ]);
      scan.recognize(1);
      await settle(tester);
      expect(reader.undoOffer, isNull);
      expect(kinds(), [
        HistoryAction.undo,
        HistoryAction.chapter,
        HistoryAction.open,
      ]);
      expect(
        reader.describe(reader.history.first.after).quote,
        HeldScan.words(1),
      );
      reader.checkInvariants();
    });

    testWidgets('a turn to a page whose text names nothing new saves the '
        'place once', (tester) async {
      final store = CountingStore();
      final scan = HeldScan();
      final reader = await read(tester, scan, store);
      // The Original view asks only for the text layer, and a scan has none.
      await reader.setPdfView(PdfPageView.original);
      await settle(tester);
      final before = store.saves;
      await reader.move(true);
      await settle(tester);
      expect(reader.position!.sourcePage, 2);
      expect(store.saves, before + 1);
    });
  });

  group('a refinement names the place that shows', () {
    Future<ReaderSession> opened(HeldScan scan) async {
      final reader = sessionOn(MemoryResume(), scan);
      await reader.bind(account(), [book]);
      await reader.open(book, edition);
      return reader;
    }

    PdfAddress named(HeldScan scan, int page, PdfText text) =>
        scan.addressFor(page, text, 0);

    test('a refinement for another page than the shown one changes '
        'nothing', () async {
      final scan = HeldScan()..recognize(2);
      final reader = await opened(scan);
      reader.acceptAddress(reader.token, PdfAddress(3, 0));
      final shown = reader.position;
      reader.refineAddress(reader.token, named(scan, 2, await scan.text(2)));
      expect(reader.position, same(shown));
      expect((reader.visibleAddress as PdfAddress).sourcePage, 3);
      reader.checkInvariants();
    });

    test('a refinement before any place shows changes nothing', () async {
      final scan = HeldScan()..recognize(2);
      final reader = await opened(scan);
      reader.refineAddress(reader.token, named(scan, 2, await scan.text(2)));
      expect(reader.position, isNull);
      expect(reader.history, isEmpty);
      reader.checkInvariants();
    });

    test('a refinement after a page turn leaves the earlier move as it '
        'was', () async {
      final scan = HeldScan()
        ..recognize(1)
        ..recognize(2);
      final reader = await opened(scan);
      reader.acceptAddress(reader.token, PdfAddress(1, 0));
      final visit = reader.history.single;
      // A page turn ends no move, so the refinement of its place names none.
      reader.acceptAddress(reader.token, PdfAddress(2, 0));
      reader.refineAddress(reader.token, named(scan, 2, await scan.text(2)));
      expect(reader.history.single, same(visit));
      expect(reader.describe(reader.position!).quote, HeldScan.words(2));
      reader.checkInvariants();
    });

    test('a refinement does not bring back a move that the person '
        'deleted', () async {
      final scan = HeldScan()..recognize(1);
      final reader = await opened(scan);
      reader.acceptAddress(reader.token, PdfAddress(1, 0));
      await reader.deleteHistory(reader.history.single.id);
      reader.refineAddress(reader.token, named(scan, 1, await scan.text(1)));
      expect(reader.history, isEmpty);
      expect(reader.describe(reader.position!).quote, HeldScan.words(1));
      reader.checkInvariants();
    });
  });
}
