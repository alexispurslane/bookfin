// The reading place of a PDF page whose text is still on its way
// (boo-f9xa). Recognition of a scanned page takes seconds, and the page
// shows meanwhile, so the page is the saved place before its text arrives.

import 'dart:async';
import 'dart:convert';

import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/crossings/crossings.dart';
import 'package:bookfin/playback/records.dart';
import 'package:bookfin/reader/book_map.dart';
import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/page_geometry.dart';
import 'package:bookfin/reader/pdf.dart';
import 'package:bookfin/reader/pdf_text_view.dart';
import 'package:bookfin/reader/platform_io.dart';
import 'package:bookfin/reader/screen.dart';
import 'package:bookfin/reader/session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'native_reader.dart' show finishReader, settleReader;
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

  /// Lets go of the text of [page], as a book does that keeps the text of
  /// only some pages: the next request for it waits for [recognize] again.
  void forget(int page) => _recognition.remove(page);

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

/// Holds raster production separately from recognition on every page.
class HeldPageDraw extends HeldScan {
  final _draws = <int, Completer<PdfRaster>>{};

  void draw(int page) => (_draws[page] ??= Completer()).complete(
    PdfRaster(1, 1, Uint8List.fromList([255, 255, 255, 255])),
  );

  void failDraw(int page) =>
      (_draws[page] ??= Completer()).completeError(Exception('raster failed'));

  @override
  Future<PdfRaster> render(int sourcePage, double width) =>
      (_draws[sourcePage] ??= Completer()).future;
}

/// Waits for native image decoding, without advancing the report clock.
Future<void> showOriginal(WidgetTester tester, int page) async {
  final original = find.byWidgetPredicate(
    (widget) =>
        widget is Semantics &&
        widget.properties.label == 'Original source page $page',
  );
  for (var frame = 0; frame < 100; frame++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (original.evaluate().isNotEmpty) break;
  }
  expect(original, findsOneWidget);
  expect(
    find.descendant(of: original, matching: find.byType(RawImage)),
    findsOneWidget,
  );
}

/// A scan whose recognition the reader can cancel, as the bundled
/// recognition does: a cancel ends every wait for a page's text with a
/// failed text, and a later request for the page waits again.
class CancelableScan extends HeldScan {
  @override
  late final PdfTextSupply textSupply = _HeldRecognition(this);

  void _cancel() {
    final waits = [
      for (final MapEntry(key: page, value: wait) in _recognition.entries)
        if (!wait.isCompleted) (page, wait),
    ];
    for (final (page, wait) in waits) {
      _recognition.remove(page);
      wait.complete(
        const PdfText(
          source: '',
          text: '',
          sourceOffsets: [],
          status: PdfTextStatus.failed,
          reason: 'Recognition was canceled.',
        ),
      );
    }
  }
}

/// The recognition of a [CancelableScan]. Only its cancel does anything,
/// and the scan itself gives the text of each page.
class _HeldRecognition implements PdfTextSupply {
  _HeldRecognition(this.scan);
  final CancelableScan scan;
  @override
  final recognizing = ValueNotifier(false);
  @override
  void bind(PdfTextLease lease) {}
  @override
  void cancel() => scan._cancel();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A scan whose words for the word view never arrive, so the original page
/// of each page shows under the progress line.
class HeldWords extends HeldScan {
  @override
  Future<PageGeometry?> geometry(int sourcePage, {bool background = false}) =>
      Completer<PageGeometry?>().future;
}

/// Lets 100 ms pass, and the reports and the saves that wait in microtasks
/// run. A stop of the app after that time must not lose a page that shows,
/// whether its text arrived or not.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await settleReader(
    tester,
    () =>
        find.byType(RawImage).evaluate().isNotEmpty ||
        find.byType(PdfTextView).evaluate().isNotEmpty,
  );
  await tester.pump(const Duration(milliseconds: 100));
  for (var frame = 0; frame < 3; frame++) {
    await tester.pump();
  }
}

/// The kinds of the reading moves of [reader], newest first.
List<HistoryAction> kindsOf(ReaderSession reader) => [
  for (final move in reader.history) move.kind,
];

/// A reading session on one phone store.
ReaderSession sessionOn(
  MemoryResume store,
  HeldScan scan, {
  bool disposeAtTearDown = true,
}) {
  final downloads = LocalFiles()..files[pdfSource.key] = Uri.file('/scan.pdf');
  final reader = ReaderSession(
    downloads: downloads,
    store: store,
    load: loadPublication,
    loadDocument: (_, _) async => scan,
  );
  addTearDown(() {
    if (disposeAtTearDown) reader.dispose();
    downloads.dispose();
  });
  return reader;
}

