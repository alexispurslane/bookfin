// A book's own font draws only the characters that the reader font lacks
// (boo-3huo). Admission decides which sections need which of the book's
// font files, and the record keeps only those files. A run that a needed
// face styles draws in the reader font, with the face first in its fallback
// list, so only the missing characters draw in the face.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bookfin/reader/epub/font_files.dart';
import 'package:bookfin/reader/epub/fonts.dart';
import 'package:bookfin/reader/epub/layout.dart';
import 'package:bookfin/reader/epub/prepare.dart';
import 'package:bookfin/reader/epub/publication.dart';
import 'package:bookfin/reader/epub/reader_coverage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'admission_test.dart' show archive, package, xhtml;
import 'helpers.dart' show loadReaderFont;

/// A book's own font that covers only letters that the reader font has.
final asciiFont = File('test/reader/epub/fixtures/outfit-ascii.woff')
    .readAsBytesSync();

/// A book's own font that also covers [star], which the reader font lacks.
/// It draws the star two em wide.
final starFont = File('test/reader/epub/fixtures/outfit-star.woff')
    .readAsBytesSync();

/// U+2605 BLACK STAR.
const star = '★';

/// The `@font-face` rule of [family] in the font file `../fonts/[file]`.
String face(String family, String file) =>
    '@font-face{font-family:$family;src:url(../fonts/$file)}';

/// A book whose sections hold [bodies], whose one style sheet is [css], and
/// whose font files are [fonts], by name in its `fonts` folder.
Uint8List fontBook(
  List<String> bodies, {
  String css = '',
  Map<String, Uint8List> fonts = const {},
}) => archive(
  {
    'OPS/book.opf': package(
      '<item id="css" href="css/core.css" media-type="text/css"/>'
      '${[for (final (i, _) in bodies.indexed) '<item id="s$i" href="text/s$i.xhtml" media-type="application/xhtml+xml"/>'].join()}'
      '${[for (final (i, name) in fonts.keys.indexed) '<item id="f$i" href="fonts/$name" media-type="font/woff"/>'].join()}',
      [for (final (i, _) in bodies.indexed) '<itemref idref="s$i"/>'].join(),
    ),
    'OPS/css/core.css': css,
    for (final (i, body) in bodies.indexed) 'OPS/text/s$i.xhtml': xhtml(body),
  },
  binary: {
    for (final MapEntry(:key, :value) in fonts.entries) 'OPS/fonts/$key': value,
  },
);

/// The paths of the font files that [publication] keeps.
Set<String> fontFiles(Publication publication) => {
  for (final MapEntry(key: path, value: type) in publication.mediaTypes.entries)
    if (type.startsWith('font/')) path,
};

/// A run style of the reader font at 20 pixels, with [face] first in its
/// fallback list.
RunStyle readerRun({String? face}) => RunStyle(
  family: readerFontFamily,
  face: face,
  size: 20,
  weight: 400,
  italic: false,
  letterSpacing: 0,
  wordSpacing: 0,
  lineHeight: null,
  underline: false,
  lineThrough: false,
  smallCaps: false,
  oldstyleFigures: false,
);

/// [text] laid out in [style] on one long line.
ui.Paragraph line(String text, RunStyle style) {
  final builder = ui.ParagraphBuilder(ui.ParagraphStyle())
    ..pushStyle(runTextStyle(style, const ui.Color(0xff000000)))
    ..addText(text);
  return builder.build()..layout(const ui.ParagraphConstraints(width: 2000));
}

/// The width of code units [start] to [end] of [paragraph].
double widthOf(ui.Paragraph paragraph, int start, int end) => paragraph
    .getBoxesForRange(start, end)
    .fold(0.0, (total, box) => total + box.right - box.left);

