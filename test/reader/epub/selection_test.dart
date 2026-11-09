// The person selects text on the shown page and copies it. A long press
// selects a word, the handles extend the selection across the page's
// paragraphs, and Copy reports the book's own text through onCopy. A tap
// with a selection clears it, a swipe with a selection does not turn, and a
// page turn clears it. On a desktop, a mouse drag selects and the copy
// shortcut copies. A test scheduler runs the page source's layout steps,
// and real time lets the workers finish.
import 'dart:async';

import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/epub/dom.dart';
import 'package:bookfin/reader/epub/page_source.dart';
import 'package:bookfin/reader/epub/pager.dart';
import 'package:bookfin/reader/epub/publication.dart';
import 'package:bookfin/reader/epub/selection.dart';
import 'package:bookfin/reader/epub/viewport.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';
import 'page_source_test.dart' show TestScheduler, book, paragraphs;

/// A book whose first page starts with two short paragraphs. The second
/// holds a line break and white space that the page draws as one space.
Publication _harbourBook() => book([
  '<h1>The harbour</h1>'
      '<p>The harbour lights came on at dusk.</p>'
      '<p>Every boat turned\n     toward the pier.</p>'
      '${paragraphs(6)}',
  paragraphs(3, label: 'Next'),
]);

/// A hyphenated English book with long words, and one word that holds the
/// book's own soft hyphen.
Publication _hyphenatedBook() => book(
  [
    '<p>${List.filled(12, 'The extraordinarily characteristic '
    'responsibilities of incomprehensibility unquestionably '
    'overwhelmed the co­operation of the harbour.').join(' ')}</p>',
  ],
  css: 'p { hyphens: auto; text-align: justify }',
  language: 'en',
);

