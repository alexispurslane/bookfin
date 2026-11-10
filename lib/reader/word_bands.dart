import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset, Rect, RSTransform;

import 'column_layout.dart';
import 'page_analysis.dart';
import 'page_geometry.dart';

/// What the word view is drawn for: the column's width, the text size and
/// the height of a screen in logical pixels, and the device pixels for one
/// logical pixel.
typedef WordSettings = ({
  double width,
  double fontSize,
  double screenHeight,
  double devicePixelRatio,
});

/// How a band's pixels take the reader's theme. [ink] maps the band's
/// lightness from the theme's text color to its paper: words and ink
/// regions. [picture] keeps the band's colors: picture regions.
enum BandTint { ink, picture }

/// A column and the bands that draw its screens.
class WordColumn {
  WordColumn(this.column, this.bands);
  final ReflowColumn column;
  final WordBands bands;

  /// Throws a [StateError] when an invariant of [ReflowColumn] or of
  /// [WordBands] does not hold.
  void checkInvariants() {
    column.checkInvariants();
    bands.checkInvariants(column);
  }
}

/// The bands of each screen of a column, and the sprites that draw the
/// screen's pieces from them. It holds only typed lists, so it crosses
/// isolates as blocks.
///
/// A band is one area of the source page, drawn [pixelsPerPageUnit] pixels
/// for one page unit. Its area is in the pixels of that drawing, with whole
/// pixel edges. A sprite draws one piece: a rectangle of its band's pixels,
/// placed on its screen by an [RSTransform] in logical pixels from the
/// screen's top left corner: the column's left edge and the top of the
/// screen's first line ([ReflowColumn.screenTop]).
///
/// Invariants, which [checkInvariants] makes sure of:
/// - Each list has its entries for each screen, band and sprite.
/// - Screens cover the bands in order, and bands cover the sprites in
///   order. Every band has a sprite.
/// - The sprites of a screen draw each of its pieces once.
/// - A sprite's rectangle lies inside its band.
/// - A band is at most [maxBandSide] pixels on each side.
/// - The bands of a screen hold at most twice [screenPixels].
class WordBands {
  WordBands({
    required this.paperLightness,
    required this.inkLightness,
    required this.screenPixels,
    required this.screenStarts,
    required this.bands,
    required this.spriteStarts,
    required this.spritePieces,
    required this.rects,
    required this.transforms,
  });

  /// The lightness of the page's paper and ink in the bands' pixels (see
  /// [PageAnalysis.paperLightness]).
  final double paperLightness;
  final double inkLightness;

  /// The device pixels of one screen of the column.
  final int screenPixels;

  /// For each screen: its first band. One more entry ends the last screen.
  final Int32List screenStarts;

  /// For each band: its tint, its pixels per page unit, and its area's
  /// left, top, width and height.
  final Int32List bands;

  /// For each band: its first sprite. One more entry ends the last band.
  final Int32List spriteStarts;

  /// For each sprite: the piece of the column that it draws.
  final Int32List spritePieces;

  /// For each sprite: its rectangle in its band's image (left, top, right
  /// and bottom), in pixels from the band's top left corner.
  final Float32List rects;

  /// For each sprite: its [RSTransform] (scos, ssin, tx and ty), which
  /// places the rectangle on its screen in logical pixels.
  final Float32List transforms;

  /// The largest side of a band, in pixels. GPUs take textures this large.
  static const maxBandSide = 4096;

  static const _bandStride = 6;

  int get bandCount => spriteStarts.length - 1;
  int get spriteCount => spritePieces.length;

  BandTint tint(int band) => BandTint.values[bands[band * _bandStride]];
  int pixelsPerPageUnit(int band) => bands[band * _bandStride + 1];
  Rect area(int band) => Rect.fromLTWH(
    bands[band * _bandStride + 2].toDouble(),
    bands[band * _bandStride + 3].toDouble(),
    bands[band * _bandStride + 4].toDouble(),
    bands[band * _bandStride + 5].toDouble(),
  );

  Rect rect(int sprite) => Rect.fromLTRB(
    rects[sprite * 4],
    rects[sprite * 4 + 1],
    rects[sprite * 4 + 2],
    rects[sprite * 4 + 3],
  );

  RSTransform transform(int sprite) => RSTransform(
    transforms[sprite * 4],
    transforms[sprite * 4 + 1],
    transforms[sprite * 4 + 2],
    transforms[sprite * 4 + 3],
  );

