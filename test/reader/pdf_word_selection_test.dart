import 'dart:async';
import 'dart:io';

import 'package:bookfin/foundation/theme.dart';
import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/pdf.dart';
import 'package:bookfin/reader/pdf_viewport.dart';
import 'package:bookfin/reader/pdf_word_view.dart';
import 'package:bookfin/reader/word_pages.dart';
import 'package:bookfin/reader/word_selection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart' as native;

import 'ocr_hop_test.dart' show runInWorker;
import 'page_analysis_test.dart' show footnotePage;
import 'pdf_test_controller.dart';
import 'pdf_word_view_test.dart' show HeldRecognition, HeldWordPdf, settle;
import 'word_pages_test.dart' show marginsBook, screenPieces;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  native.Pdfrx.pdfiumModulePath = Platform.environment['PDFIUM_LIBRARY'];
  native.Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;
  tearDownAll(() => PdfRuntime.instance.shutdown());

  Future<PdfBook> open(WidgetTester tester, {PdfTextSupply? supply}) async {
    final path = supply == null ? marginsBook : footnotePage;
    final book = (await tester.runAsync(
      () async => PdfRuntime.instance.open(
        path,
        'e' * 64,
        textSupply: supply,
        hop: runInWorker,
      ),
    ))!;
    addTearDown(() async {
      if (supply is HeldRecognition && !supply.textArrives.isCompleted) {
        supply.textArrives.complete();
      }
      await tester.pumpWidget(const SizedBox());
      var closed = false;
      unawaited(book.dispose().then((_) => closed = true));
      await settle(tester, () => closed, 'the PDF releases its native work');
    });
    return book;
  }

  WordScreen? shown(WidgetTester tester) {
    final view = find.byType(WordScreenView);
    return view.evaluate().isEmpty
        ? null
        : tester.widget<WordScreenView>(view).screen.value;
  }

  Future<DocumentNavigator> show(
    WidgetTester tester,
    PdfBook book, {
    int page = 2,
    VoidCallback? onTap,
  }) async {
    tester.view
      ..physicalSize = const Size(412, 480)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    DocumentNavigator? navigator;
    await tester.pumpWidget(
      MaterialApp(
        theme: bookfinTheme(Brightness.light),
        home: Scaffold(
          body: PdfTestController(
            book: book,
            fontSize: 20,
            initial: PdfAddress(page, 0),
            view: PdfPageView.pageWords,
            onReady: (value, _) => navigator = value,
            onAddress: (_) {},
            onRefinedAddress: (_) {},
            onCancelRecognition: () {},
            onTap: onTap ?? () {},
            onTurn: (forward) => unawaited(navigator!.move(forward)),
          ),
        ),
      ),
    );
    await settle(tester, () => shown(tester) != null, 'word images show');
    return navigator!;
  }

  Future<Rect> wordBox(WidgetTester tester, PdfBook book, String word) async {
    final screen = shown(tester)!;
    final attached = (await tester.runAsync(() async {
      final page = (await book.reflowPage(screen.page))!;
      return page.attachedText();
    }))!;
    final column = screen.column.column;
    for (final piece in screenPieces(column, screen.screen)) {
      final index = column.word(piece);
      if (index < 0) continue;
      final first = attached.attachment![index * 2];
      final end = attached.attachment![index * 2 + 1];
      if (attached.text.source.substring(first, end) != word) continue;
      return column
          .target(piece)
          .shift(
            tester.getTopLeft(find.byType(WordScreenView)) -
                Offset(0, column.screenTop(screen.screen)),
          );
    }
    throw StateError('The shown screen has no word "$word".');
  }

  WordSelection selection(WidgetTester tester) =>
      tester
          .renderObject<RenderWordSelectable>(find.byType(WordSelectable))
          .selection
        ..checkInvariants();

  testWidgets('retained words cannot select an unseen source page while '
      'its replacement images are pending', (tester) async {
    final born = await open(tester);
    final book = HeldWordPdf(born);
    final navigator = await show(tester, book);
    final screens = tester
        .widget<PdfWordView>(find.byType(PdfWordView))
        .screens;
    await settle(
      tester,
      () => screens.text.value != null,
      'selection is ready',
    );
    final point = (await wordBox(tester, book, 'Falling')).center;
    await tester.longPressAt(point);
    await tester.pumpAndSettle();
    expect(selection(tester).text, 'Falling');
    final before = shown(tester)!;
    final bandsArrive = Completer<void>();
    addTearDown(() {
      if (!bandsArrive.isCompleted) bandsArrive.complete();
    });
    book.bandsWait = bandsArrive.future;
    unawaited(navigator.display(PdfAddress(3, 0)));
    await settle(
      tester,
      () => book.waitingBands > 0 && !screens.waitingForText.value,
      'the target has text but its images still wait',
    );
    expect(shown(tester), same(before));
    expect(screens.text.value, isNull);
    expect(selection(tester).text, isNull);
    expect(selection(tester).rects, isEmpty);
    await tester.longPressAt(point);
    await tester.pump();
    expect(find.text('Copy'), findsNothing);
    expect(selection(tester).selecting, isFalse);
    expect(find.bySemanticsLabel('Original source page 3'), findsNothing);
    screens.checkInvariants();
    bandsArrive.complete();
    await settle(
      tester,
      () => shown(tester)?.page == 3 && screens.text.value != null,
      'the target images and their own selection text show together',
    );
    expect(selection(tester).screen, same(screens.text.value));
    expect(screens.text.value!.column, same(shown(tester)!.column.column));
    screens.checkInvariants();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'selection keeps the original reading text and attachment after worker preparation',
    (tester) async {
      final book = await open(tester);
      await show(tester, book);
      final screens = tester
          .widget<PdfWordView>(find.byType(PdfWordView))
          .screens;
      await settle(
        tester,
        () => screens.text.value != null,
        'selection text is ready',
      );
      final original = (await tester.runAsync(() async {
        return (await book.reflowPage(2))!.attachedText();
      }))!;
      expect(screens.text.value!.page.attached.text, same(original.text));
      expect(
        screens.text.value!.page.attached.attachment,
        same(original.attachment),
      );
      screens.checkInvariants();
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('dragging a word-image handle selects individual characters', (
    tester,
  ) async {
    final book = await open(tester);
    await show(tester, book);
    final first = await wordBox(tester, book, 'Falling');
    final last = await wordBox(tester, book, 'Bodies');
    await tester.longPressAt(first.center);
    await tester.pumpAndSettle();
    final finger = await tester.startGesture(
      first.bottomRight + const Offset(4, 10),
    );
    final move = Offset(last.center.dx, last.bottom) - first.bottomRight;
    for (var step = 0; step < 10; step++) {
      await finger.moveBy(move / 10);
      await tester.pump();
    }
    await finger.up();
    await tester.pumpAndSettle();
    expect(selection(tester).text, 'Falling Bod');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'a tap clears selection and only the next tap toggles the reader controls',
    (tester) async {
      var taps = 0;
      final book = await open(tester);
      await show(tester, book, onTap: () => taps++);
      await tester.longPressAt((await wordBox(tester, book, 'Falling')).center);
      await tester.pumpAndSettle();
      expect(selection(tester).selecting, isTrue);
      await tester.tapAt(const Offset(200, 350));
      await tester.pumpAndSettle();
      expect(selection(tester).selecting, isFalse);
      expect(taps, 0);
      await tester.tapAt(const Offset(200, 350));
      await tester.pumpAndSettle();
      expect(taps, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'a search hit opens the word screen that contains its first character',
    (tester) async {
      final book = await open(tester);
      final navigator = await show(tester, book);
      ReaderSearchReport? report;
      unawaited(navigator.search('the', 1).then((value) => report = value));
      await settle(tester, () => report != null, 'the search finishes');
      final hit = report!.hits.lastWhere((hit) => hit.address.page == 2);
      final address = hit.address as PdfAddress;
      unawaited(navigator.display(address));
      await settle(tester, () {
        final view = tester.widget<PdfWordView>(find.byType(PdfWordView));
        final text = view.screens.text.value;
        return text != null &&
            text.screen > 0 &&
            text.extent!.$1 <= address.character &&
            address.character < text.extent!.$2;
      }, 'the search hit is on the shown word screen');
      expect(shown(tester)!.page, 2);
      final text = tester
          .widget<PdfWordView>(find.byType(PdfWordView))
          .screens
          .text
          .value!;
      expect(
        text.rectsFor(address.character, address.character + 3),
        isNotEmpty,
      );
      expect(
        text.page.attached.text.source
            .substring(address.character, address.character + 3)
            .toLowerCase(),
        'the',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'a turn clears selection and a swipe with selection does not turn',
    (tester) async {
      final book = await open(tester);
      final navigator = await show(tester, book);
      await tester.longPressAt((await wordBox(tester, book, 'Falling')).center);
      await tester.pumpAndSettle();
      expect(selection(tester).text, 'Falling');
      final before = shown(tester)!;
      await tester.dragFrom(const Offset(350, 350), const Offset(-200, 0));
      await tester.pumpAndSettle();
      expect(shown(tester), same(before));
      unawaited(navigator.move(true));
      await settle(
        tester,
        () => shown(tester)?.screen != before.screen,
        'the next word screen shows',
      );
      expect(selection(tester).text, isNull);
      expect(selection(tester).rects, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('a long press selects the printed word and Copy gives its '
      'reading text', (tester) async {
    final book = await open(tester);
    await show(tester, book);
    await tester.longPressAt((await wordBox(tester, book, 'Falling')).center);
    await tester.pumpAndSettle();
    expect(find.text('Copy'), findsOneWidget);
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
    await tester.tap(find.text('Copy'));
    await tester.pump();
    expect(copied, 'Falling');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the screen reader receives the reading text of each '
      'paragraph instead of an image label', (tester) async {
    final semantics = tester.ensureSemantics();
    final book = await open(tester);
    await show(tester, book);
    await tester.pump();
    final labels = <String>[];
    void read(SemanticsNode node) {
      final label = node.getSemanticsData().label;
      if (label.isNotEmpty) labels.add(label);
      node.visitChildren((child) {
        read(child);
        return true;
      });
    }

    read(tester.getSemantics(find.byType(PdfViewport)));
    expect(labels, contains('Falling Bodies'));
    expect(labels, isNot(contains('Source page 2')));
    semantics.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a long press before recognized text attaches selects '
      'nothing', (tester) async {
    final supply = HeldRecognition.gibbon();
    final book = await open(tester, supply: supply);
    await show(tester, book, page: 1);
    final screen = shown(tester)!;
    final column = screen.column.column;
    final first = screenPieces(column, screen.screen).first;
    final point =
        column.target(first).center +
        tester.getTopLeft(find.byType(WordScreenView)) -
        Offset(0, column.screenTop(screen.screen));
    await tester.longPressAt(point);
    await tester.pump();
    expect(find.text('Copy'), findsNothing);
    supply.textArrives.complete();
    await settle(
      tester,
      () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
      'the text attaches',
    );
    expect(find.text('Copy'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
