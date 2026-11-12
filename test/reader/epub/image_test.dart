// Images draw in both themes, and an image that cannot draw keeps its
// description. Standard Ebooks inverts its black line art in the dark color
// scheme, so the night theme draws it light on the dark paper. An image that
// fails to decode draws its alt text in its box, and admission's fallbacks
// for SVG reach the page through the native renderer.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:bookfin/reader/epub/dom.dart';
import 'package:bookfin/reader/epub/layout.dart';
import 'package:bookfin/reader/epub/places.dart';
import 'package:bookfin/reader/epub/prepare.dart';
import 'package:bookfin/reader/epub/publication.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'epubjs_fixtures.dart' show immediateSource;
import 'helpers.dart';
import 'page_source_test.dart' show book;

/// The reader's page in the night theme.
final nightPage = PageSettings(
  width: readerPage.width,
  height: readerPage.height,
  fontSize: readerPage.fontSize,
  night: true,
);

/// A 200 × 200 PNG of one color: red 200, green 40, blue 40.
List<int> redSquare() => img.encodePng(
  img.Image(width: 200, height: 200)..clear(img.ColorRgb8(200, 40, 40)),
);

/// A PNG chunk of [type] that holds [data].
List<int> _chunk(String type, List<int> data) {
  final body = [...type.codeUnits, ...data];
  return [
    ...(ByteData(4)..setUint32(0, data.length)).buffer.asUint8List(),
    ...body,
    ...(ByteData(4)..setUint32(0, getCrc32(body))).buffer.asUint8List(),
  ];
}

/// A 200 × 200 PNG of palette colors without its palette. The image package
/// reads it, so admission keeps it, but Flutter's decoder refuses it.
List<int> undecodable() {
  final header = ByteData(13)
    ..setUint32(0, 200)
    ..setUint32(4, 200)
    ..setUint8(8, 8)
    ..setUint8(9, 3);
  final rows = [
    for (var y = 0; y < 200; y++) ...[0, ...List.filled(200, 0)],
  ];
  return [
    ...[137, 80, 78, 71, 13, 10, 26, 10],
    ..._chunk('IHDR', header.buffer.asUint8List()),
    ..._chunk('IDAT', ZLibEncoder().encode(rows)),
    ..._chunk('IEND', const []),
  ];
}

/// The style sheet of a Standard Ebooks book that inverts its images in the
/// dark color scheme.
const invertInDark =
    '@media (prefers-color-scheme: dark){img{filter:invert(100%)}}';

/// A drawn page: its pixels and where its images sit, from the page's top
/// left.
class Drawn {
  Drawn(this.page, this.bytes, this.width);

  /// [picture] of [page] at [settings], rastered.
  static Future<Drawn> of(
    LaidPage page,
    ui.Picture picture,
    PageSettings settings,
  ) async {
    final raster = await picture.toImage(
      settings.width.round(),
      settings.height.round(),
    );
    final bytes = (await raster.toByteData())!;
    raster.dispose();
    return Drawn(page, bytes, settings.width.round());
  }

  final LaidPage page;
  final ByteData bytes;
  final int width;

  /// The color of the pixel at [at].
  ui.Color at(ui.Offset at) {
    final index = (at.dy.round() * width + at.dx.round()) * 4;
    return ui.Color.fromARGB(
      bytes.getUint8(index + 3),
      bytes.getUint8(index),
      bytes.getUint8(index + 1),
      bytes.getUint8(index + 2),
    );
  }

  /// The box of the page's one image, a block image or an inline one.
  ui.Rect get image {
    final boxes = [
      for (final decoration in page.decorations)
        if (decoration is ImageDecoration)
          decoration.rect.shift(ui.Offset(0, -page.top)),
      for (final piece in page.pieces)
        for (final (box, held) in piece.inlines)
          if (held is! ui.Paragraph)
            box.shift(ui.Offset(piece.x, piece.y - page.top)),
    ];
    return boxes.single;
  }