  /// The band that holds [sprite].
  int bandOfSprite(int sprite) {
    var band = 0;
    while (spriteStarts[band + 1] <= sprite) {
      band++;
    }
    return band;
  }

  /// The pixels of the bands of [screen].
  int screenBandPixels(int screen) {
    var pixels = 0;
    for (
      var band = screenStarts[screen];
      band < screenStarts[screen + 1];
      band++
    ) {
      pixels += bands[band * _bandStride + 4] * bands[band * _bandStride + 5];
    }
    return pixels;
  }

  /// Throws a [StateError] when an invariant of the class comment does not
  /// hold for [column]. It runs only on demand, from a test or a debug
  /// switch.
  void checkInvariants(ReflowColumn column) {
    void require(bool holds, String rule) {
      if (!holds) throw StateError('Word bands: $rule.');
    }

    require(
      screenStarts.length == column.screenCount + 1 &&
          bands.length == bandCount * _bandStride &&
          rects.length == spriteCount * 4 &&
          transforms.length == spriteCount * 4,
      'each screen, band and sprite has its entries',
    );
    require(
      screenStarts.first == 0 &&
          screenStarts.last == bandCount &&
          spriteStarts.first == 0 &&
          spriteStarts.last == spriteCount,
      'screens cover the bands and bands cover the sprites',
    );
    for (var screen = 0; screen < column.screenCount; screen++) {
      require(
        screenStarts[screen] <= screenStarts[screen + 1],
        'screen $screen has bands in order',
      );
      final firstPiece = column.lineStarts[column.screenStarts[screen]];
      final endPiece = column.lineStarts[column.screenStarts[screen + 1]];
      final drawn = <int>{};
      for (
        var band = screenStarts[screen];
        band < screenStarts[screen + 1];
        band++
      ) {
        require(
          spriteStarts[band] < spriteStarts[band + 1],
          'band $band has a sprite',
        );
        final area = this.area(band);
        require(
          area.width > 0 &&
              area.height > 0 &&
              area.width <= maxBandSide &&
              area.height <= maxBandSide,
          'band $band is at most $maxBandSide pixels on a side',
        );
        for (
          var sprite = spriteStarts[band];
          sprite < spriteStarts[band + 1];
          sprite++
        ) {
          final piece = spritePieces[sprite];
          require(
            piece >= firstPiece && piece < endPiece && drawn.add(piece),
            'sprite $sprite draws a piece of screen $screen once',
          );
          final rect = this.rect(sprite);
          require(
            rect.left >= 0 &&
                rect.top >= 0 &&
                rect.right <= area.width &&
                rect.bottom <= area.height &&
                rect.width > 0 &&
                rect.height > 0,
            'sprite $sprite lies inside its band',
          );
        }
      }
      require(
        drawn.length == endPiece - firstPiece,
        'screen $screen draws each of its pieces',
      );
      require(
        screenBandPixels(screen) <= 2 * screenPixels,
        'the bands of screen $screen hold at most twice its pixels',
      );
    }
  }
}

/// The column of a page and the bands of its screens, at once. It runs in a
/// hop, so a frame does no layout work.
WordColumn planWordColumn(
  ({
    PageGeometry geometry,
    PageAnalysis analysis,
    double bodyLineHeight,
    WordSettings settings,
  })
  page,
) {
  final settings = page.settings;
  final column = layoutColumn((
    geometry: page.geometry,
    analysis: page.analysis,
    bodyLineHeight: page.bodyLineHeight,
    settings: ColumnSettings(
      width: settings.width,
      fontSize: settings.fontSize,
      screenHeight: settings.screenHeight,
    ),
  ));
  return WordColumn(
    column,
    _planBands(column, page.geometry, page.analysis, settings.devicePixelRatio),
  );
}

/// A band joins the pieces of more source lines while its area stays within
/// this many times the areas of their own boxes, so a joined band holds
/// little that the screen does not draw.
const _joinSlack = 1.5;

/// The pieces of one band while it is planned, and its area in page units.
class _Part {
  _Part(this.tint, this.pixelsPerPageUnit, this.line, this.box, int piece)
    : pieces = [piece];
  final BandTint tint;
  final int pixelsPerPageUnit;

  /// The source line of the part's words, or -1 for a region.
  final int line;
  Rect box;
  final List<int> pieces;

