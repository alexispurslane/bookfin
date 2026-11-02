import 'dart:convert';
import 'dart:io';

import 'package:markdown/markdown.dart' as markdown;
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:test/test.dart';

void main() {
  final enabled = Platform.environment['BOOKFIN_REAL_CORPUS'] == '1';
  final observations = <String, Object?>{};
  group(
    'Public-source PDF and Markdown observations',
    () {
      setUpAll(() async {
        Pdfrx.pdfiumModulePath = Platform.environment['PDFIUM_LIBRARY'];
        await pdfrxInitialize();
      });
      tearDownAll(() {
        if (enabled) {
          File('../_out/corpus/dart-pdf-observations.json').writeAsStringSync(
            '${const JsonEncoder.withIndent('  ').convert(observations)}\n',
          );
        }
      });
      for (final entry in {
        'nist-cloud.pdf': (7, 4, 'cloud computing'),
        'census-notice.pdf': (2, 0, 'nominations'),
        'raven-1873.pdf': (24, 8, 'Nevermore'),
      }.entries) {
        test(
          '${entry.key} retains source text and renders its complete sampled page',
          () async {
            final document = await PdfDocument.openFile(
              '../_out/corpus/originals/${entry.key}',
            );
            try {
              final counts = <int>[];
              final text = StringBuffer();
              for (final page in document.pages) {
                final extracted = await page.loadText();
                counts.add(extracted!.fullText.length);
                text.write(extracted.fullText);
              }
              final page = document.pages[entry.value.$2];
              final image = await page.render(
                fullWidth: 360,
                fullHeight: page.height * 360 / page.width,
              );
              try {
                final phrasePresent = text.toString().toLowerCase().contains(
                  entry.value.$3.toLowerCase(),
                );
                observations[entry.key] = {
                  'pages': document.pages.length,
                  'text_characters_by_page': counts,
                  'expected_phrase': entry.value.$3,
                  'expected_phrase_present': phrasePresent,
                  'sampled_page_1_based': entry.value.$2 + 1,
                  'rendered_pixels': [image!.width, image.height],
                  'has_nonwhite_pixels': image.pixels.any(
                    (value) => value < 200,
                  ),
                };
                expect(document.pages.length, entry.value.$1);
                expect(phrasePresent, isTrue);
                expect(image.width, 360);
                expect(
                  image.height / image.width,
                  closeTo(page.height / page.width, 0.01),
                );
                expect(image.pixels.any((value) => value < 200), isTrue);
              } finally {
                image?.dispose();
              }
            } finally {
              await document.dispose();
            }
          },
        );
      }
      test('a raster-only derivative of the real scan renders without extracted text', () async {
        final document = await PdfDocument.openFile(
          '../_out/corpus/raven-raster-only.pdf',
        );
        try {
          final page = document.pages.single;
          final extracted = await page.loadText();
          final image = await page.render(
            fullWidth: 360,
            fullHeight: page.height * 360 / page.width,
          );
          try {
            observations['raven-raster-only.pdf'] = {
              'text_characters': extracted!.fullText.trim().length,
              'has_nonwhite_pixels': image!.pixels.any((value) => value < 200),
            };
            expect(extracted.fullText.trim(), isEmpty);
            expect(image.pixels.any((value) => value < 200), isTrue);
          } finally {
            image?.dispose();
          }
        } finally {
          await document.dispose();
        }
      });
      test(
        'the real sonnet source retains verse line breaks in fenced Markdown',
        () {
          final source = File('../_out/corpus/sonnets.md').readAsStringSync();
          final rendered = markdown.markdownToHtml(
            source,
            extensionSet: markdown.ExtensionSet.gitHubFlavored,
          );
          observations['sonnets.md'] = {
            'rendered_html_characters': rendered.length,
            'contains_sonnet_18': rendered.contains(
              'Shall I compare thee to a summer',
            ),
            'preserves_adjacent_verse_lines': rendered.contains(
              'lovely and more temperate:\n',
            ),
          };
          expect(rendered, contains('<h1>Shakespeare'));
          expect(rendered, contains('<pre><code class="language-text">'));
          expect(rendered, contains('Shall I compare thee to a summer'));
          expect(rendered, contains('lovely and more temperate:\n'));
        },
      );
    },
    skip: enabled ? false : 'Set BOOKFIN_REAL_CORPUS=1 after acquiring and probing the public corpus',
  );
}
