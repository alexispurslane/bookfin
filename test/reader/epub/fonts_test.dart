import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bookfin/reader/epub/css.dart';
import 'package:bookfin/reader/epub/fonts.dart';
import 'package:bookfin/reader/epub/layout.dart';
import 'package:bookfin/reader/epub/prepare.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

Uint8List fixture(String name) =>
    File('test/reader/epub/fixtures/$name').readAsBytesSync();

/// The width in pixels of one line of sample text in [family] at 20 pixels.
double widthIn(String family) {
  final builder = ui.ParagraphBuilder(ui.ParagraphStyle())
    ..pushStyle(ui.TextStyle(fontFamily: family, fontSize: 20))
    ..addText('The harbour boats return at seven.');
  final paragraph = builder.build()
    ..layout(const ui.ParagraphConstraints(width: 10000));
  return paragraph.maxIntrinsicWidth;
}

/// The face of family Outfit in the WOFF fixture.
const outfit = FontFaceRule(family: 'outfit', path: 'epub/fonts/outfit.woff');

/// The publication files that [outfit] and its neighbours name.
Uint8List? files(String path) => switch (path) {
  'epub/fonts/outfit.woff' => fixture('outfit-ascii.woff'),
  'epub/fonts/outfit.woff2' => fixture('outfit-ascii.woff2'),
  _ => null,
};

/// The width of the sample text in the subset fixture, loaded from its TTF.
late final double outfitWidth;

void main() {
  setUpAll(() async {
    await loadReaderFont();
    await ui.loadFontFromList(
      fixture('outfit-ascii.ttf'),
      fontFamily: 'fixture-ttf',
    );
    outfitWidth = widthIn('fixture-ttf');
    // The fixture is a different font, and Flutter draws with it.
    expect(outfitWidth, isNot(widthIn(readerFontFamily)));
    expect(outfitWidth, isNot(widthIn('no-such-family')));
  });

  test('a WOFF 1 font converts to one that Flutter draws as the same font '
      'in TTF form', () async {
    final converted = sfntOf(fixture('outfit-ascii.woff'));
    expect(converted, isNotNull);
    await ui.loadFontFromList(converted!, fontFamily: 'fixture-woff');
    expect(widthIn('fixture-woff'), outfitWidth);
  });

  test('a TTF font stays as it is', () {
    final ttf = fixture('outfit-ascii.ttf');
    expect(sfntOf(ttf), ttf);
  });

  test('WOFF 2, a font collection, a cut-off WOFF and a damaged WOFF table '
      'do not convert', () {
    final woff = fixture('outfit-ascii.woff');
    final collection = Uint8List.fromList([
      ...'ttcf'.codeUnits,
      ...List.filled(60, 0),
    ]);
    // The first table whose data is compressed loses its zlib header.
    final damaged = Uint8List.fromList(woff);
    final view = ByteData.sublistView(damaged);
    for (var entry = 44; ; entry += 20) {
      final offset = view.getUint32(entry + 4);
      if (view.getUint32(entry + 8) < view.getUint32(entry + 12)) {
        damaged[offset] = 0xff;
        damaged[offset + 1] = 0xff;
        break;
      }
    }
    expect(sfntOf(fixture('outfit-ascii.woff2')), isNull);
    expect(sfntOf(collection), isNull);
    expect(sfntOf(Uint8List.sublistView(woff, 0, 200)), isNull);
    expect(sfntOf(Uint8List.sublistView(woff, 0, woff.length - 100)), isNull);
    expect(sfntOf(damaged), isNull);
    expect(sfntOf(Uint8List(0)), isNull);
  });

  test('after the book fonts load, a run in an embedded face lays out with '
      'the widths of that face', () async {
    const prefix = 'bookfin-00000000000a';
    SectionSource source(String css) => SectionSource(
      index: 0,
      path: 'epub/text/one.xhtml',
      xhtml:
          '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>T</title>'
          '<link href="../css/book.css" rel="stylesheet"/></head>'
          // Outfit draws these letters about 9% narrower than the reader
          // font. Short words let a line show the difference.
          '<body><p>${'mim mu ' * 600}</p></body></html>',
      fontPrefix: prefix,
      styleSheets: {'epub/css/book.css': css},
    );
    final embedded = prepareSections([
      source(
        '@font-face{font-family:Outfit;src:url(../fonts/outfit.woff)}'
        'p{font-family:Outfit,serif}',
      ),
    ], readerPage).single;
    final plain = prepareSections([source('')], readerPage).single;
    int lines(PreparedSection section) => layoutSection(section).slices.length;
    final before = lines(embedded);

    await BookFonts.load(embedded.fonts, files, prefix);

    expect(embedded.fonts, [outfit]);
    expect(widthIn('$prefix-outfit'), outfitWidth);
    expect(lines(embedded), isNot(lines(plain)));
    expect(lines(embedded), isNot(before));
  });

  test('a face that cannot load is skipped and the faces after it load', () {
    const prefix = 'bookfin-00000000000b';
    const faces = [
      FontFaceRule(family: 'compressed', path: 'epub/fonts/outfit.woff2'),
      FontFaceRule(family: 'missing', path: 'epub/fonts/missing.ttf'),
      outfit,
    ];
    return expectLater(
      BookFonts.load(faces, files, prefix).then((_) {
        expect(widthIn('$prefix-outfit'), outfitWidth);
        expect(widthIn('$prefix-compressed'), widthIn('no-such-family'));
      }),
      completes,
    );
  });

  test('a second load of a face that is still loading waits for it', () async {
    const prefix = 'bookfin-00000000000c';
    final first = BookFonts.load([outfit], files, prefix);
    await BookFonts.load([outfit], files, prefix);
    expect(widthIn('$prefix-outfit'), outfitWidth);
    await first;
  });
}
