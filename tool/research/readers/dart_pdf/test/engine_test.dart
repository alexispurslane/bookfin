import 'dart:io';

import 'package:markdown/markdown.dart' as markdown;
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(() async {
    Pdfrx.pdfiumModulePath = Platform.environment['PDFIUM_LIBRARY'];
    await pdfrxInitialize();
  });

  test('PDF text exposes the source page character rectangles', () async {
    final document = await PdfDocument.openFile('../fixtures/simple.pdf');
    try {
      expect(document.pages.length, 2);
      final text = await document.pages.first.loadText();
      expect(text!.fullText, contains('The river follows the old road.'));
      expect(text.charRects.length, text.fullText.length);
      final character = text.fullText.indexOf('old road');
      expect(text.charRects[character].width, greaterThan(0));
    } finally {
      await document.dispose();
    }
  });

  test(
    'PDF original pages render without extracting text from a scan',
    () async {
      final document = await PdfDocument.openFile('../fixtures/scanned.pdf');
      try {
        final page = document.pages.first;
        expect((await page.loadText())!.fullText.trim(), isEmpty);
        final image = await page.render(
          fullWidth: 360,
          fullHeight: page.height * 360 / page.width,
        );
        expect(image, isNotNull);
        try {
          expect(image!.pixels.any((value) => value < 200), isTrue);
          final markerOffset = (430 * image.width + 336) * 4;
          expect(image.pixels[markerOffset], lessThan(200));
          await Directory('../_out').create(recursive: true);
          await File('../_out/scanned-original.ppm').writeAsBytes([
            ...'P6\n${image.width} ${image.height}\n255\n'.codeUnits,
            for (var offset = 0; offset < image.pixels.length; offset += 4) ...[
              image.pixels[offset + 2],
              image.pixels[offset + 1],
              image.pixels[offset],
            ],
          ]);
        } finally {
          image!.dispose();
        }
      } finally {
        await document.dispose();
      }
    },
  );

  test('Markdown preserves readable structure and local image references', () {
    final source = File('../fixtures/chapter.md').readAsStringSync();
    final html = markdown.markdownToHtml(source);
    expect(html, contains('<h1>River chapter</h1>'));
    expect(html, contains('<li>Follow the river</li>'));
    expect(html, contains('src="dot.png"'));
    expect(html, contains('<pre><code'));
    expect(html, contains('<script>'));
  });
}