/// Opens [scan] in the reader's Text view, or in [view], as the reader
/// screen shows it.
Future<ReaderSession> read(
  WidgetTester tester,
  HeldScan scan,
  MemoryResume store, {
  PdfPageView view = PdfPageView.text,
  bool disposeAtTearDown = true,
}) async {
  final reader = sessionOn(store, scan, disposeAtTearDown: disposeAtTearDown);
  await reader.bind(account(), [book]);
  await reader.open(book, edition);
  await reader.setPdfView(view);
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
      // Page 2 showed for less than the wait for a late text, so only the
      // page that the person stopped on reports its place.
      expect(
        reports.addresses.skip(before).map((address) => address.sourcePage),
        [3],
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

    testWidgets('a page whose text is ready reports its place once, as its '
        'text names it', (tester) async {
      final scan = HeldScan()
        ..recognize(1)
        ..recognize(2);
      final reports = Reports();
      await tester.pumpWidget(viewport(scan, reports, view: PdfPageView.text));
      await settle(tester);
      final before = reports.addresses.length;
      await finishReader(tester, reports.navigator!.move(true));
      await settle(tester);
      final turned = reports.addresses.skip(before).toList();
      expect(turned.first.quote, HeldScan.words(2));
      expect(
        turned.map((address) => jsonEncode(address.toJson())).toSet(),
        hasLength(1),
        reason: 'Every report of the turn names the same full place.',
      );
      expect(reports.refined, isEmpty);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
      'a change of view during recognition makes no repeated place report',
      (tester) async {
        final scan = HeldScan();
        final reports = Reports();
        await tester.pumpWidget(
          viewport(scan, reports, view: PdfPageView.text),
        );
        await settle(tester);
        final before = reports.addresses.length;
        await tester.pumpWidget(
          viewport(scan, reports, view: PdfPageView.original),
        );
        await settle(tester);
        await tester.pumpWidget(
          viewport(scan, reports, view: PdfPageView.text),
        );
        await settle(tester);
        expect(reports.addresses, hasLength(before));
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets('a turn back to a scanned page reports that page first, and '
        'then its end as its text names it', (tester) async {
      final scan = HeldScan()..recognize(2);
      final reports = Reports();
      await tester.pumpWidget(
        viewport(
          scan,
          reports,
          view: PdfPageView.text,
          initial: PdfAddress(2, 0),
        ),
      );
      await settle(tester);
      final before = reports.addresses.length;
      unawaited(reports.navigator!.move(false));
      await settle(tester);
      final early = reports.addresses.skip(before).single;
      expect((early.sourcePage, early.character), (1, 0));
      expect(reports.refined, isEmpty);
      scan.recognize(1);
      await settle(tester);
      expect(reports.refined.single.sourcePage, 1);
      expect(reports.refined.single.character, HeldScan.words(1).length);
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
    for (final trigger in ['timer', 'flush', 'contents']) {
      testWidgets('a $trigger cannot save an unseen scanned page', (
        tester,
      ) async {
        final store = MemoryResume();
        final scan = HeldPageDraw()..recognize(1);
        final reader = await read(tester, scan, store);
        expect(find.byType(PdfTextView), findsOneWidget);
        expect(reader.position!.sourcePage, 1);
        if (trigger == 'contents') {
          unawaited(reader.goToContents('page:2'));
        } else {
          unawaited(reader.move(true));
        }
        await tester.pump();
        expect(find.byType(PdfTextView), findsNothing);
        expect(find.byType(RawImage), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        if (trigger == 'flush') {
          await reader.flush();
        } else {
          await tester.pump(const Duration(milliseconds: 100));
          await tester.pump();
        }
        final before = await restarted(store);
        await before.open(book, edition);
        expect((before.initialAddress as PdfAddress).sourcePage, 1);
        expect(
          before.history.where((move) => move.kind == HistoryAction.chapter),
          isEmpty,
        );

        scan.draw(2);
        await showOriginal(tester, 2);
        if (trigger == 'flush') {
          await reader.flush();
        } else {
          await settle(tester);
        }
        final after = await restarted(store);
        await after.open(book, edition);
        expect((after.initialAddress as PdfAddress).sourcePage, 2);
        if (trigger == 'contents') {
          final jump = after.history.firstWhere(
            (move) => move.kind == HistoryAction.chapter,
          );
          expect((pageOf(jump.before), pageOf(jump.after)), (1, 2));
        }
      });
    }

    testWidgets(
      'a failed raster does not lose a jump whose text later appears',
      (tester) async {
        final store = MemoryResume();
        final scan = HeldPageDraw()..recognize(1);
        final reader = await read(tester, scan, store);
        final jump = reader.goToContents('page:2');
        await tester.pump();
        scan.failDraw(2);
        await tester.pump();
        expect(find.text('Retry source page'), findsOneWidget);
        expect(reader.position!.sourcePage, 1);
        scan.recognize(2);
        await finishReader(tester, jump);
        await settle(tester);
        final next = await restarted(store);
        final chapters = next.history.where(
          (move) => move.kind == HistoryAction.chapter,
        );
        expect(chapters, hasLength(1));
        final move = chapters.single;
        expect((pageOf(move.before), pageOf(move.after)), (1, 2));
        expect(find.byType(PdfTextView), findsOneWidget);
      },
    );

    testWidgets('ready text becomes the saved page only after its frame', (
      tester,
    ) async {
      final store = MemoryResume();
      final scan = HeldPageDraw()
        ..recognize(1)
        ..recognize(2);
      final reader = await read(tester, scan, store);
      final turn = reader.move(true);
      await Future<void>.value();
      await Future<void>.value();
      await reader.flush();
      final before = await restarted(store);
      await before.open(book, edition);
      expect((before.initialAddress as PdfAddress).sourcePage, 1);
      await finishReader(tester, turn);
      await settle(tester);
      expect(find.byType(PdfTextView), findsOneWidget);
      final after = await restarted(store);
      await after.open(book, edition);
      expect((after.initialAddress as PdfAddress).sourcePage, 2);
    });

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

    for (final ending in [
      'flush',
      'close',
      'pop',
      'open',
      'account',
      'remove',
      'dispose',
    ]) {
      testWidgets('a $ending before the late report saves the scanned page', (
        tester,
      ) async {
        final store = MemoryResume();
        final scan = HeldScan()..recognize(1);
        final reader = await read(
          tester,
          scan,
          store,
          disposeAtTearDown: ending != 'dispose',
        );
        unawaited(reader.move(true));
        // Native decoding and a frame finish, but no fake time passes
        // between the appearance of the page and the end of the view.
        await showOriginal(tester, 2);
        expect(reader.position!.sourcePage, 1);
        switch (ending) {
          case 'flush':
            await reader.flush();
          case 'close':
            reader.closeView(reader.token);
            await reader.flush();
          case 'pop':
            await tester.pumpWidget(const SizedBox());
            await reader.flush();
          case 'open':
            await reader.open(book, edition);
            await reader.flush();
          case 'account':
            await reader.bind(null, []);
          case 'dispose':
            reader.dispose();
            await reader.flush();
          case 'remove':
            await reader.bind(account(), []);
        }
        final next = await restarted(store);
        await next.open(book, edition);
        expect((next.initialAddress as PdfAddress).sourcePage, 2);
        if (ending == 'close' || ending == 'pop' || ending == 'open') {
          final closed = next.history.firstWhere(
            (move) => move.kind == HistoryAction.close,
          );
          expect(pageOf(closed.after), 2);
        }
      });
    }

    testWidgets(
      'a jump within the PDF starts History at the pending scanned page',
      (tester) async {
        final store = MemoryResume();
        final scan = HeldScan()
          ..recognize(1)
          ..recognize(3);
        final reader = await read(tester, scan, store);
        unawaited(reader.move(true));
        await showOriginal(tester, 2);
        expect(reader.position!.sourcePage, 1);
        await finishReader(tester, reader.goToContents('page:3'));
        await reader.flush();
        final next = await restarted(store);
        expect(next.history.first.kind, HistoryAction.chapter);
        expect(pageOf(next.history.first.before), 2);
        expect(pageOf(next.history.first.after), 3);
      },
    );

    testWidgets(
      'a jump into another edition starts History at the pending scanned page',
      (tester) async {
        const other = Edition(
          id: 'other-pdf',
          kind: EditionKind.text,
          label: 'Other PDF',
          files: [pdfSource],
          memberIds: ['other'],
        );
        const both = Book(
          id: 'work',
          title: 'Two editions',
          author: 'Writer',
          editions: [edition, other],
        );
        final store = MemoryResume();
        final scan = HeldScan()
          ..recognize(1)
          ..recognize(4);
        final reader = sessionOn(store, scan);
        await reader.bind(account(), [both]);
        await reader.open(both, other);
        reader.acceptAddress(reader.token, PdfAddress(4, 0));
        await reader.addBookmark(title: 'Other edition');
        final bookmark = reader.bookmarks.single.id;
        await reader.open(both, edition);
        await reader.setPdfView(PdfPageView.text);
        await tester.pumpWidget(
          MaterialApp(
            home: ReaderScreen(reader: reader, onNightChanged: (_) {}),
          ),
        );
        addTearDown(() => tester.pumpWidget(const SizedBox()));
        await settle(tester);
        unawaited(reader.move(true));
        await showOriginal(tester, 2);
        expect(reader.position!.sourcePage, 1);

        await reader.restoreBookmark(bookmark);
        await settle(tester);
        final move = reader.history.first;
        expect(move.kind, HistoryAction.bookmarkRestore);
        expect(move.before.editionId, edition.id);
        expect(move.before.sourcePage, 2);
        expect(move.after.editionId, other.id);
        expect(move.after.sourcePage, 4);
        final next = await restarted(store);
        await next.open(book, edition);
        expect((next.initialAddress as PdfAddress).sourcePage, 2);
        reader.checkInvariants();
      },
    );

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
      await finishReader(tester, reader.goToContents('page:3'));
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

    testWidgets('the Undo offer of a jump to a scanned page shows when the '
        'jump has finished, not while the page is recognized', (tester) async {
      final store = MemoryResume();
      final scan = HeldScan()..recognize(1);
      final reader = await read(tester, scan, store);
      unawaited(reader.goToContents('page:3'));
      await settle(tester);
      // The move is recorded and saved, and Undo is not offered yet: a tap
      // on it would wait for the recognition of page 3 (td-rbtc).
      expect(reader.history.first.kind, HistoryAction.chapter);
      expect(
        (await restarted(store)).history.first.kind,
        HistoryAction.chapter,
      );
      expect(reader.undoOffer, isNull);
      scan.recognize(3);
      await settle(tester);
      expect(reader.undoOffer?.action.id, reader.history.first.id);
      expect(
        reader.describe(reader.undoOffer!.action.after).quote,
        HeldScan.words(3),
      );
      reader.checkInvariants();
    });

    testWidgets('an Undo asked for during the recognition of a jump does not '
        'run after a later page turn', (tester) async {
      final scan = CancelableScan()..recognize(1);
      final reader = await read(tester, scan, MemoryResume());
      // From Contents to page 3, which is not recognized yet.
      unawaited(reader.goToContents('page:3'));
      await settle(tester);
      expect(reader.position!.sourcePage, 3);
      // A tap on Undo, if the reader offers it now.
      unawaited(reader.undoMove());
      await settle(tester);
      expect(reader.position!.sourcePage, 3);
      // The turn cancels the recognition of page 3, which ends the jump.
      unawaited(reader.move(true));
      await settle(tester);
      expect(reader.position!.sourcePage, 4);
      expect(kindsOf(reader), [HistoryAction.chapter, HistoryAction.open]);
      reader.checkInvariants();
    });

    testWidgets(
      'two PDF chapter choices queued behind a running jump both happen',
      (tester) async {
        final scan = HeldScan()
          ..recognize(1)
          ..recognize(3)
          ..recognize(4);
        final reader = await read(tester, scan, MemoryResume());
        final running = reader.goToContents('page:2');
        await settle(tester);
        final first = reader.goToContents('page:3');
        final second = reader.goToContents('page:4');
        scan.recognize(2);
        await settle(tester);
        await Future.wait([running, first, second]);
        expect(reader.position!.sourcePage, 4);
        expect(
          reader.history
              .where((move) => move.kind == HistoryAction.chapter)
              .map((move) => pageOf(move.after)),
          [4, 3, 2],
        );
        reader.checkInvariants();
      },
    );

    testWidgets(
      'a queued PDF landing still lands after a page turn and returns true',
      (tester) async {
        final scan = HeldScan()
          ..recognize(1)
          ..recognize(3)
          ..recognize(4);
        final reader = await read(tester, scan, MemoryResume());
        final running = reader.goToContents('page:2');
        await settle(tester);
        const heard = AudioPosition(
          editionId: 'audio',
          sourceKey: 'audio:one',
          revision: 'a1',
          milliseconds: 1000,
        );
        final went = reader.goToLanding(
          TextLanding(
            heard,
            (part: 3, progress: 0),
            into: (
              editionId: edition.id,
              sourceKey: pdfSource.key,
              revision: pdfSource.revision,
            ),
            share: .6,
            chapter: 'Source page 4',
          ),
          HistoryAction.historyRestore,
        );
        await finishReader(tester, reader.move(true));
        scan.recognize(2);
        await settle(tester);
        await running;
        expect(await went, isTrue);
        expect(reader.position!.sourcePage, 4);
        expect(reader.history.first.kind, HistoryAction.historyRestore);
        expect(reader.history.first.counterpartOf, heard);
        reader.checkInvariants();
      },
    );

    testWidgets('an Undo that waits behind a jump is dropped when the person '
        'turns the page', (tester) async {
      final scan = CancelableScan()
        ..recognize(1)
        ..recognize(2);
      final reader = await read(tester, scan, MemoryResume());
      await finishReader(tester, reader.goToContents('page:2'));
      await settle(tester);
      expect(reader.undoOffer, isNotNull);
      // A jump to page 4 starts. Its page did not report its place yet, so
      // the offer of the jump before it still shows.
      unawaited(reader.goToContents('page:4'));
      await tester.pump();
      expect(reader.undoOffer, isNotNull);
      unawaited(reader.undoMove());
      await tester.pump();
      unawaited(reader.move(true));
      await settle(tester);
      expect(reader.position!.sourcePage, 5);
      expect(kindsOf(reader), isNot(contains(HistoryAction.undo)));
      reader.checkInvariants();
    });

    testWidgets('an Undo that waits behind a jump is dropped when the person '
        'asks for another jump', (tester) async {
      final scan = CancelableScan()
        ..recognize(1)
        ..recognize(2)
        ..recognize(5);
      final reader = await read(tester, scan, MemoryResume());
      await finishReader(tester, reader.goToContents('page:2'));
      await settle(tester);
      // A jump to page 4 starts, and the offer of the jump before it still
      // shows. The Undo and then the jump to page 5 wait behind it.
      unawaited(reader.goToContents('page:4'));
      await tester.pump();
      unawaited(reader.undoMove());
      await tester.pump();
      unawaited(reader.goToContents('page:5'));
      await settle(tester);
      scan.recognize(4);
      await settle(tester);
      expect(reader.position!.sourcePage, 5);
      expect(kindsOf(reader), isNot(contains(HistoryAction.undo)));
      expect(reader.history.first.before.sourcePage, 4);
      reader.checkInvariants();
    });

    testWidgets('a turn to a page whose text is ready saves the place once, '
        'as its text names it', (tester) async {
      final store = CountingStore();
      final scan = HeldScan()
        ..recognize(1)
        ..recognize(2);
      final reader = await read(tester, scan, store);
      final before = store.saves;
      await finishReader(tester, reader.move(true));
      await settle(tester);
      expect(reader.describe(reader.position!).quote, HeldScan.words(2));
      expect(store.saves, before + 1);
    });

    testWidgets('a jump to a page whose text is ready saves the place and '
        'the move once', (tester) async {
      final store = CountingStore();
      final scan = HeldScan()
        ..recognize(1)
        ..recognize(3);
      final reader = await read(tester, scan, store);
      final before = store.saves;
      await finishReader(tester, reader.goToContents('page:3'));
      await settle(tester);
      expect(
        reader.describe(reader.history.first.after).quote,
        HeldScan.words(3),
      );
      expect(store.saves, before + 1);
    });

    testWidgets('a turn in the word view with no word screen to keep saves '
        'the page while its words are on their way', (tester) async {
      final store = MemoryResume();
      final reader = await read(
        tester,
        HeldWords(),
        store,
        view: PdfPageView.pageWords,
      );
      expect(reader.position!.sourcePage, 1);
      unawaited(reader.move(true));
      await settle(tester);
      expect(reader.position!.sourcePage, 2);
      // Android stops Bookfin here: the words of page 2 did not arrive.
      final next = await restarted(store);
      await next.open(book, edition);
      expect((next.initialAddress as PdfAddress).sourcePage, 2);
    });

    testWidgets('a change of the view during recognition keeps the end of '
        'the jump for the words of the page', (tester) async {
      final scan = HeldScan()..recognize(1);
      final reader = await read(tester, scan, MemoryResume());
      unawaited(reader.goToContents('page:3'));
      await settle(tester);
      final moves = reader.history.length;
      // The view changes while the same place stays on screen.
      await reader.setPdfView(PdfPageView.original);
      await settle(tester);
      await reader.setPdfView(PdfPageView.text);
      await settle(tester);
      scan.recognize(3);
      await settle(tester);
      expect(reader.history, hasLength(moves));
      expect(reader.history.first.kind, HistoryAction.chapter);
      expect(
        reader.describe(reader.history.first.after).quote,
        HeldScan.words(3),
      );
      reader.checkInvariants();
    });

    /// The moves that [jump] records to a page under recognition: first
    /// when the page shows, and then when its text arrives. [page] is the
    /// page of the jump, whose text [scan] holds back.
    Future<void> recordsOneMove(
      WidgetTester tester,
      ReaderSession reader,
      HeldScan scan,
      int page,
      HistoryAction kind,
      Future<void> Function() jump,
    ) async {
      final moves = reader.history.length;
      unawaited(jump());
      await settle(tester);
      expect(reader.position!.sourcePage, page);
      expect(reader.history, hasLength(moves + 1));
      expect(reader.history.first.kind, kind);
      final id = reader.history.first.id;
      scan.recognize(page);
      await settle(tester);
      expect(reader.history, hasLength(moves + 1));
      expect(reader.history.first.id, id);
      expect(reader.history.first.after.sourcePage, page);
      expect(reader.undoOffer?.action.id, id);
      reader.checkInvariants();
    }

    testWidgets('a search jump to a page under recognition records one '
        'move', (tester) async {
      final scan = HeldScan();
      for (var page = 1; page <= 5; page++) {
        scan.recognize(page);
      }
      final reader = await read(tester, scan, MemoryResume());
      await reader.search('begins');
      final hit = reader.hits.firstWhere(
        (hit) => (hit.address as PdfAddress).sourcePage == 3,
      );
      scan.forget(3);
      await recordsOneMove(
        tester,
        reader,
        scan,
        3,
        HistoryAction.search,
        () => reader.openHit(hit),
      );
    });

    testWidgets('a scrub to a page under recognition records one move', (
      tester,
    ) async {
      final scan = HeldScan()..recognize(1);
      final reader = await read(tester, scan, MemoryResume());
      await recordsOneMove(
        tester,
        reader,
        scan,
        4,
        HistoryAction.seek,
        () => reader.goTo(const BookTarget(fraction: .6, part: 3, progress: 0)),
      );
    });

    testWidgets('a History go-to to a page under recognition records one '
        'move', (tester) async {
      final scan = HeldScan()
        ..recognize(1)
        ..recognize(4);
      final reader = await read(tester, scan, MemoryResume());
      await finishReader(tester, reader.goToContents('page:4'));
      await settle(tester);
      final jump = reader.history.first;
      scan.forget(1);
      await recordsOneMove(
        tester,
        reader,
        scan,
        1,
        HistoryAction.historyRestore,
        () => reader.restoreHistory(jump.id),
      );
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
      await finishReader(tester, reader.move(true));
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

    testWidgets('a repeated view of the same place keeps the move for the '
        'refinement', (tester) async {
      final scan = HeldScan();
      final reader = await read(tester, scan, MemoryResume());
      // The viewport suppresses the repeat before it reaches the session.
      await reader.setPdfView(PdfPageView.original);
      await settle(tester);
      await reader.setPdfView(PdfPageView.text);
      await settle(tester);
      scan.recognize(1);
      await settle(tester);
      final visit = reader.history.single;
      expect(reader.describe(visit.after).quote, HeldScan.words(1));
      expect(visit.moved, isFalse);
      reader.checkInvariants();
    });

    test('a refinement after the place moved inside the page leaves the '
        'earlier move as it was', () async {
      final scan = HeldScan()..recognize(1);
      final reader = await opened(scan);
      final text = await scan.text(1);
      reader.acceptAddress(reader.token, PdfAddress(1, 0));
      final visit = reader.history.single;
      // The person turned a screen inside the page, which ends no move.
      reader.acceptAddress(reader.token, PdfAddress(1, 8));
      reader.refineAddress(reader.token, scan.addressFor(1, text, 8));
      expect(reader.history.single, same(visit));
      expect(reader.describe(reader.position!).quote, isNotEmpty);
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
