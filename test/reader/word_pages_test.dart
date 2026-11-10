import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bookfin/foundation/theme.dart';
import 'package:bookfin/reader/column_layout.dart';
import 'package:bookfin/reader/page_analysis.dart';
import 'package:bookfin/reader/pdf.dart';
import 'package:bookfin/reader/word_bands.dart';
import 'package:bookfin/reader/word_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart' as native;

import 'ocr_hop_test.dart' show runInWorker;
import 'page_analysis_test.dart'
    show FixtureRecognition, equationPage, footnotePage, ravenPage;

/// The device pixels for one logical pixel on a Pixel 8.
const devicePixelRatio = 2.625;

/// The column of a Pixel 8 in portrait: its width without the margins, and
/// the height of a screen of lines, in logical pixels.
const columnWidth = 371.0, screenHeight = 760.0;

const marginsBook = 'test/reader/fixtures/reflow/margins-book.pdf';

WordSettings settings({
  double fontSize = 20,
  double width = columnWidth,
  double height = screenHeight,
}) => (
  width: width,
  fontSize: fontSize,
  screenHeight: height,
  devicePixelRatio: devicePixelRatio,
);

/// The device pixels of one screen of [settings].
int screenPixels(WordSettings settings) =>
    (settings.width * settings.devicePixelRatio).ceil() *
    (settings.screenHeight * settings.devicePixelRatio).ceil();

/// The pieces of [screen] of [column].
Iterable<int> screenPieces(ReflowColumn column, int screen) sync* {
  final first = column.lineStarts[column.screenStarts[screen]];
  final end = column.lineStarts[column.screenStarts[screen + 1]];
  for (var piece = first; piece < end; piece++) {
    yield piece;
  }
}

/// The paper and ink of a test tint: white paper and black ink, so a drawn
/// page keeps the pixels that pdfium drew.
const neutral = WordTint(
  paper: Color(0xFFFFFFFF),
  ink: Color(0xFF000000),
  brightness: Brightness.light,
);

/// The pixels of [bands] drawn by [paintScreen] on a canvas [width] by
/// [height] device pixels, at [devicePixelRatio], as RGBA bytes.
Future<ByteData> drawScreen(
  List<DrawnBand> bands,
  WordTint tint,
  int width,
  int height, {
  double ratio = devicePixelRatio,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(ratio);
  paintScreen(canvas, Size(width / ratio, height / ratio), bands, tint);
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  final bytes = (await image.toByteData())!;
  image.dispose();
  return bytes;
}

/// An image [width] by [height] from RGBA [pixels].
Future<ui.Image> imageOf(int width, int height, List<int> pixels) {
  final done = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    Uint8List.fromList(pixels),
    width,
    height,
    ui.PixelFormat.rgba8888,
    done.complete,
  );
  return done.future;
}

/// The color of pixel ([x], [y]) of RGBA [bytes] [width] pixels wide.
Color pixelAt(ByteData bytes, int width, int x, int y) {
  final at = (y * width + x) * 4;
  return Color.fromARGB(
    bytes.getUint8(at + 3),
    bytes.getUint8(at),
    bytes.getUint8(at + 1),
    bytes.getUint8(at + 2),
  );
}

/// Whether [a] and [b] differ by at most [within] in each channel of 255.
bool near(Color a, Color b, {int within = 2}) =>
    ((a.r - b.r) * 255).abs() <= within &&
    ((a.g - b.g) * 255).abs() <= within &&
    ((a.b - b.b) * 255).abs() <= within;