void main() {
  setUpAll(loadReaderFont);

  late TestScheduler scheduler;
  late PageSource source;
  EpubPager? opened;
  final turns = <bool>[];
  final links = <String>[];
  final copies = <String>[];
  var taps = 0;

  EpubPager pager() => opened!;
  ShownPage shown() => pager().shown.value!;

  setUp(() {
    scheduler = TestScheduler();
    turns.clear();
    links.clear();
    copies.clear();
    taps = 0;
  });
  tearDown(() {
    opened?.dispose();
    opened = null;
  });

  /// Runs layout steps, real time for the workers and frames until [done]
  /// holds and no step has run for a while.
  Future<void> settle(WidgetTester tester, [bool Function()? done]) async {
    var quiet = 0;
    for (var turn = 0; turn < 5000; turn++) {
      if (scheduler.runOne()) {
        quiet = 0;
      } else {
        quiet++;
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1)),
        );
      }
      await tester.pump();
      if ((done?.call() ?? true) && quiet >= 10) return;
    }
    fail('The pager did not settle.');
  }

  /// Opens [publication] in a viewport in an app of [size] logical pixels,
  /// and waits for its first page.
  Future<void> read(
    WidgetTester tester,
    Publication publication, {
    Size size = const Size(412, 671),
  }) async {
    source = PageSource(publication, schedule: scheduler.schedule);
    opened = EpubPager(
      EpubDocument(publication),
      onPlace: (_) {},
      onWarning: (_) {},
      source: source,
    );
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: EpubViewport(
          pager: pager(),
          fontSize: 20,
          night: false,
          onTap: () => taps++,
          onTurn: turns.add,
          onLink: links.add,
          onCopy: copies.add,
        ),
      ),
    );
    await settle(tester, () => pager().shown.value != null);
  }

  /// The box of the visible character [index] of [word], in the first text
  /// node of the shown page that holds it, from the screen's top left
  /// corner. The viewport fills the screen.
  Rect boxOf(String word, [int index = 0]) {
    final page = shown().page;
    final dom = source.sectionOf(page).dom;
    final text = dom.texts.firstWhere((text) => text.text.contains(word));
    final place = EpubPlace(
      page.section,
      text.order,
      text.text.indexOf(word) + index,
    );
    for (final piece in page.pieces) {
      for (var unit = 0; unit < piece.map.length; unit++) {
        if (piece.map.textPlaceAt(unit) != place) continue;
        return piece.paragraph
            .getBoxesForRange(unit, unit + 1)
            .first
            .toRect()
            .shift(Offset(piece.x, piece.y - page.top));
      }
    }
    throw StateError('$word is not on the shown page.');
  }

  /// The middle of the visible character [index] of [word].
  Offset pointOf(String word, [int index = 0]) => boxOf(word, index).center;

  /// The selection of the shown page, after it checks its invariants.
  PageSelection selection(WidgetTester tester) {
    final page = tester.renderObject(
      find.descendant(
        of: find.byType(EpubViewport),
        matching: find.byWidgetPredicate(
          (widget) => widget is LeafRenderObjectWidget,
        ),
      ),
    );
    return ((page as dynamic).selection as PageSelection)..checkInvariants();
  }

  /// Taps the context menu's button [label].
  Future<void> choose(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  SelectableRegionState region(WidgetTester tester) =>
      tester.state<SelectableRegionState>(find.byType(SelectableRegion));

  /// Presses the copy or select all shortcut of the platform: Cmd on macOS,
  /// Ctrl elsewhere.
  Future<void> shortcut(WidgetTester tester, LogicalKeyboardKey key) async {
    final modifier = defaultTargetPlatform == TargetPlatform.macOS
        ? LogicalKeyboardKey.metaLeft
        : LogicalKeyboardKey.controlLeft;
    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(modifier);
    await tester.pump();
  }

  /// The visible characters of the book's text on the shown page, from its
  /// DOM, without the book's soft hyphens.
  String pageText() {
    final page = shown().page;
    final visible = StringBuffer();
    for (final text in source.sectionOf(page).dom.texts) {
      for (final unit in text.text.codeUnits) {
        if (!isSpace(unit)) visible.writeCharCode(unit);
      }
    }
    return visible
        .toString()
        .substring(page.startVisible, page.endVisible)
        .replaceAll('­', '');
  }

  testWidgets('a long press selects the word under the finger, and Copy '
      'reports it', (tester) async {
    await read(tester, _harbourBook());

    await tester.longPressAt(pointOf('lights', 2));
    await tester.pumpAndSettle();
    expect(selection(tester).text, 'lights');
    await choose(tester, 'Copy');

    expect(copies, ['lights']);
    expect(taps, 0);
    expect(selection(tester).selecting, isFalse);
  });

  testWidgets('dragging the end handle into the next paragraph extends the '
      'selection across both, and Copy reports their text with a line break '
      'between them and the book\'s white space as one space', (tester) async {
    await read(tester, _harbourBook());
    await tester.longPressAt(pointOf('lights', 2));
    await tester.pumpAndSettle();
    final end = boxOf('lights', 5);
    final target = boxOf('boat', 3);

    // The end handle hangs below the end of the selection, and the end
    // follows it by the same move.
    final finger = await tester.startGesture(
      Offset(end.right + 4, end.bottom + 10),
    );
    await tester.pump();
    final move = Offset(target.right - 1, target.bottom) - end.bottomRight;
    for (var step = 1; step <= 10; step++) {
      await finger.moveBy(move / 10);
      await tester.pump();
    }
    await finger.up();
    await tester.pumpAndSettle();
    selection(tester);
    await choose(tester, 'Copy');

    expect(copies, ['lights came on at dusk.\nEvery boat']);
    expect(turns, isEmpty);
  });

  testWidgets('the copied text is the book\'s own text: a hyphenated word '
      'and a word with the book\'s soft hyphen copy whole, without the '
      'hyphens that layout draws', (tester) async {
    await read(tester, _hyphenatedBook(), size: const Size(240, 671));

    // The narrow page has no room for Select all in the menu, so a
    // keyboard selects the page and copies it.
    await tester.longPressAt(pointOf('harbour', 1));
    await tester.pumpAndSettle();
    await shortcut(tester, LogicalKeyboardKey.keyA);
    await shortcut(tester, LogicalKeyboardKey.keyC);

    final copied = copies.single;
    expect(copied, isNot(matches(RegExp('[­‐⁠]'))));
    expect(copied, contains('incomprehensibility unquestionably'));
    expect(copied, contains('the cooperation of'));
    expect(copied.replaceAll(RegExp(r'\s'), ''), pageText());
  });

  testWidgets('a tap with a selection clears it and does not call onTap, and '
      'the next tap does', (tester) async {
    await read(tester, _harbourBook());
    await tester.longPressAt(pointOf('lights', 2));
    await tester.pumpAndSettle();

    await tester.tapAt(pointOf('pier', 1));
    await tester.pumpAndSettle();

    expect(taps, 0);
    expect(find.text('Copy'), findsNothing);
    expect(region(tester).selectionOverlay, isNull);
    await shortcut(tester, LogicalKeyboardKey.keyC);
    expect(copies, isEmpty);

    await tester.tapAt(pointOf('pier', 1));
    expect(taps, 1);
  });

  testWidgets('a swipe with a selection does not turn the page, and keeps '
      'the selection', (tester) async {
    await read(tester, _harbourBook());
    await tester.longPressAt(pointOf('lights', 2));
    await tester.pumpAndSettle();

    await tester.dragFrom(const Offset(206, 400), const Offset(-120, 0));
    await tester.pumpAndSettle();

    expect(turns, isEmpty);
    await shortcut(tester, LogicalKeyboardKey.keyC);
    expect(copies, ['lights']);
  });

  testWidgets('a page turn clears the selection and its handles', (
    tester,
  ) async {
    await read(tester, _harbourBook());
    await tester.longPressAt(pointOf('lights', 2));
    await tester.pumpAndSettle();
    expect(region(tester).selectionOverlay, isNotNull);
    final first = shown().page;

    unawaited(pager().move(true));
    await settle(tester, () => !identical(shown().page, first));

    expect(region(tester).selectionOverlay, isNull);
    expect(selection(tester).selecting, isFalse);
    await shortcut(tester, LogicalKeyboardKey.keyC);
    expect(copies, isEmpty);
    await tester.tapAt(const Offset(206, 335));
    expect(taps, 1);
  });

  testWidgets('a long press on a link selects its word and follows nothing, '
      'and a tap on the link still follows it', (tester) async {
    await read(
      tester,
      book([
        '<p>Before the link. <a href="s1.xhtml#target">Follow the '
            'lantern</a> after the link.</p>',
        '<p id="target">The target.</p>',
      ]),
    );

    await tester.longPressAt(pointOf('lantern', 2));
    await tester.pumpAndSettle();
    await choose(tester, 'Copy');

    expect(copies, ['lantern']);
    expect(links, isEmpty);
    await tester.tapAt(pointOf('lantern', 2));
    expect(links, ['text/s1.xhtml#target']);
  });

  testWidgets('a long press that moves before it lifts extends the selection '
      'by whole words', (tester) async {
    await read(tester, _harbourBook());

    final finger = await tester.startGesture(pointOf('lights', 2));
    await tester.pump(const Duration(milliseconds: 600));
    await finger.moveTo(pointOf('dusk', 1));
    await tester.pump();
    await finger.up();
    await tester.pumpAndSettle();
    await choose(tester, 'Copy');

    expect(copies, ['lights came on at dusk']);
    expect(turns, isEmpty);
  });

  testWidgets('a selection that starts between a letter and the hyphen that '
      'layout draws after it copies neither the letter nor the hyphen', (
    tester,
  ) async {
    await read(tester, _hyphenatedBook(), size: const Size(240, 671));
    final page = shown().page;
    final dom = source.sectionOf(page).dom;
    final lines = textLines(page);
    // A line whose last code unit is a hyphen that layout drew: it maps to
    // the letter before it.
    final split = lines.indexWhere((line) {
      final map = line.piece!.map;
      final (first, end) = line.units;
      final last = map.textPlaceAt(end - 1);
      return end - first > 1 &&
          last != null &&
          last == map.textPlaceAt(end - 2) &&
          RegExp('[a-z]').hasMatch(dom.textAt(last)!.text[last.offset]);
    });
    expect(split, isNot(-1), reason: 'No line of the page breaks in a word.');
    final line = lines[split];
    final next = lines[split + 1];
    final after = next.piece!.map.textPlaceAt(next.units.$1)!;
    final word = dom
        .textAt(after)!
        .text
        .substring(after.offset, after.offset + 3);

    final text = selectedText(
      page,
      lines,
      PageCaret(split, line.units.$2 - 1),
      PageCaret(split + 1, next.units.$1 + 3),
    );

    expect(text, word);
  });

  testWidgets(
    'on a desktop, a mouse drag selects across paragraphs, and the copy '
    'shortcut reports the same text',
    (tester) async {
      await read(tester, _harbourBook());
      final from = boxOf('lights');
      final to = boxOf('boat', 3);

      await tester.dragFrom(
        Offset(from.left + 1, from.center.dy),
        Offset(to.right - 1, to.center.dy) -
            Offset(from.left + 1, from.center.dy),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      await shortcut(tester, LogicalKeyboardKey.keyC);

      expect(copies, ['lights came on at dusk.\nEvery boat']);
      expect(turns, isEmpty);
      expect(taps, 0);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.linux,
      TargetPlatform.windows,
    }),
  );

  testWidgets(
    'on a desktop, the select all shortcut selects the page, and the copy '
    'shortcut reports its text',
    (tester) async {
      await read(tester, _harbourBook());

      await tester.tapAt(pointOf('pier', 1));
      await shortcut(tester, LogicalKeyboardKey.keyA);
      await shortcut(tester, LogicalKeyboardKey.keyC);

      final copied = copies.single;
      expect(
        copied,
        startsWith(
          'The harbour\nThe harbour lights came on at dusk.\n'
          'Every boat turned toward the pier.\nPart 0 passage 1.',
        ),
      );
      expect(copied.replaceAll(RegExp(r'\s'), ''), pageText());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
