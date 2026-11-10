import 'package:bookfin/reader/column_layout.dart';
import 'package:bookfin/reader/pdf.dart';
import 'package:bookfin/reader/word_selection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

WordScreenText fixture({int screen = 0}) {
  final column = ReflowColumn(
    width: 240,
    screenHeight: 40,
    scale: 1,
    pieces: Float32List.fromList([
      0,
      0,
      100,
      20,
      0,
      0,
      100,
      20,
      0,
      110,
      0,
      120,
      20,
      110,
      0,
      120,
      20,
      0,
      140,
      0,
      220,
      20,
      140,
      0,
      220,
      20,
      0,
      0,
      50,
      100,
      70,
      0,
      50,
      100,
      70,
      0,
    ]),
    pieceItems: Int32List.fromList([0, 1, 2, 3]),
    lineStarts: Int32List.fromList([0, 3, 4]),
    lineExtents: Float32List.fromList([0, 18, 20, 50, 68, 70]),
    screenStarts: Int32List.fromList([0, 1, 2]),
  );
  final page = WordPageText(
    (
      text: const PdfText(
        source: '  alpha \n beta\ngamma',
        text: 'alpha beta gamma',
        sourceOffsets: [
          2,
          3,
          4,
          5,
          6,
          7,
          10,
          11,
          12,
          13,
          14,
          15,
          16,
          17,
          18,
          19,
        ],
        status: PdfTextStatus.candidate,
        digest: 'fixture',
      ),
      attachment: Int32List.fromList([2, 7, 7, 7, 10, 14, 15, 20]),
    ),
    (paragraphs: [(2, 14), (15, 20)], regions: []),
  );
  return WordScreenText(page, column, screen);
}

