import 'dart:io';
import 'dart:ui' as ui;

import 'package:bookfin/reader/epub/layout.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  setUpAll(() async {
    await loadReaderFont();
    await ui.loadFontFromList(
      File('assets/fonts/NotoSansMath-Arrows.ttf').readAsBytesSync(),
      fontFamily: arrowFontFamily,
    );
  });

  /// The width of [text] drawn in [family] at the reader page's text size.
  double widthIn(String family, String text) {
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(fontFamily: family))
      ..pushStyle(
        ui.TextStyle(fontFamily: family, fontSize: readerPage.fontSize),
      )
      ..addText(text);
    final paragraph = builder.build()
      ..layout(const ui.ParagraphConstraints(width: double.infinity));
    final width = paragraph.maxIntrinsicWidth;
    paragraph.dispose();
    return width;
  }

  /// The width of the character at [index] of the first paragraph of the
  /// page that [body] lays out to.
  Future<double> drawnWidth(String body, int index) async {
    final layout = await lay(body);
    final paragraph = layout.pages.first.pieces.first.paragraph;
    final boxes = paragraph.getBoxesForRange(index, index + 1);
    return boxes.single.right - boxes.single.left;
  }

  test('an arrow that the reader font lacks, such as the leftwards arrow '
      'with hook of a back link, draws as a text glyph of the bundled '
      'arrow font, not as a color emoji', () async {
    for (final arrow in ['↩', '↪', '⤴']) {
      expect(
        await drawnWidth('<p>Back $arrow</p>', 5),
        moreOrLessEquals(widthIn(arrowFontFamily, arrow), epsilon: 0.01),
        reason: 'U+${arrow.codeUnitAt(0).toRadixString(16)}',
      );
    }
  });

  test('an arrow that the reader font has keeps the reader font, so the '
      'arrow font comes after it', () async {
    final drawn = await drawnWidth('<p>Next →</p>', 5);
    expect(
      (drawn - widthIn(arrowFontFamily, '→')).abs(),
      greaterThan(1),
      reason: 'The arrow font draws a wider rightwards arrow.',
    );
  });
}
