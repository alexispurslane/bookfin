import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/ocr.dart';
import 'package:bookfin/reader/page_geometry.dart';
import 'package:bookfin/reader/pdf.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pdf_navigation_test.dart' show HeldPdf;

/// The layout record that the fixture file [name] keeps: one entry a line,
/// its nine numbers separated by spaces.
Int32List layoutFixture(String name) => Int32List.fromList([
  for (final line in File(
    'test/reader/fixtures/reflow/$name.layout',
  ).readAsLinesSync())
    if (line.trim().isNotEmpty) ...line.trim().split(' ').map(int.parse),
]);

/// The hOCR that the fixture file [name] keeps.
String hocrFixture(String name) =>
    File('test/reader/fixtures/reflow/$name.hocr').readAsStringSync();

const _page = 0, _block = 1, _paragraph = 2, _line = 3, _word = 4;

/// A layout record of a page [width] by [height] pixels with one text block,
/// one paragraph and the lines [lines], each a list of word boxes (left,
/// top, right, bottom) on a flat baseline at the boxes' bottom.
Int32List layoutOf(int width, int height, List<List<List<int>>> lines) {
  final values = <int>[_page, 0, 0, width, height, 0, 0, 0, 0];
  int lowest(int index) => lines
      .expand((line) => line)
      .fold(
        index == 1 ? height : 0,
        (value, box) =>
            index == 1 ? math.min(value, box[1]) : math.max(value, box[3]),
      );
  final left = lines
      .expand((line) => line)
      .map((box) => box[0])
      .reduce(math.min);
  final right = lines
      .expand((line) => line)
      .map((box) => box[2])
      .reduce(math.max);
  values.addAll([_block, left, lowest(1), right, lowest(3), 1, 0, 0, 0]);
  values.addAll([_paragraph, left, lowest(1), right, lowest(3), 1, 0, 0, 1]);
  for (final line in lines) {
    final left = line.map((box) => box[0]).reduce(math.min);
    final top = line.map((box) => box[1]).reduce(math.min);
    final right = line.map((box) => box[2]).reduce(math.max);
    final bottom = line.map((box) => box[3]).reduce(math.max);
    values.addAll([
      _line, left, top, right, bottom, //
      left, bottom, right, bottom,
    ]);
    for (final box in line) {
      values.addAll([_word, ...box, box[0], box[3], box[2], box[3]]);
    }
  }
  return Int32List.fromList(values);
}

/// hOCR of a page [width] by [height] pixels with the lines [lines], each a
/// list of words with their boxes.
String hocrOf(int width, int height, List<List<(String, List<int>)>> lines) {
  final output = StringBuffer(
    "<div class='ocr_page' id='page_1' title='image \"unknown\"; bbox 0 0 $width $height; ppageno 0'>",
  );
  for (final line in lines) {
    final boxes = line.map((word) => word.$2);
    output.write(
      "<span class='ocr_line' title='bbox ${boxes.map((box) => box[0]).reduce(math.min)} "
      "${boxes.map((box) => box[1]).reduce(math.min)} "
      "${boxes.map((box) => box[2]).reduce(math.max)} "
      "${boxes.map((box) => box[3]).reduce(math.max)}; baseline 0 0'>",
    );
    for (final (text, box) in line) {
      output.write(
        "<span class='ocrx_word' title='bbox ${box.join(' ')}; x_wconf 90'>$text</span> ",
      );
    }
    output.write('</span>');
  }
  output.write('</div>');
  return output.toString();
}

/// The text that [attachment] gives each word of a page with [source].
List<String> attachedWords(TextAttachment attachment, String source) => [
  for (var word = 0; word < attachment.length ~/ 2; word++)
    source.substring(attachment[word * 2], attachment[word * 2 + 1]),
];