void main() {
  group('the coverage of a font', () {
    test('the reader coverage table is the character map of the bundled '
        'reader font', () {
      final font = File('assets/fonts/SourceSerif4.ttf').readAsBytesSync();

      expect(Coverage.of(font)?.ranges, readerCoverage.ranges);
    });

    test("a WOFF font's coverage is its character map", () {
      final coverage = Coverage.of(starFont)!;

      expect(coverage.has(star.runes.single), isTrue);
      expect(coverage.has('A'.runes.single), isTrue);
      expect(coverage.has('é'.runes.single), isFalse);
      expect(readerCoverage.has(star.runes.single), isFalse);
      expect(readerCoverage.has('é'.runes.single), isTrue);
    });
  });

  group('admission', () {
    test('a book whose own font only repeats letters that the reader font '
        'has needs no font, and its record keeps no font file', () {
      final publication = Publication.admit(
        fontBook(
          ['<p>Plain words.</p>'],
          css: '${face('Outfit', 'ascii.woff')}p{font-family:Outfit,serif}',
          fonts: {'ascii.woff': asciiFont},
        ),
      );

      expect(publication.sectionFaces, isEmpty);
      expect(fontFiles(publication), isEmpty);
      publication.checkInvariants();
    });

    test('a section whose text holds a character that only the book font '
        'has needs that font, and the other sections need none', () {
      final publication = Publication.admit(
        fontBook(
          ['<p>Plain words.</p>', '<p>A star $star here.</p>'],
          css: '${face('Star', 'star.woff')}p{font-family:Star,serif}',
          fonts: {'star.woff': starFont},
        ),
      );

      expect(publication.sectionFaces, {
        'OPS/text/s1.xhtml': ['OPS/fonts/star.woff'],
      });
      publication.checkInvariants();
    });

    test('a character that only the book font has needs no font where the '
        'book does not style it with that font', () {
      final publication = Publication.admit(
        fontBook(
          ['<p>A star $star here.</p><p class="x">Plain words.</p>'],
          css: '${face('Star', 'star.woff')}.x{font-family:Star,serif}',
          fonts: {'star.woff': starFont},
        ),
      );

      expect(publication.sectionFaces, isEmpty);
      expect(fontFiles(publication), isEmpty);
    });

    test('characters that draw nothing, such as a zero width joiner, need no '
        'book font, though the book font has them and the reader font lacks '
        'them', () {
      final publication = Publication.admit(
        fontBook(
          ['<p>Joined\u200dwords and\ufeff a mark.</p>'],
          css: '${face('Star', 'star.woff')}p{font-family:Star,serif}',
          fonts: {'star.woff': starFont},
        ),
      );

      expect(publication.sectionFaces, isEmpty);
      expect(fontFiles(publication), isEmpty);
    });

    test('the record keeps only the font files that some section needs', () {
      final publication = Publication.admit(
        fontBook(
          ['<h1>Title</h1><p>A star $star here.</p>'],
          css:
              '${face('Plain', 'ascii.woff')}${face('Star', 'star.woff')}'
              'h1{font-family:Plain}p{font-family:Star,serif}',
          fonts: {
            'ascii.woff': asciiFont,
            'star.woff': starFont,
            'spare.woff': asciiFont,
          },
        ),
      );

      expect(fontFiles(publication), {'OPS/fonts/star.woff'});
      expect(publication.sectionFaces, {
        'OPS/text/s0.xhtml': ['OPS/fonts/star.woff'],
      });
      publication.checkInvariants();
    });
  });

  group('drawing', () {
    setUpAll(loadReaderFont);

    test('a character that only the book font has draws in the book font, '
        'and the letters around it draw in the reader font', () async {
      await BookFonts.load({
        'fonts/star.woff': 'test-book-star',
      }, (path) async => starFont);

      final withFace = line('A${star}B', readerRun(face: 'test-book-star'));
      // Each letter alone, so that no kerning between them counts.
      final readerA = line('A', readerRun());
      final readerB = line('B', readerRun());
      addTearDown(withFace.dispose);
      addTearDown(readerA.dispose);
      addTearDown(readerB.dispose);

      // The book font draws the star two em wide.
      expect(widthOf(withFace, 1, 2), 40);
      expect(widthOf(withFace, 0, 1), widthOf(readerA, 0, 1));
      expect(widthOf(withFace, 2, 3), widthOf(readerB, 0, 1));
    });
  });
}