  /// The pixels inside [rect] whose color differs from [paper].
  int inked(ui.Rect rect, ui.Color paper) {
    var count = 0;
    for (var y = rect.top.ceil(); y < rect.bottom.floor(); y++) {
      for (var x = rect.left.ceil(); x < rect.right.floor(); x++) {
        final color = at(ui.Offset(x.toDouble(), y.toDouble()));
        if ((color.r - paper.r).abs() > .1 ||
            (color.g - paper.g).abs() > .1 ||
            (color.b - paper.b).abs() > .1) {
          count++;
        }
      }
    }
    return count;
  }
}

/// The first page of [publication] at [settings], drawn once its images
/// are decoded, or as the draft that draws before they are when [draft].
Future<Drawn> firstPage(
  Publication publication, {
  PageSettings settings = readerPage,
  bool draft = false,
}) async {
  final source = immediateSource(publication)..settings = settings;
  addTearDown(source.dispose);
  final section = await source.section(0);
  final page = await source.pageAt(
    EpubPlace(0, section.dom.body.order, 0),
    anchored: true,
    urgent: true,
  );
  final picture = draft ? source.draft(page) : await source.picture(page);
  return Drawn.of(page, picture, settings);
}

/// A book of one section whose body is [body], with a red square at
/// `images/map.png`.
Publication mapBook(String body, {String css = '', List<int>? map}) =>
    book([body], css: css, files: {'images/map.png': map ?? redSquare()});

const blockMap =
    '<p>Map.</p>'
    '<img src="../images/map.png" alt="A map of the harbour" '
    'style="display:block;width:200px"/>';

/// Whether [color] is [red], [green] and [blue] out of 255, within 3.
Matcher rgb(int red, int green, int blue) => predicate<ui.Color>(
  (color) =>
      ((color.r * 255) - red).abs() <= 3 &&
      ((color.g * 255) - green).abs() <= 3 &&
      ((color.b * 255) - blue).abs() <= 3,
  'the color ($red, $green, $blue)',
);

