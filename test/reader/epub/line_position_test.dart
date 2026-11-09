// Lines sit at their exact CSS positions, as Chromium places them, at every
// text size. Flutter rounds each line's height to a whole pixel, so layout
// keeps the exact positions itself (tc-n6wv).
import 'dart:ui' as ui;

import 'package:bookfin/reader/epub/layout.dart';
import 'package:bookfin/reader/epub/paint.dart';
import 'package:bookfin/reader/epub/prepare.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'helpers.dart';

/// A page at [fontSize] pixels, [height] pixels high.
PageSettings pageOf(double fontSize, {double height = 671}) =>
    PageSettings(width: 412, height: height, fontSize: fontSize, night: false);

/// The line slices of [chapter], in order.
List<Slice> linesOf(ChapterLayout chapter) => [
  for (final slice in chapter.slices)
    if (slice.piece != null) slice,
];

/// The bands of rows of [page] that hold ink, as [top, bottom) rows.
Future<List<(int, int)>> inkBands(LaidPage page) async {
  final picture = drawPage(page, const {});
  final width = page.settings.width.round();
  final height = page.settings.height.round();
  final image = await picture.toImage(width, height);
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  image.dispose();
  picture.dispose();
  final paper = page.settings.paper;
  bool inked(int row) {
    for (var column = 0; column < width; column++) {
      final red = bytes.getUint8((row * width + column) * 4);
      if ((red - (paper.r * 255).round()).abs() > 60) return true;
    }
    return false;
  }

  final bands = <(int, int)>[];
  int? start;
  for (var row = 0; row <= height; row++) {
    final ink = row < height && inked(row);
    if (ink && start == null) start = row;
    if (!ink && start != null) {
      bands.add((start, row));
      start = null;
    }
  }
  return bands;
}

void main() {
  setUpAll(loadReaderFont);

  test('at 23 pixels the lines of a body paragraph start 37.95 pixels '
      'apart', () async {
    final chapter = await lay('<p>${prose(6)}</p>', settings: pageOf(23));
    final lines = linesOf(chapter);
    expect(lines.length, greaterThan(5));
    for (var line = 1; line < lines.length; line++) {
      expect(lines[line].top - lines[line - 1].top, closeTo(37.95, 1e-6));
      expect(lines[line].top, lines[line - 1].bottom);
    }
    chapter.dispose();
  });

  test('a two-line heading at 30 pixels is 99 pixels high, as Chromium '
      'makes it', () async {
    final chapter = await lay(
      '<h2>A heading that is long enough to take two lines</h2>',
    );
    final lines = linesOf(chapter);
    expect(lines, hasLength(2));
    expect(lines.last.bottom - lines.first.top, closeTo(99, 1e-6));
    chapter.dispose();
  });

  test('a line that holds a tall image grows to hold it, and the lines '
      'after it keep their exact height', () async {
    final chapter = await lay(
      '<p>A map <img src="map.png" style="height:60px;width:20px"/> of the '
      'harbour, drawn by the reader who followed the shoreline and watched '
      'the small boats return to the quay at dusk.</p>',
      settings: pageOf(23),
      files: {'text/map.png': img.encodePng(img.Image(width: 20, height: 60))},
    );
    final lines = linesOf(chapter);
    expect(lines.length, greaterThan(2));
    expect(lines.first.bottom - lines.first.top, greaterThan(60));
    for (final line in lines.skip(1)) {
      expect(line.bottom - line.top, closeTo(37.95, 1e-6));
    }
    chapter.dispose();
  });

  test('a page holds every line that fits at the exact line height', () async {
    // 18 lines are 683.1 pixels high at 23 pixels, but 684 when Flutter
    // rounds each to 38.
    final chapter = await lay(
      '<p>${prose(12)}</p>',
      css: 'p{margin:0}',
      settings: pageOf(23, height: 683.5),
    );
    expect(chapter.pages.first.slices, hasLength(18));
    chapter.dispose();
  });

  test('each line draws on its exact baseline', () async {
    // At 21 pixels a line is 34.65 pixels high, which Flutter rounds to 35,
    // so a line drawn where Flutter puts it sinks a third of a pixel more
    // with each line. Letters without ascenders or descenders put each
    // line's ink right above its baseline.
    final chapter = await lay(
      '<p>${List.filled(400, 'xxx').join(' ')}</p>',
      css: 'p{margin:0;text-align:left}',
      settings: pageOf(21),
    );
    final page = chapter.pages.first;
    final lines = page.slices;
    expect(lines.length, greaterThan(15));
    final bands = await inkBands(page);
    expect(bands, hasLength(lines.length));
    // Each line's ink ends at most a pixel from the first line's end plus
    // a whole number of exact line heights.
    final first = bands.first.$2;
    for (final (index, band) in bands.indexed) {
      expect(
        band.$2,
        closeTo(first + index * 34.65, 1),
        reason: 'line $index ink ends at row ${band.$2}',
      );
    }
    chapter.dispose();
  });
}
