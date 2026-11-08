import 'dart:io';
import 'dart:ui' as ui;

import 'package:bookfin/reader/epub/layout.dart';
import 'package:bookfin/reader/epub/paint.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// Every line slice of [chapter] that shows text, in order, with the
/// index of the page that holds it.
List<(int, Slice)> linesByPage(ChapterLayout chapter) => [
  for (var page = 0; page < chapter.pages.length; page++)
    for (
      var index = chapter.pages[page].firstSlice;
      index < chapter.pages[page].endSlice;
      index++
    )
      (page, chapter.slices[index]),
];

/// The text node that page [index] of [chapter] starts in.
String startText(ChapterLayout chapter, int index) =>
    chapter.section.dom.textAt(chapter.pages[index].start!)!.text;

void main() {
  setUpAll(loadReaderFont);

  test('a short paragraph fits on one page', () async {
    final chapter = await lay('<p>${prose(2)}</p>');
    expect(chapter.pages, hasLength(1));
  });

  test('a long chapter splits a paragraph between two of its lines', () async {
    final chapter = await lay('<p>${prose(60)}</p>');
    expect(chapter.pages.length, greaterThan(1));
    final first = chapter.pages[0];
    final second = chapter.pages[1];
    final last = chapter.slices[first.endSlice - 1];
    final next = chapter.slices[second.firstSlice];
    expect(identical(last.piece, next.piece), isTrue);
    expect(next.line, last.line + 1);
  });

  test('every page holds whole lines that fit its height', () async {
    final chapter = await lay(
      [for (var i = 0; i < 30; i++) '<p>${prose(3)}</p>'].join(),
    );
    for (final page in chapter.pages) {
      for (var index = page.firstSlice; index < page.endSlice; index++) {
        final slice = chapter.slices[index];
        expect(slice.top, greaterThanOrEqualTo(page.startY - 0.01));
        expect(slice.bottom, lessThanOrEqualTo(page.startY + 671.01));
      }
    }
    // The pages cover the slices once, in order.
    expect(chapter.pages.first.firstSlice, 0);
    for (var page = 1; page < chapter.pages.length; page++) {
      expect(chapter.pages[page].firstSlice, chapter.pages[page - 1].endSlice);
    }
    expect(chapter.pages.last.endSlice, chapter.slices.length);
  });

  // At 20 pixels and line height 1.65 a line is 33 pixels high, and a 671
  // pixel page holds 20 lines.
  String filler(int lines) =>
      [for (var i = 0; i < lines; i++) '<p>Line $i.</p>'].join();
  String fiveLines() =>
      [for (var i = 0; i < 5; i++) '<span>Verse line $i</span>'].join('<br/>');
  const tight = 'p{margin:0;text-align:left}';

  test(
    'a paragraph moves to the next page rather than leave one line',
    () async {
      final chapter = await lay(
        '${filler(19)}<p>${fiveLines()}</p>',
        css: tight,
      );
      expect(chapter.pages, hasLength(2));
      expect(startText(chapter, 1), 'Verse line 0');
    },
  );

  test(
    'a split paragraph leaves at least two lines for the next page',
    () async {
      final chapter = await lay(
        '${filler(16)}<p>${fiveLines()}</p>',
        css: tight,
      );
      expect(chapter.pages, hasLength(2));
      // Four lines would fit, but then one would be left alone.
      expect(startText(chapter, 1), 'Verse line 3');
    },
  );

  test('a three-line paragraph leaves one line, as Chromium does', () async {
    // Two lines fit. Keeping two lines on each page is impossible, and
    // Chromium then keeps the orphans rule and drops the widows rule.
    final verse = [for (var i = 0; i < 3; i++) '<span>Verse line $i</span>']
        .join('<br/>');
    final chapter = await lay('${filler(18)}<p>$verse</p>', css: tight);
    expect(startText(chapter, 1), 'Verse line 2');
  });

  test('page breaks are ignored, as in the WebView columns', () async {
    final chapter = await lay(
      '<p>Before the break.</p><p class="new">After the break.</p>',
      css: '.new{page-break-before:always}',
    );
    expect(chapter.pages, hasLength(1));
  });

  test(
    'a heading that avoids a break after it moves with its paragraph',
    () async {
      // The heading's 49.5 pixel line still fits after 18 lines, but the
      // paragraph's first line does not.
      final chapter = await lay(
        '${filler(18)}<h2>Heading</h2><p>${prose(4)}</p>',
        css: '$tight h2{margin:0;break-after:avoid}',
      );
      expect(startText(chapter, 1), 'Heading');
    },
  );

  test('a heading without that rule stays at the bottom of the page', () async {
    final chapter = await lay(
      '${filler(18)}<h2>Heading</h2><p>${prose(4)}</p>',
      css: '$tight h2{margin:0}',
    );
    expect(startText(chapter, 1), startsWith('Harbour'));
  });

  test('white space between blocks makes no lines', () async {
    final chapter = await lay('\n\t<p>One.</p>\n\t\n\t<p>Two.</p>\n');
    expect(chapter.slices, hasLength(2));
  });

  test('content that is not displayed takes no space', () async {
    final shown = await lay('<p>One.</p><p>Two.</p>');
    final hidden = await lay(
      '<p>One.</p><p style="display:none">${prose(40)}</p><p>Two.</p>',
    );
    expect(hidden.slices, hasLength(shown.slices.length));
    expect(hidden.slices.last.top, shown.slices.last.top);
  });

  test('vertical margins of neighbors collapse to the larger one', () async {
    final chapter = await lay(
      '<p>One.</p><p class="far">Two.</p>',
      css: 'p{margin:10px 0} .far{margin-top:30px}',
    );
    final [first, second] = chapter.slices;
    expect(second.top - first.bottom, closeTo(30, 0.01));
  });

  test('the margin at an unforced page break is dropped', () async {
    final chapter = await lay(
      [for (var i = 0; i < 30; i++) '<p>Line $i.</p>'].join(),
      css: 'p{margin:0 0 40px}',
    );
    expect(chapter.pages.length, greaterThan(1));
    final second = chapter.pages[1];
    expect(chapter.slices[second.firstSlice].top, second.startY);
  });

  test('text-indent moves only the first line', () async {
    final chapter = await lay(
      '<p>${prose(6)}</p>',
      css: 'p{text-indent:2em;text-align:left}',
    );
    final paragraph = chapter.slices.first.piece!.paragraph;
    final lines = paragraph.computeLineMetrics();
    expect(lines[0].left, closeTo(0, 0.5));
    // The first line starts after a 40 pixel indent placeholder.
    final box = paragraph.getBoxesForPlaceholders().single;
    expect(box.right - box.left, closeTo(40, 0.01));
    expect(lines[1].left, closeTo(0, 0.5));
  });

  test('a hanging indent puts the first line left of the others', () async {
    final chapter = await lay(
      '<p class="verse">${prose(3)}</p>',
      css: '.verse{padding-left:2em;text-indent:-2em;text-align:left}',
    );
    final first = chapter.slices.first.piece!;
    final rest = chapter.slices[1].piece!;
    expect(rest.x - first.x, closeTo(40, 0.01));
    expect(chapter.slices[1].start, isNotNull);
    // The hanging line's paragraph shows only that line, so its other
    // lines do not draw over the rest.
    expect(first.shown, chapter.slices[0].bottom - chapter.slices[0].top);
    expect(rest.shown, double.infinity);
  });

  test('an image wider than the page shrinks to the text width', () async {
    final png = File('tool/research/readers/fixtures/dot.png')
        .readAsBytesSync();
    final chapter = await lay(
      '<p><img src="big.png" style="width:900px"/></p>',
      files: {'text/big.png': png},
    );
    final (box, _) = chapter.slices.single.piece!.inlines.single;
    expect(box.width, closeTo(412 - 34, 0.5));
  });

  test('list items draw a marker left of their first line', () async {
    final chapter = await lay('<ol><li>First.</li><li>Second.</li></ol>');
    final markers = chapter.decorations.whereType<MarkerDecoration>().toList();
    expect(markers, hasLength(2));
    expect(markers.first.offset.dx, lessThan(chapter.slices.first.piece!.x));
  });

  test('a page draws into a picture of the page size', () async {
    final chapter = await lay('<h1>Title</h1><p>${prose(30)}</p>');
    final picture = drawPage(chapter, chapter.pages.length - 1, const {});
    final image = await picture.toImage(412, 671);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    // Some pixels are ink, not paper.
    final pixels = bytes!.buffer.asUint32List();
    expect(pixels.toSet().length, greaterThan(2));
    image.dispose();
    picture.dispose();
  });
}