/// A band of one sprite that draws [image] whole, its top left corner at
/// ([x], [y]) logical pixels, at one image pixel for one device pixel.
DrawnBand oneSprite(
  ui.Image image,
  BandTint tint, {
  double x = 0,
  double y = 0,
}) => DrawnBand(
  image: image,
  tint: tint,
  transforms: Float32List.fromList([1 / devicePixelRatio, 0, x, y]),
  rects: Float32List.fromList([
    0,
    0,
    image.width.toDouble(),
    image.height.toDouble(),
  ]),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  native.Pdfrx.pdfiumModulePath = Platform.environment['PDFIUM_LIBRARY'];
  native.Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;
  late List<Function> hopped;

  Future<R> hop<M, R>(FutureOr<R> Function(M) work, M input) {
    hopped.add(work);
    return runInWorker(work, input);
  }

  setUp(() => hopped = []);
  tearDownAll(() => PdfRuntime.instance.shutdown());

  Future<PdfBook> open(String path, {PdfTextSupply? textSupply}) async {
    final book = await PdfRuntime.instance.open(
      await File(path).readAsBytes(),
      'd' * 64,
      textSupply: textSupply,
      hop: hop,
    );
    addTearDown(book.dispose);
    return book;
  }

  Future<PdfBook> gibbon() => open(
    footnotePage,
    textSupply: FixtureRecognition('footnote-page')..textArrives.complete(),
  );
  Future<PdfBook> raven() => open(
    ravenPage,
    textSupply: FixtureRecognition('scanned-page')..textArrives.complete(),
  );
  Future<PdfBook> equation() => open(equationPage);

  /// The column and bands of page [page] of [book] for [settings].
  Future<WordColumn> plan(
    PdfBook book,
    WordSettings settings, {
    int page = 1,
  }) async {
    final reflow = (await book.reflowPage(page))!;
    final planned = planWordColumn((
      geometry: reflow.geometry,
      analysis: reflow.analysis,
      bodyLineHeight: reflow.bodyLineHeight,
      settings: settings,
    ));
    planned.checkInvariants();
    return planned;
  }

  group('bands', () {
    test('a word image draws at one band pixel for one device pixel, on '
        'the device pixel grid when it is level', () async {
      for (final book in [await gibbon(), await equation(), await raven()]) {
        for (final fontSize in [14.0, 20.0, 40.0]) {
          final planned = await plan(book, settings(fontSize: fontSize));
          final bands = planned.bands;
          var words = 0;
          for (var sprite = 0; sprite < bands.spriteCount; sprite++) {
            if (planned.column.word(bands.spritePieces[sprite]) < 0) continue;
            words++;
            final t = bands.transform(sprite);
            final drawn = math.sqrt(t.scos * t.scos + t.ssin * t.ssin);
            expect(drawn * devicePixelRatio, closeTo(1, 1e-6));
            if (t.ssin == 0) {
              final x = t.tx * devicePixelRatio, y = t.ty * devicePixelRatio;
              expect(x, closeTo(x.roundToDouble(), 1e-3));
              expect(y, closeTo(y.roundToDouble(), 1e-3));
            }
          }
          expect(words, greaterThan(20));
        }
      }
    });

    test('every screen draws its pieces from the top of the screen, within '
        'its height', () async {
      final book = await gibbon();
      final planned = await plan(book, settings(fontSize: 40));
      final column = planned.column, bands = planned.bands;
      expect(column.screenCount, greaterThan(2));
      for (var screen = 0; screen < column.screenCount; screen++) {
        var top = double.infinity, bottom = -double.infinity;
        for (
          var sprite = bands.spriteStarts[bands.screenStarts[screen]];
          sprite < bands.spriteStarts[bands.screenStarts[screen + 1]];
          sprite++
        ) {
          final t = bands.transform(sprite), rect = bands.rect(sprite);
          top = math.min(top, t.ty);
          bottom = math.max(bottom, t.ty + rect.height * t.scos);
        }
        expect(top, closeTo(0, 2), reason: 'screen $screen');
        expect(bottom, lessThanOrEqualTo(screenHeight + 1));
      }
    });

    test('a band renders at the scale that the text size needs', () async {
      final book = await gibbon();
      for (final fontSize in [14.0, 32.0]) {
        final planned = await plan(book, settings(fontSize: fontSize));
        final wordBand = planned.bands.bandOfSprite(0);
        expect(
          planned.bands.pixelsPerPageUnit(wordBand),
          (planned.column.scale * devicePixelRatio).round(),
        );
      }
    });

    test('every piece of a screen draws once, from a band of that '
        'screen', () async {
      for (final book in [await gibbon(), await equation(), await raven()]) {
        for (final fontSize in [14.0, 26.0, 40.0]) {
          final planned = await plan(book, settings(fontSize: fontSize));
          final column = planned.column, bands = planned.bands;
          for (var screen = 0; screen < column.screenCount; screen++) {
            final drawn = <int>[
              for (
                var band = bands.screenStarts[screen];
                band < bands.screenStarts[screen + 1];
                band++
              )
                for (
                  var sprite = bands.spriteStarts[band];
                  sprite < bands.spriteStarts[band + 1];
                  sprite++
                )
                  bands.spritePieces[sprite],
            ]..sort();
            expect(drawn, screenPieces(column, screen).toList());
          }
        }
      }
    });

    test('a band is at most 4096 pixels on each side, and a screen\'s '
        'bands hold at most twice its device pixels', () async {
      for (final book in [await gibbon(), await equation(), await raven()]) {
        for (final (fontSize, width, height) in [
          (14.0, columnWidth, screenHeight),
          (20.0, columnWidth, screenHeight),
          (40.0, columnWidth, screenHeight),
          (40.0, 700.0, 380.0),
          (14.0, 1200.0, 1800.0),
        ]) {
          final wanted = settings(
            fontSize: fontSize,
            width: width,
            height: height,
          );
          final planned = await plan(book, wanted);
          final bands = planned.bands;
          for (var screen = 0; screen < planned.column.screenCount; screen++) {
            var pixels = 0;
            for (
              var band = bands.screenStarts[screen];
              band < bands.screenStarts[screen + 1];
              band++
            ) {
              final area = bands.area(band);
              expect(area.width, lessThanOrEqualTo(4096));
              expect(area.height, lessThanOrEqualTo(4096));
              pixels += (area.width * area.height).toInt();
            }
            expect(pixels, lessThanOrEqualTo(2 * screenPixels(wanted)));
          }
        }
      }
    });

    test('a picture region draws from a band of its own with the picture '
        'tint, and words and ink regions with the ink tint', () async {
      final book = await raven();
      final reflow = (await book.reflowPage(1))!;
      final planned = await plan(book, settings());
      final column = planned.column, bands = planned.bands;
      var pictures = 0;
      for (var band = 0; band < bands.bandCount; band++) {
        for (
          var sprite = bands.spriteStarts[band];
          sprite < bands.spriteStarts[band + 1];
          sprite++
        ) {
          final region = column.region(bands.spritePieces[sprite]);
          final picture =
              region >= 0 &&
              reflow.analysis.regionKind(region) == RegionKind.picture;
          expect(bands.tint(band), picture ? BandTint.picture : BandTint.ink);
          if (picture) {
            pictures++;
            expect(bands.spriteStarts[band + 1] - bands.spriteStarts[band], 1);
          }
        }
      }
      expect(pictures, greaterThan(0), reason: 'the Raven has an engraving');
    });
  });

  group('drawing', () {
    test('a drawn word has the pixels that pdfium draws at device '
        'resolution, at two text sizes', () async {
      final book = await gibbon();
      for (final fontSize in [14.0, 32.0]) {
        final wanted = settings(fontSize: fontSize);
        final planned = await plan(book, wanted);
        final column = planned.column, bands = planned.bands;
        final band = bands.screenStarts[0];
        final image = await book.renderPart(
          1,
          bands.pixelsPerPageUnit(band),
          bands.area(band),
        );
        addTearDown(image.dispose);
        final width = (columnWidth * devicePixelRatio).ceil();
        final height = (screenHeight * devicePixelRatio).ceil();
        final drawn = await drawScreen(
          [DrawnBand.of(image, bands, band)],
          neutral,
          width,
          height,
        );
        final source = (await image.toByteData())!;
        // How many sprites cover each device pixel. Where two meet, such as
        // the halves of a joined hyphen pair, their rounded edges add.
        final covers = Uint8List(width * height);
        for (
          var sprite = bands.spriteStarts[band];
          sprite < bands.spriteStarts[band + 1];
          sprite++
        ) {
          final t = bands.transform(sprite), rect = bands.rect(sprite);
          final corners = [
            for (final (x, y) in [
              (0.0, 0.0),
              (rect.width, 0.0),
              (0.0, rect.height),
              (rect.width, rect.height),
            ])
              Offset(
                (t.scos * x - t.ssin * y + t.tx) * devicePixelRatio,
                (t.ssin * x + t.scos * y + t.ty) * devicePixelRatio,
              ),
          ];
          final xs = corners.map((corner) => corner.dx);
          final ys = corners.map((corner) => corner.dy);
          for (
            var y = math.max(0, ys.reduce(math.min).floor());
            y < math.min(height, ys.reduce(math.max).ceil());
            y++
          ) {
            for (
              var x = math.max(0, xs.reduce(math.min).floor());
              x < math.min(width, xs.reduce(math.max).ceil());
              x++
            ) {
              covers[y * width + x]++;
            }
          }
        }
        var compared = 0, inked = 0;
        for (
          var sprite = bands.spriteStarts[band];
          sprite < bands.spriteStarts[band + 1];
          sprite++
        ) {
          final t = bands.transform(sprite);
          if (t.ssin != 0 || column.word(bands.spritePieces[sprite]) < 0) {
            continue;
          }
          final rect = bands.rect(sprite);
          final left = (t.tx * devicePixelRatio).round();
          final top = (t.ty * devicePixelRatio).round();
          for (var y = rect.top.toInt(); y < rect.bottom; y++) {
            for (var x = rect.left.toInt(); x < rect.right; x++) {
              final at = (
                left + x - rect.left.toInt(),
                top + y - rect.top.toInt(),
              );
              if (at.$1 < 0 ||
                  at.$1 >= width ||
                  at.$2 < 0 ||
                  at.$2 >= height ||
                  covers[at.$2 * width + at.$1] != 1) {
                continue;
              }
              final want = pixelAt(source, image.width, x, y);
              final got = pixelAt(drawn, width, at.$1, at.$2);
              // The page's paper lightness and lighter draw white, and its
              // ink lightness and darker black.
              final lightness = want.r * .299 + want.g * .587 + want.b * .114;
              final gray =
                  ((lightness - bands.inkLightness) /
                          (bands.paperLightness - bands.inkLightness))
                      .clamp(0, 1) *
                  255;
              final expected = Color.fromARGB(
                255,
                gray.round(),
                gray.round(),
                gray.round(),
              );
              expect(
                near(got, expected, within: 3),
                isTrue,
                reason:
                    'size $fontSize, sprite $sprite at ($x, $y): '
                    'drawn $got, pdfium $expected',
              );
              compared++;
              if (gray < 100) inked++;
            }
          }
        }
        expect(compared, greaterThan(1000));
        expect(inked, greaterThan(100));
      }
    });

    for (final brightness in Brightness.values) {
      final theme = bookfinTheme(brightness).colorScheme;
      final name = brightness == Brightness.light ? 'cream' : 'night';

      test(
        'in $name, transparent band pixels leave the reader paper visible',
        () async {
          final image = await imageOf(2, 1, [0, 0, 0, 0, 0, 0, 0, 255]);
          addTearDown(image.dispose);
          final drawn = await drawScreen(
            [oneSprite(image, BandTint.ink)],
            WordTint.of(theme),
            4,
            2,
          );
          expect(near(pixelAt(drawn, 4, 0, 0), theme.surface), isTrue);
          expect(near(pixelAt(drawn, 4, 1, 0), theme.onSurface), isTrue);
        },
      );

      test('in $name, a black pixel draws in the text color and a white '
          'pixel in the paper', () async {
        final tint = WordTint.of(theme);
        final image = await imageOf(2, 1, [0, 0, 0, 255, 255, 255, 255, 255]);
        addTearDown(image.dispose);
        final drawn = await drawScreen(
          [oneSprite(image, BandTint.ink, x: 0, y: 0)],
          tint,
          4,
          2,
        );
        expect(near(pixelAt(drawn, 4, 0, 0), theme.onSurface), isTrue);
        expect(near(pixelAt(drawn, 4, 1, 0), theme.surface), isTrue);
        expect(near(pixelAt(drawn, 4, 3, 1), theme.surface), isTrue);
      });

      test('in $name, a picture keeps its colors', () async {
        final tint = WordTint.of(theme);
        final image = await imageOf(3, 1, [
          ...[200, 40, 40, 255],
          ...[128, 128, 128, 255],
          ...[255, 255, 255, 255],
        ]);
        addTearDown(image.dispose);
        final drawn = await drawScreen(
          [oneSprite(image, BandTint.picture)],
          tint,
          3,
          1,
        );
        Color times(Color color, double r, double g, double b) => Color.from(
          alpha: 1,
          red: color.r * r,
          green: color.g * g,
          blue: color.b * b,
        );
        final paper = theme.surface;
        final (r, g, b) = brightness == Brightness.light
            ? (paper.r, paper.g, paper.b)
            : (.8, .8, .8);
        for (final (x, source) in [
          (0, const Color(0xFFC82828)),
          (1, const Color(0xFF808080)),
          (2, const Color(0xFFFFFFFF)),
        ]) {
          expect(
            near(pixelAt(drawn, 3, x, 0), times(source, r, g, b)),
            isTrue,
            reason: 'pixel $x is ${pixelAt(drawn, 3, x, 0)}',
          );
        }
      });

      test('in $name, the paper of a word never paints over the ink of a '
          'word that it overlaps', () async {
        final tint = WordTint.of(theme);
        final ink = await imageOf(1, 1, [0, 0, 0, 255]);
        final paper = await imageOf(2, 1, [255, 255, 255, 255, 0, 0, 0, 255]);
        addTearDown(ink.dispose);
        addTearDown(paper.dispose);
        final drawn = await drawScreen(
          [oneSprite(ink, BandTint.ink), oneSprite(paper, BandTint.ink)],
          tint,
          2,
          1,
        );
        expect(near(pixelAt(drawn, 2, 0, 0), theme.onSurface), isTrue);
        expect(near(pixelAt(drawn, 2, 1, 0), theme.onSurface), isTrue);
      });
    }
  });

  group('levels', () {
    test('the page analysis measures the paper and the ink of a scan, and '
        'a born-digital page has white paper and black ink', () async {
      final scan = (await (await gibbon()).reflowPage(1))!.analysis;
      expect(scan.paperLightness, inInclusiveRange(.6, .95));
      expect(scan.inkLightness, lessThan(.4));
      final digital = (await (await equation()).reflowPage(1))!.analysis;
      expect(digital.paperLightness, 1);
      expect(digital.inkLightness, lessThan(.05));
    });

    test('the paper of a scan draws in the theme\'s paper, and its ink in '
        'the text color', () async {
      final book = await gibbon();
      final cream = bookfinTheme(Brightness.light).colorScheme;
      final planned = await plan(book, settings());
      final bands = planned.bands;
      final band = bands.screenStarts[0];
      final image = await book.renderPart(
        1,
        bands.pixelsPerPageUnit(band),
        bands.area(band),
      );
      addTearDown(image.dispose);
      final width = (columnWidth * devicePixelRatio).ceil();
      final height = (screenHeight * devicePixelRatio).ceil();
      final drawn = await drawScreen(
        [DrawnBand.of(image, bands, band)],
        WordTint.of(cream),
        width,
        height,
      );
      // Inside the first word, which draws on whole device pixels.
      final sprite = bands.spriteStarts[band];
      final t = bands.transform(sprite), rect = bands.rect(sprite);
      var paper = 0, ink = 0, pixels = 0;
      for (var y = 1; y < rect.height - 1; y++) {
        for (var x = 1; x < rect.width - 1; x++) {
          final color = pixelAt(
            drawn,
            width,
            (t.tx * devicePixelRatio).round() + x,
            (t.ty * devicePixelRatio).round() + y,
          );
          pixels++;
          if (near(color, cream.surface)) paper++;
          if (near(color, cream.onSurface, within: 24)) ink++;
        }
      }
      expect(paper, greaterThan(pixels * .5), reason: '$paper of $pixels');
      expect(ink, greaterThan(pixels * .05), reason: '$ink of $pixels');
    });
  });

  group('PdfWordPages', () {
    /// The images that [pages] keeps, and a check that they and their
    /// pixels stay within the bound.
    List<ui.Image> live(PdfWordPages pages, List<WordSettings> shown) {
      pages.checkInvariants();
      final images = pages.liveImages.toList();
      final pixels = images.fold(
        0,
        (sum, image) => sum + image.width * image.height,
      );
      expect(
        pixels,
        lessThanOrEqualTo(4 * shown.map(screenPixels).reduce(math.max)),
      );
      return images;
    }

    test('the live band images never hold more than 4 times the screen\'s '
        'pixels while the person turns through a page and back', () async {
      final book = await gibbon();
      final pages = PdfWordPages(book);
      addTearDown(pages.dispose);
      final wanted = settings(fontSize: 26);
      pages.shown.addListener(() => live(pages, [wanted]));
      final column = (await pages.column(1, wanted))!;
      expect(column.column.screenCount, greaterThan(2));
      for (var screen = 0; screen < column.column.screenCount; screen++) {
        await pages.show(1, wanted, screen);
        live(pages, [wanted]);
      }
      for (var screen = column.column.screenCount - 1; screen >= 0; screen--) {
        await pages.show(1, wanted, screen, forward: false);
        live(pages, [wanted]);
      }
      expect(pages.shown.value!.screen, 0);
    });

    test('a turn to the next screen shows the bands that were rendered '
        'ahead for it', () async {
      final book = await gibbon();
      final pages = PdfWordPages(book);
      addTearDown(pages.dispose);
      final wanted = settings();
      await pages.show(1, wanted, 0);
      final ahead = pages.liveImages
          .where(
            (image) => !pages.shown.value!.bands.any(
              (band) => identical(band.image, image),
            ),
          )
          .toList();
      expect(ahead, isNotEmpty);
      await pages.show(1, wanted, 1);
      expect(
        pages.shown.value!.bands.map((band) => band.image),
        unorderedEquals(ahead),
      );
    });

    test('the shown screen stays until the bands of the new screen are '
        'ready', () async {
      final book = await gibbon();
      final pages = PdfWordPages(book);
      addTearDown(pages.dispose);
      await pages.show(1, settings(), 0);
      final before = pages.shown.value!;
      final larger = pages.show(1, settings(fontSize: 30), 0);
      expect(pages.shown.value, same(before));
      for (final band in before.bands) {
        expect(band.image.debugDisposed, isFalse);
      }
      await larger;
      expect(pages.shown.value!.settings.fontSize, 30);
    });

    test('a change of page, text size or width disposes the images that '
        'the new screens do not use', () async {
      final book = await open(marginsBook);
      final pages = PdfWordPages(book);
      addTearDown(pages.dispose);
      final changes = [
        (page: 3, settings: settings()),
        (page: 3, settings: settings(fontSize: 22)),
        (page: 3, settings: settings(fontSize: 22, width: 300)),
        (page: 4, settings: settings(fontSize: 22, width: 300)),
        (page: 3, settings: settings()),
      ];
      var before = <ui.Image>[];
      WordSettings? last;
      for (final change in changes) {
        await pages.show(change.page, change.settings, 0);
        final now = live(pages, [change.settings, ?last]);
        for (final image in before) {
          if (!now.contains(image)) expect(image.debugDisposed, isTrue);
        }
        before = now;
        last = change.settings;
      }
      pages.dispose();
      for (final image in before) {
        expect(image.debugDisposed, isTrue);
      }
    });

    test('the column layout and the band plans run through the book\'s '
        'hop', () async {
      final book = await equation();
      final pages = PdfWordPages(book);
      addTearDown(pages.dispose);
      hopped.clear();
      await pages.column(1, settings());
      expect(hopped, contains(planWordColumn));
    });
  });

  test('renderPart draws an area of the page as the whole page drawn at '
      'that width draws it', () async {
    final book = await equation();
    final whole = await book.render(1, 1200);
    final part = await book.renderPart(
      1,
      1200,
      const Rect.fromLTWH(300, 400, 120, 80),
    );
    addTearDown(part.dispose);
    expect((part.width, part.height), (120, 80));
    final bytes = (await part.toByteData())!;
    // pdfium smooths a glyph's edge pixels a little differently when it
    // draws a part, so the pixels agree in where the ink is, not exactly.
    var total = 0, largest = 0, inked = 0;
    for (var y = 0; y < 80; y++) {
      for (var x = 0; x < 120; x++) {
        final at = ((400 + y) * whole.width + 300 + x) * 4;
        final want = whole.bgra[at + 1];
        final got = bytes.getUint8((y * 120 + x) * 4 + 1);
        final difference = (want - got).abs();
        total += difference;
        largest = math.max(largest, difference);
        if (want < 100) inked++;
      }
    }
    expect(inked, greaterThan(200), reason: 'the area holds text');
    expect(largest, lessThanOrEqualTo(128));
    expect(total / (120 * 80), lessThan(2));
  });
}