  /// The pixels of the boxes of the parts that the band joined, once the
  /// parts are planned.
  var ownPixels = 0;

  int get pixels => _pixelArea(box, pixelsPerPageUnit);

  /// Whether [box] fits one band at this part's scale.
  bool fits(Rect box) {
    final pixels = _pixelBox(box, pixelsPerPageUnit);
    return pixels.width <= WordBands.maxBandSide &&
        pixels.height <= WordBands.maxBandSide;
  }

  /// Whether this part's band can take [other]: both hold words, with one
  /// tint and one scale.
  bool takes(_Part other) =>
      line >= 0 &&
      other.line >= 0 &&
      tint == other.tint &&
      pixelsPerPageUnit == other.pixelsPerPageUnit;
}

/// [box], in page units, in the whole pixels of the page drawn
/// [pixelsPerPageUnit] wide that cover it.
Rect _pixelBox(Rect box, int pixelsPerPageUnit) => Rect.fromLTRB(
  (box.left * pixelsPerPageUnit).floorToDouble(),
  (box.top * pixelsPerPageUnit).floorToDouble(),
  (box.right * pixelsPerPageUnit).ceilToDouble(),
  (box.bottom * pixelsPerPageUnit).ceilToDouble(),
);

int _pixelArea(Rect box, int pixelsPerPageUnit) {
  final pixels = _pixelBox(box, pixelsPerPageUnit);
  return (pixels.width * pixels.height).toInt();
}

/// The bands and sprites of every screen of [column].
///
/// A piece renders at its own scale in device pixels, so it draws at one
/// band pixel for one device pixel. A word wider than the column and a
/// region that fits the column or the screen have their own scale. The
/// pieces of one source line with one scale and one tint make a part, and
/// a region is a part alone. Consecutive word parts join into one band
/// while the band stays within [_joinSlack] times their own areas and the
/// screen's bands within twice its pixels, because each band costs a render
/// of the page. A part wider or taller than [WordBands.maxBandSide] splits.
/// Only when a screen's own parts hold more than twice its pixels, such as
/// a screen much taller than it is wide, does the screen render at a lower
/// resolution.
WordBands _planBands(
  ReflowColumn column,
  PageGeometry geometry,
  PageAnalysis analysis,
  double devicePixelRatio,
) {
  final wordLines = Int32List(geometry.wordCount);
  for (var line = 0; line < geometry.lineCount; line++) {
    wordLines.fillRange(
      geometry.lineStarts[line],
      geometry.lineStarts[line + 1],
      line,
    );
  }
  final screenPixels =
      (column.width * devicePixelRatio).ceil() *
      (column.screenHeight * devicePixelRatio).ceil();
  final budget = 2 * screenPixels;
  final screenStarts = <int>[0];
  final bands = <int>[];
  final spriteStarts = <int>[0];
  final spritePieces = <int>[];
  final rects = <double>[];
  final transforms = <double>[];

  /// The parts of [pieces] at [resolution] times one band pixel for one
  /// device pixel.
  List<_Part> partsOf(Iterable<int> pieces, double resolution) {
    final parts = <_Part>[];
    for (final piece in pieces) {
      final source = column.source(piece), target = column.target(piece);
      final region = column.region(piece);
      final tint =
          region >= 0 && analysis.regionKind(region) == RegionKind.picture
          ? BandTint.picture
          : BandTint.ink;
      final pixelsPerPageUnit = math.max(
        1,
        math.min(
          (target.width / source.width * devicePixelRatio * resolution).round(),
          // A piece fits a band, with a pixel to spare for its rounded edges.
          ((WordBands.maxBandSide - 2) / math.max(source.width, source.height))
              .floor(),
        ),
      );
      final line = region >= 0 ? -1 : wordLines[column.word(piece)];
      final own = _Part(tint, pixelsPerPageUnit, line, source, piece);
      final part = parts.reversed
          .where((part) => part.line == line && part.takes(own))
          .firstOrNull;
      final joined = part?.box.expandToInclude(source);
      if (part != null && part.fits(joined!)) {
        part
          ..box = joined
          ..pieces.add(piece);
      } else {
        parts.add(own);
      }
    }
    for (final part in parts) {
      part.ownPixels = part.pixels;
    }
    return parts;
  }

  for (var screen = 0; screen < column.screenCount; screen++) {
    final first = column.lineStarts[column.screenStarts[screen]];
    final end = column.lineStarts[column.screenStarts[screen + 1]];
    final pieces = [for (var piece = first; piece < end; piece++) piece];
    var resolution = 1.0;
    var parts = partsOf(pieces, resolution);
    int total() => parts.fold(0, (sum, part) => sum + part.pixels);
    while (total() > budget && resolution > 1e-3) {
      resolution *= math.sqrt(budget / total()) * .98;
      parts = partsOf(pieces, resolution);
    }
    var spare = budget - total();
    final joined = <_Part>[];
    for (final part in parts) {
      final band = joined.lastOrNull;
      if (band != null && band.takes(part)) {
        final box = band.box.expandToInclude(part.box);
        final pixels = _pixelArea(box, band.pixelsPerPageUnit);
        final extra = pixels - band.pixels - part.pixels;
        final own = band.ownPixels + part.ownPixels;
        if (pixels <= _joinSlack * own && extra <= spare && band.fits(box)) {
          spare -= extra;
          band
            ..box = box
            ..ownPixels = own
            ..pieces.addAll(part.pieces);
          continue;
        }
      }
      joined.add(part);
    }

    for (final band in joined) {
      final perUnit = band.pixelsPerPageUnit;
      final area = _pixelBox(band.box, perUnit);
      bands.addAll([
        band.tint.index,
        perUnit,
        area.left.toInt(),
        area.top.toInt(),
        area.width.toInt(),
        area.height.toInt(),
      ]);
      for (final piece in band.pieces) {
        _addSprite(
          column,
          piece,
          perUnit,
          area.topLeft,
          column.screenTop(screen),
          devicePixelRatio,
          spritePieces,
          rects,
          transforms,
        );
      }
      spriteStarts.add(spritePieces.length);
    }
    screenStarts.add(spriteStarts.length - 1);
  }
  return WordBands(
    paperLightness: analysis.paperLightness,
    inkLightness: analysis.inkLightness,
    screenPixels: screenPixels,
    screenStarts: Int32List.fromList(screenStarts),
    bands: Int32List.fromList(bands),
    spriteStarts: Int32List.fromList(spriteStarts),
    spritePieces: Int32List.fromList(spritePieces),
    rects: Float32List.fromList(rects),
    transforms: Float32List.fromList(transforms),
  );
}