void main() {
  group('a scanned page from its layout record', () {
    test('has the layout pass words, lines and blocks in Tesseract order, '
        'in page units', () {
      final record = layoutFixture('scanned-page');
      final geometry = pageGeometryFromLayout(record);
      final width = record[3];
      final words = [
        for (var index = 0; index < record.length; index += 9)
          if (record[index] == _word) record.sublist(index + 1, index + 5),
      ];
      final lines = [
        for (var index = 0; index < record.length; index += 9)
          if (record[index] == _line) index,
      ];

      expect(geometry.height, closeTo(record[4] / width, 1e-6));
      expect(geometry.wordCount, words.length);
      for (final (index, box) in words.indexed) {
        for (var side = 0; side < 4; side++) {
          expect(
            geometry.boxes[index * 4 + side],
            closeTo(box[side] / width, 1e-6),
          );
        }
      }
      expect(geometry.lineCount, lines.length);
      expect(geometry.lineStarts.first, 0);
      expect(geometry.lineStarts.last, geometry.wordCount);
      geometry.checkInvariants();
    });

    test(
      'keeps the engraving as a picture block with its box and no lines',
      () {
        final geometry = pageGeometryFromLayout(layoutFixture('scanned-page'));
        final pictures = [
          for (var block = 0; block < geometry.blockCount; block++)
            if (geometry.blockKind(block) == PageBlockKind.picture) block,
        ];
        expect(pictures, isNotEmpty);
        final engraving = pictures.firstWhere((block) {
          final box = geometry.blockBoxes.sublist(block * 4, block * 4 + 4);
          return (box[2] - box[0]) * (box[3] - box[1]) > geometry.height / 4;
        });
        expect(
          geometry.blockStarts[engraving + 1],
          geometry.blockStarts[engraving],
        );
      },
    );

    test('gives each word its own baseline at its left and right edges', () {
      final geometry = pageGeometryFromLayout(layoutFixture('scanned-page'));
      for (var word = 0; word < geometry.wordCount; word++) {
        final top = geometry.boxes[word * 4 + 1];
        final bottom = geometry.boxes[word * 4 + 3];
        for (final side in [0, 1]) {
          final baseline = geometry.ownBaselines[word * 2 + side];
          expect(baseline, inInclusiveRange(top, bottom + 0.01));
        }
      }
    });

    test('the skewed page has line slopes of its 2.5 degree turn', () {
      final record = layoutFixture('skewed-page');
      final geometry = pageGeometryFromLayout(record);
      final slopes = [
        for (var line = 0; line < geometry.lineCount; line++)
          if (geometry.lineRight(line) - geometry.lineLeft(line) > .25)
            math.atan(geometry.lineSlope(line)) * 180 / math.pi,
      ];
      expect(slopes.length, greaterThanOrEqualTo(3));
      for (final slope in slopes) {
        expect(slope.abs(), closeTo(2.5, 0.2));
      }
      geometry.checkInvariants();
    });

    test(
      'the skewed page sits each word of a line on that line\'s baseline',
      () {
        final geometry = pageGeometryFromLayout(layoutFixture('skewed-page'));
        for (var line = 0; line < geometry.lineCount; line++) {
          for (
            var word = geometry.lineStarts[line];
            word < geometry.lineStarts[line + 1];
            word++
          ) {
            final left = geometry.boxes[word * 4];
            final right = geometry.boxes[word * 4 + 2];
            final center = (left + right) / 2;
            final ownCenter =
                (geometry.ownBaselines[word * 2] +
                    geometry.ownBaselines[word * 2 + 1]) /
                2;
            // Tesseract's word baseline is the row's baseline at the word.
            expect(
              ownCenter,
              closeTo(geometry.lineBaselineAt(line, center), 2 / 1600),
            );
          }
        }
      },
    );

    test('keeps each line\'s height from ascender top to descender bottom, '
        'not the height of its turned box', () {
      final geometry = pageGeometryFromLayout(layoutFixture('skewed-page'));
      final flat = pageGeometryFromLayout(layoutFixture('scanned-page'));
      double median(PageGeometry page) {
        final heights = [
          for (var line = 0; line < page.lineCount; line++)
            page.lineHeight(line),
        ]..sort();
        return heights[heights.length ~/ 2];
      }

      // The turned page is drawn a little smaller to keep its corners.
      expect(median(geometry), closeTo(median(flat), median(flat) * .2));
      for (var line = 0; line < geometry.lineCount; line++) {
        expect(geometry.lineDescender(line), greaterThanOrEqualTo(0));
        expect(
          geometry.lineDescender(line),
          lessThan(geometry.lineHeight(line)),
        );
      }
    });

    test('marks the paragraph starts of the layout pass with their '
        'justification and indent', () {
      final record = layoutOf(1000, 1400, [
        [
          [100, 100, 200, 130],
          [220, 100, 300, 130],
        ],
        [
          [100, 140, 300, 170],
        ],
      ]);
      // Make the paragraph centered, with an indent of 50 pixels.
      record[18 + 5] = 2;
      record[18 + 6] = 50;
      final geometry = pageGeometryFromLayout(record);
      expect(geometry.paragraphStarts, [0]);
      expect(geometry.paragraphJustification(0), ParagraphJustification.center);
      expect(geometry.paragraphIndents.single, closeTo(.05, 1e-6));
      expect(geometry.lineStarts, [0, 2, 3]);
    });

    test('a record that is not a layout record gives no geometry', () {
      expect(
        () => pageGeometryFromLayout(Int32List.fromList([1, 2, 3])),
        throwsFormatException,
      );
      expect(
        () => pageGeometryFromLayout(
          Int32List.fromList([
            _page, 0, 0, 100, 100, 0, 0, 0, 0, //
            _word, 10, 10, 20, 20, 10, 20, 20, 20,
          ]),
        ),
        throwsFormatException,
      );
    });
  });

  group('recognized text attaches to the layout words', () {
    test('a recognized page gives the same reading text and digest as before '
        'word geometry, so a place saved before still resolves', () {
      final recognized = decodeRecognizedPage(hocrFixture('scanned-page')).text;
      expect(recognized.status, PdfTextStatus.candidate);
      expect(recognized.digest, scannedDigestBefore);
      expect(recognized.source, scannedSourceBefore);
      final pdf = HeldPdf();
      final place = PdfAddress(
        1,
        12,
        quote: recognized.source.substring(12, 172),
        pageCount: 1,
        representation:
            'fixture/fixture/${BundledEnglishText.version}/$scannedDigestBefore',
      );
      expect(pdf.resolveAddress(place, recognized), isNotNull);
    });

    test('each layout word of the scanned page attaches to the characters of '
        'the hOCR words that overlap it, in increasing order', () {
      final geometry = pageGeometryFromLayout(layoutFixture('scanned-page'));
      final recognized = decodeRecognizedPage(hocrFixture('scanned-page'));
      final attachment = attachText((
        geometry: geometry,
        words: recognized.words,
      ));
      final source = recognized.text.source;
      geometry.checkInvariants(attachment: attachment, source: source);
      final attached = attachedWords(attachment, source);
      expect(
        attached.where((word) => word.isNotEmpty).length,
        greaterThanOrEqualTo(geometry.wordCount - 2),
      );
      // Every recognized word is attached to some layout word.
      final joined = attached.where((word) => word.isNotEmpty).join(' ');
      expect(joined.split(RegExp(r'\s+')), source.split(RegExp(r'\s+')));
    });

    test('the skewed page attaches its text to its turned words', () {
      final geometry = pageGeometryFromLayout(layoutFixture('skewed-page'));
      final recognized = decodeRecognizedPage(hocrFixture('skewed-page'));
      final attachment = attachText((
        geometry: geometry,
        words: recognized.words,
      ));
      geometry.checkInvariants(
        attachment: attachment,
        source: recognized.text.source,
      );
      expect(
        attachedWords(
          attachment,
          recognized.text.source,
        ).where((word) => word.isNotEmpty).length,
        greaterThanOrEqualTo(geometry.wordCount - 3),
      );
    });

    test('the footnote page gives the page analysis an indented paragraph '
        'and line-end hyphens, with its text attached', () {
      final geometry = pageGeometryFromLayout(layoutFixture('footnote-page'));
      final recognized = decodeRecognizedPage(hocrFixture('footnote-page'));
      final attachment = attachText((
        geometry: geometry,
        words: recognized.words,
      ));
      final source = recognized.text.source;
      geometry.checkInvariants(attachment: attachment, source: source);
      final words = attachedWords(attachment, source);
      List<String> lineWords(int line) => words.sublist(
        geometry.lineStarts[line],
        geometry.lineStarts[line + 1],
      );
      final lines = [
        for (var line = 0; line < geometry.lineCount; line++) line,
      ];

      // "The name of the Alemanni" starts an indented paragraph of the
      // body, the block of the first line that starts with "hostile".
      final named = lines.singleWhere(
        (line) => lineWords(line).take(3).join(' ') == 'The name of',
      );
      final paragraph = geometry.paragraphStarts.indexOf(named);
      expect(paragraph, isNot(-1));
      expect(geometry.paragraphIndents[paragraph], greaterThan(0.02));
      final body = lines.singleWhere(
        (line) => lineWords(line).first == 'hostile',
      );
      expect(
        geometry.lineLeft(named),
        greaterThan(geometry.lineLeft(body) + 0.02),
      );

      // Six lines of the body and four lines of the footnotes end with a
      // hyphen that splits a word.
      expect(
        [
          for (final line in lines)
            if (lineWords(line).last.endsWith('-')) lineWords(line).last,
        ],
        [
          'arse-', 'num-', 'es-', 'Tou-', 'pro-', 'en-', //
          'ascer-', 'justi-', 'tran-', 'Thu-',
        ],
      );
    });

    test('a layout word joins each hOCR word that overlaps it most', () {
      final geometry = pageGeometryFromLayout(
        layoutOf(1000, 1400, [
          [
            [100, 100, 300, 130],
            [320, 100, 500, 130],
          ],
        ]),
      );
      final recognized = decodeRecognizedPage(
        hocrOf(1000, 1400, [
          [
            ('The', [100, 100, 180, 130]),
            ('quiet', [190, 100, 300, 130]),
            ('garden.', [300, 100, 500, 130]),
          ],
        ]),
      );
      final attachment = attachText((
        geometry: geometry,
        words: recognized.words,
      ));
      expect(attachedWords(attachment, recognized.text.source), [
        'The quiet',
        'garden.',
      ]);
    });

    test('an hOCR word that no layout word overlaps attaches to the word '
        'before it on its line, or else to the word after it', () {
      final geometry = pageGeometryFromLayout(
        layoutOf(1000, 1400, [
          [
            [100, 100, 200, 130],
            [400, 100, 500, 130],
          ],
        ]),
      );
      final recognized = decodeRecognizedPage(
        hocrOf(1000, 1400, [
          [
            ('A', [20, 100, 40, 130]),
            ('quiet', [100, 100, 200, 130]),
            ('little', [250, 100, 350, 130]),
            ('garden.', [400, 100, 500, 130]),
          ],
        ]),
      );
      final attachment = attachText((
        geometry: geometry,
        words: recognized.words,
      ));
      expect(attachedWords(attachment, recognized.text.source), [
        'A quiet little',
        'garden.',
      ]);
    });

    test('a layout word that no hOCR word overlaps names no text, at the '
        'place between its neighbors', () {
      final geometry = pageGeometryFromLayout(
        layoutOf(1000, 1400, [
          [
            [100, 100, 200, 130],
            [250, 100, 300, 130],
            [400, 100, 500, 130],
          ],
        ]),
      );
      final recognized = decodeRecognizedPage(
        hocrOf(1000, 1400, [
          [
            ('quiet', [100, 100, 200, 130]),
            ('garden.', [400, 100, 500, 130]),
          ],
        ]),
      );
      final attachment = attachText((
        geometry: geometry,
        words: recognized.words,
      ));
      expect(attachment, [0, 5, 5, 5, 6, 13]);
      geometry.checkInvariants(
        attachment: attachment,
        source: recognized.text.source,
      );
    });

    test('a layout word whose text would run backward names no text', () {
      // Layout reading order puts the right word first.
      final record = layoutOf(1000, 1400, [
        [
          [400, 100, 500, 130],
          [100, 100, 200, 130],
        ],
      ]);
      final geometry = pageGeometryFromLayout(record);
      final recognized = decodeRecognizedPage(
        hocrOf(1000, 1400, [
          [
            ('quiet', [100, 100, 200, 130]),
            ('garden.', [400, 100, 500, 130]),
          ],
        ]),
      );
      final attachment = attachText((
        geometry: geometry,
        words: recognized.words,
      ));
      expect(attachment, [6, 13, 13, 13]);
    });

    test('a page without word boxes in its hOCR attaches no text', () {
      final geometry = pageGeometryFromLayout(
        layoutOf(1000, 1400, [
          [
            [100, 100, 200, 130],
          ],
        ]),
      );
      final recognized = decodeRecognizedPage(
        '<div class="ocr_page"><span class="ocr_line" title="bbox 100 100 200 130">'
        '<span class="ocrx_word">quiet</span></span></div>',
      );
      expect(recognized.text.text, 'quiet');
      expect(attachText((geometry: geometry, words: recognized.words)), [0, 0]);
    });
  });
}

/// The reading text and digest that decodeRecognizedPage gave for the
/// scanned fixture's hOCR before this ticket (commit 6c9208b).
const scannedDigestBefore =
    'b445f1857d95e243154bfeb056e7df3b477586153e917f78f3477f0a319d25b4';
const scannedSourceBefore =
    'BY EDGAR A. POR.\n'
    '(ee npon a wildinight dreary, while [ pondered, weak and weary,\n'
    'Over many a qiaint and cuorions velume of forgotten lore\n'
    'While T aodded, nearly napping, suddenly there come a Lapping,';