void main() {
  setUpAll(loadReaderFont);

  group('filter: invert()', () {
    test('in night, an image that the dark color scheme inverts draws '
        'inverted', () async {
      final drawn = await firstPage(
        mapBook(blockMap, css: invertInDark),
        settings: nightPage,
      );
      expect(drawn.at(drawn.image.center), rgb(55, 215, 215));
    });

    test('in cream, the same image draws unchanged', () async {
      final drawn = await firstPage(mapBook(blockMap, css: invertInDark));
      expect(drawn.at(drawn.image.center), rgb(200, 40, 40));
    });

    test('an image in a line inverts as a block image does', () async {
      final drawn = await firstPage(
        mapBook(
          '<p>The map <img src="../images/map.png" alt="A map" '
          'style="width:100px"/> shows the harbour.</p>',
          css: invertInDark,
        ),
        settings: nightPage,
      );
      expect(drawn.at(drawn.image.center), rgb(55, 215, 215));
    });

    test('invert(50%) draws each color half way to its inverse', () async {
      final drawn = await firstPage(
        mapBook(blockMap, css: 'img{filter:invert(50%)}'),
      );
      expect(drawn.at(drawn.image.center), rgb(128, 128, 128));
    });

    test('a list of filters inverts by its invert() and ignores the other '
        'filters', () async {
      final drawn = await firstPage(
        mapBook(blockMap, css: 'img{filter:sepia(1) invert(1) blur(3px)}'),
      );
      expect(drawn.at(drawn.image.center), rgb(55, 215, 215));
    });

    test('two invert(100%) filters cancel each other', () async {
      final drawn = await firstPage(
        mapBook(blockMap, css: 'img{filter:invert(100%) invert(100%)}'),
      );
      expect(drawn.at(drawn.image.center), rgb(200, 40, 40));
    });

    test('a filter without invert() draws the image unchanged', () async {
      final drawn = await firstPage(
        mapBook(blockMap, css: 'img{filter:grayscale(100%)}'),
      );
      expect(drawn.at(drawn.image.center), rgb(200, 40, 40));
    });
  });

  group('an image that cannot draw', () {
    test(
      'an image that fails to decode draws its alt text in its box',
      () async {
        final drawn = await firstPage(mapBook(blockMap, map: undecodable()));
        final box = drawn.image;
        expect(drawn.inked(box.deflate(4), readerPage.paper), greaterThan(50));
        expect(drawn.at(box.center), isNot(rgb(200, 40, 40)));
      },
    );

    test(
      'an image without alt text that fails to decode draws an outline',
      () async {
        final drawn = await firstPage(
          mapBook(
            '<p>Map.</p><img src="../images/map.png" '
            'style="display:block;width:200px"/>',
            map: undecodable(),
          ),
        );
        final box = drawn.image;
        expect(drawn.inked(box.deflate(4), readerPage.paper), 0);
        expect(drawn.inked(box.inflate(1), readerPage.paper), greaterThan(0));
      },
    );

    test('once an image fails to decode, a draft of its page draws its alt '
        'text too', () async {
      final publication = mapBook(blockMap, map: undecodable());
      final source = immediateSource(publication)..settings = readerPage;
      addTearDown(source.dispose);
      final section = await source.section(0);
      final page = await source.pageAt(
        EpubPlace(0, section.dom.body.order, 0),
        anchored: true,
        urgent: true,
      );
      await source.picture(page);
      final drawn = await Drawn.of(page, source.draft(page), readerPage);
      expect(
        drawn.inked(drawn.image.deflate(4), readerPage.paper),
        greaterThan(50),
      );
    });

    test('an image that is not decoded yet draws an outline, not its alt '
        'text', () async {
      final drawn = await firstPage(mapBook(blockMap), draft: true);
      expect(drawn.inked(drawn.image.deflate(4), readerPage.paper), 0);
    });
  });

  group("admission's fallbacks for SVG", () {
    test('an inline SVG with an aria-label shows its label as text, and that '
        'text has places', () async {
      final publication = book([
        '<p>Before the chart.</p>'
            '<svg xmlns="http://www.w3.org/2000/svg" aria-label="Tide chart" '
            'viewBox="0 0 10 10"><rect width="10" height="10"/></svg>',
      ]);
      final source = immediateSource(publication)..settings = readerPage;
      addTearDown(source.dispose);
      final section = await source.section(0);
      final label = section.dom.texts.singleWhere(
        (text) => text.text.contains('Tide chart'),
      );
      expect(label.text, '[Unsupported image: Tide chart]');
      final place = EpubPlace(0, label.order, 1);
      final page = await source.pageAt(place, anchored: true, urgent: true);
      expect(page.endPlace, EpubPlace(0, label.order, label.text.length - 1));
      final spine = spineStep(
        String.fromCharCodes(publication.textFiles[publication.packagePath]!),
        0,
      );
      expect(placeOf(section.dom, 0, cfiOf(spine, section.dom, place)), place);
      expect(quoteAt(section.dom, place), startsWith('Unsupported image'));
    });

    test('an SVG wrapper of a JPEG draws the JPEG', () async {
      final jpeg = img.encodeJpg(
        img.Image(width: 200, height: 300)..clear(img.ColorRgb8(200, 40, 40)),
        quality: 100,
      );
      final drawn = await firstPage(
        book(
          [
            '<p>Cover.</p><img src="../images/cover.svg" alt="Cover" '
                'style="display:block;width:200px"/>',
          ],
          files: {
            'images/cover.jpg': jpeg,
            'images/cover.svg':
                '<svg xmlns="http://www.w3.org/2000/svg" '
                        'xmlns:xlink="http://www.w3.org/1999/xlink" version="1.1" '
                        'width="100%" height="100%" viewBox="0 0 200 300" '
                        'preserveAspectRatio="xMidYMid meet">'
                        '<image width="200" height="300" xlink:href="cover.jpg"/>'
                        '</svg>'
                    .codeUnits,
          },
        ),
      );
      expect(
        drawn.page.decorations.whereType<ImageDecoration>().single.path,
        'OPS/images/cover.jpg',
      );
      expect(drawn.at(drawn.image.center), rgb(200, 40, 40));
    });
  });
}