/// Adds the sprite of [piece], drawn from a band [pixelsPerPageUnit] pixels
/// for one page unit whose top left pixel of the page is [origin], on a
/// screen whose top is [screenTop] in the column.
///
/// The sprite's rectangle holds the whole pixels that cover the piece's
/// source. Its image turns by the piece's rotation about the target's
/// center. A piece that renders at its target's scale draws at one band
/// pixel for one device pixel, so its size may differ from its target by
/// the rounding of the band's scale to whole pixels: at most half a pixel
/// for each page width. A level one lands on whole device pixels, so
/// drawing copies its pixels.
void _addSprite(
  ReflowColumn column,
  int piece,
  int pixelsPerPageUnit,
  Offset origin,
  double screenTop,
  double devicePixelRatio,
  List<int> spritePieces,
  List<double> rects,
  List<double> transforms,
) {
  final source = column.source(piece);
  final target = column.target(piece).shift(Offset(0, -screenTop));
  final rect = _pixelBox(source, pixelsPerPageUnit).shift(-origin);
  final center = source.center * pixelsPerPageUnit.toDouble() - origin;
  final wanted = target.width / source.width * devicePixelRatio;
  final exact = (wanted - pixelsPerPageUnit).abs() <= .5;
  // Logical pixels for one band pixel.
  final scale = exact
      ? 1 / devicePixelRatio
      : target.width / source.width / pixelsPerPageUnit;
  final rotation = column.rotation(piece);
  final scos = scale * math.cos(rotation), ssin = scale * math.sin(rotation);
  final ax = rect.left - center.dx, ay = rect.top - center.dy;
  var tx = target.center.dx + scos * ax - ssin * ay;
  var ty = target.center.dy + ssin * ax + scos * ay;
  if (exact && rotation == 0) {
    tx = (tx * devicePixelRatio).roundToDouble() / devicePixelRatio;
    ty = (ty * devicePixelRatio).roundToDouble() / devicePixelRatio;
  }
  spritePieces.add(piece);
  rects.addAll([rect.left, rect.top, rect.right, rect.bottom]);
  transforms.addAll([scos, ssin, tx, ty]);
}