void main() {
  test('a caret shared by two printed lines anchors the handle to its selected side', () {
    final page = WordPageText(
      (
        text: const PdfText(
          source: 'alphabeta',
          text: 'alphabeta',
          sourceOffsets: [0, 1, 2, 3, 4, 5, 6, 7, 8],
          status: PdfTextStatus.candidate,
          digest: 'joined-word',
        ),
        attachment: Int32List.fromList([0, 5, 5, 9]),
      ),
      (paragraphs: [(0, 9)], regions: []),
    );
    final column = ReflowColumn(
      width: 240,
      screenHeight: 60,
      scale: 1,
      pieces: Float32List.fromList([
        0,
        0,
        .5,
        .1,
        0,
        0,
        100,
        20,
        0,
        0,
        .2,
        .4,
        .3,
        0,
        30,
        80,
        50,
        0,
      ]),
      pieceItems: Int32List.fromList([0, 1]),
      lineStarts: Int32List.fromList([0, 1, 2]),
      lineExtents: Float32List.fromList([0, 18, 20, 30, 48, 50]),
      screenStarts: Int32List.fromList([0, 2]),
    );
    final screen = WordScreenText(page, column, 0);
    expect(screen.pointAt(5, true).localPosition, const Offset(0, 50));
    expect(screen.pointAt(5, false).localPosition, const Offset(100, 20));
  });

  test(
    'a whole region shares its attached reading text and character rectangles',
    () {
      final words = fixture().page;
      final page = WordPageText(words.attached, (
        paragraphs: words.plan.paragraphs,
        regions: [(2, 14)],
      ));
      final column = ReflowColumn(
        width: 240,
        screenHeight: 40,
        scale: 1,
        pieces: Float32List.fromList([0, 0, 1, .2, 0, 0, 240, 20, 0]),
        pieceItems: Int32List.fromList([-1]),
        lineStarts: Int32List.fromList([0, 1]),
        lineExtents: Float32List.fromList([0, 18, 20]),
        screenStarts: Int32List.fromList([0, 1]),
      );
      final screen = WordScreenText(page, column, 0);
      expect(screen.rangeAt(const Offset(220, 10), TextGranularity.word), (
        10,
        14,
      ));
      expect(screen.rectsFor(10, 14), [const Rect.fromLTRB(160, 0, 240, 20)]);
      expect(screen.paragraphs.single.text, 'alpha beta');
    },
  );

  test('a screen of empty attachment ranges has no selectable content or paragraph labels', () {
    final original = fixture();
    final page = WordPageText(
      (text: original.page.attached.text, attachment: Int32List(8)),
      (paragraphs: [], regions: []),
    );
    final screen = WordScreenText(page, original.column, 0);
    expect(screen.extent, isNull);
    expect(screen.caretAt(const Offset(50, 10)), isNull);
    expect(screen.rangeAt(const Offset(50, 10), TextGranularity.word), isNull);
    expect(screen.rectsFor(0, 20), isEmpty);
    expect(screen.paragraphs, isEmpty);
  });

  test(
    'a point divides the printed word evenly into reading-text characters',
    () {
      final screen = fixture();
      expect(screen.caretAt(const Offset(30, 10)), 4);
      expect(screen.caretAt(const Offset(130, 10)), 10);
      expect(screen.rangeAt(const Offset(70, 10), TextGranularity.word), (
        2,
        7,
      ));
    },
  );

  test('unattached ink is never a word or a highlighted rectangle', () {
    final screen = fixture();
    expect(screen.rangeAt(const Offset(115, 10), TextGranularity.word), isNull);
    expect(screen.rectsFor(7, 10), isEmpty);
    expect(screen.rectsFor(2, 14), [
      const Rect.fromLTRB(0, 0, 100, 20),
      const Rect.fromLTRB(140, 0, 220, 20),
    ]);
  });

  test(
    'read-aloud rectangles cover only the requested characters of each piece',
    () {
      final screen = fixture();
      expect(screen.rectsFor(3, 5), [const Rect.fromLTRB(20, 0, 60, 20)]);
      expect(screen.rectsFor(12, 6), [
        const Rect.fromLTRB(80, 0, 100, 20),
        const Rect.fromLTRB(140, 0, 180, 20),
      ]);
      expect(screen.rectsFor(4, 4), isEmpty);
      expect(fixture(screen: 1).rectsFor(16, 19), [
        const Rect.fromLTRB(20, 0, 80, 20),
      ]);
    },
  );

  test('copy uses reading text rather than source line breaks and spacing', () {
    final screen = fixture();
    expect(screen.textBetween(2, 14), 'alpha beta');
    expect(screen.textBetween(12, 4), 'pha be');
  });

  test(
    'paragraph labels contain only the reading text shown on their screen',
    () {
      expect(fixture().paragraphs.map((paragraph) => paragraph.text), [
        'alpha beta',
      ]);
      expect(fixture(screen: 1).paragraphs.map((paragraph) => paragraph.text), [
        'gamma',
      ]);
    },
  );

  testWidgets(
    'character handles move within a printed word and reverse across each other',
    (tester) async {
      final text = ValueNotifier<WordScreenText?>(fixture());
      addTearDown(text.dispose);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: WordSelectable(
            text: text,
            child: const SizedBox(width: 240, height: 40),
          ),
        ),
      );
      final box = tester.renderObject<RenderWordSelectable>(
        find.byType(WordSelectable),
      );
      final selection = box.selection;
      selection.dispatchSelectionEvent(
        SelectWordSelectionEvent(
          globalPosition: box.localToGlobal(const Offset(40, 10)),
        ),
      );
      expect(selection.text, 'alpha');
      selection.dispatchSelectionEvent(
        SelectionEdgeUpdateEvent.forStart(
          globalPosition: box.localToGlobal(const Offset(20, 10)),
          granularity: TextGranularity.character,
        ),
      );
      selection.dispatchSelectionEvent(
        SelectionEdgeUpdateEvent.forEnd(
          globalPosition: box.localToGlobal(const Offset(80, 10)),
          granularity: TextGranularity.character,
        ),
      );
      expect(selection.text, 'lph');
      expect(selection.rects, [const Rect.fromLTRB(20, 0, 80, 20)]);
      selection.dispatchSelectionEvent(
        SelectionEdgeUpdateEvent.forStart(
          globalPosition: box.localToGlobal(const Offset(180, 10)),
          granularity: TextGranularity.character,
        ),
      );
      expect(selection.text, 'a be');
      selection.checkInvariants();
      text.value = fixture(screen: 1);
      expect(selection.text, isNull);
      expect(selection.rects, isEmpty);
      selection.checkInvariants();
      await tester.pumpWidget(const SizedBox());
    },
  );
}
