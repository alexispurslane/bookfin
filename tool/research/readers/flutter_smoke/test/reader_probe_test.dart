import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_packaging_probe/reader_probe.dart';
import 'package:reader_packaging_probe/license_text.dart';

void main() {
  test('a UTF-8 license preserves its copyright symbol and non-Latin text', () {
    expect(decodeLicense([0xc2, 0xa9, 32, 0xe6, 0x96, 0x87]), '© 文');
  });

  test('a Latin-1 license preserves its copyright symbol', () {
    expect(decodeLicense([67, 32, 0xa9, 32, 50, 48, 50, 54]), 'C © 2026');
  });

  const paragraph =
      'The river follows the old road. '
      'A reader can change the text size without changing the saved source location.';

  testWidgets('narrow reflow wraps text into more lines without shrinking it', (
    tester,
  ) async {
    Future<RenderParagraph> renderAt(double width) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReflowPage(
              text: paragraph,
              width: width,
              sourcePage: 2,
              sourceCharacter: 39,
              onSource: () {},
            ),
          ),
        ),
      );
      return tester.renderObject<RenderParagraph>(find.text(paragraph));
    }

    final wide = await renderAt(360);
    final wideHeight = wide.size.height;
    final wideFontSize = wide.text.style!.fontSize;
    final narrow = await renderAt(200);
    expect(narrow.size.height, greaterThan(wideHeight));
    expect(narrow.text.style!.fontSize, wideFontSize);
    expect(narrow.text.toPlainText(), paragraph);
  });

  testWidgets(
    'a source link returns to the page that supplied the reflow text',
    (tester) async {
      var returnedPage = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReflowPage(
              text: paragraph,
              width: 360,
              sourcePage: 2,
              sourceCharacter: 39,
              onSource: () {
                returnedPage = 2;
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('Source page 2, character 39'));
      expect(returnedPage, 2);
    },
  );
}
