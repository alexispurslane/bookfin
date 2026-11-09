// Draws one laid page into a picture.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'layout.dart';
import 'prepare.dart';

/// The decoded images of a page, by path. A path without an entry is not
/// decoded yet, and its image draws as an outline. A path whose entry is
/// null cannot decode, and its image draws its alt text, or an outline
/// without alt text.
typedef PageImages = Map<String, ui.Image?>;

/// Draws [page], with the images in [images].
///
/// Everything draws at its place on the page, from the page's top: the
/// strip position minus the page's top, in double precision. The canvas
/// does not move to the page's top, because its single-precision
/// transform could round a glyph to another pixel row far down the strip,
/// and a page laid out again from its start must draw the same pixels.
ui.Picture drawPage(LaidPage page, PageImages images) {
  final settings = page.settings;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final bounds = ui.Rect.fromLTWH(0, 0, settings.width, settings.height);
  canvas.drawRect(bounds, ui.Paint()..color = settings.paper);
  final height = page.height.clamp(0, settings.height).toDouble();
  canvas
    ..save()
    ..clipRect(ui.Rect.fromLTWH(0, 0, settings.width, height));
  final up = ui.Offset(0, -page.top);
  final ink = ui.Paint()..color = settings.ink;
  void image(DrawnImage image, ui.Rect rect) =>
      _image(canvas, image, images, rect, settings);
  for (final piece in page.pieces) {
    final y = piece.y - page.top;
    _lines(canvas, piece, y, height, settings.width);
    canvas.save();
    if (piece.shown.isFinite) {
      canvas.clipRect(ui.Rect.fromLTWH(0, y, settings.width, piece.shown));
    }
    for (final (box, held) in piece.inlines) {
      final rect = box.shift(ui.Offset(piece.x, y));
      if (held is ui.Paragraph) {
        canvas.drawParagraph(held, rect.topLeft);
      } else if (held is DrawnImage) {
        image(held, rect);
      }
    }
    canvas.restore();
  }
  for (final decoration in page.decorations) {
    switch (decoration) {
      case RuleDecoration(:final rect):
        canvas.drawRect(rect.shift(up), ink);
      case ImageDecoration(:final rect, image: final drawn):
        image(drawn, rect.shift(up));
      case MarkerDecoration(:final paragraph, :final offset):
        canvas.drawParagraph(paragraph, offset + up);
    }
  }
  canvas.restore();
  return recorder.endRecording();
}

/// Draws the lines of [piece], whose top is [y] pixels below the page's
/// top, on a page [height] pixels high and [width] pixels wide. Each line
/// draws at its exact place, clipped to it. Neighboring lines that Flutter
/// draws at their exact places, as at a whole-pixel line height, draw
/// together. The piece's first and last lines are clipped only by the page
/// at their outer edge, unless the piece shows only some of its lines.
void _lines(
  ui.Canvas canvas,
  Piece piece,
  double y,
  double height,
  double width,
) {
  final tops = piece.tops;
  final shifts = piece.shifts;
  final last = shifts.length;
  final shown = piece.shown.isFinite;
  var first = 0;
  while (first < last) {
    var end = first + 1;
    while (end < last && (shifts[end] - shifts[first]).abs() < 1e-3) {
      end++;
    }
    final top = first == 0 && !shown ? 0.0 : y + tops[first];
    final bottom = math.min(
      end == last ? height : y + tops[end],
      y + piece.shown,
    );
    if (bottom > math.max(top, 0) && top < height) {
      final offset = ui.Offset(piece.x, y + shifts[first]);
      if (first == 0 && end == last && !shown) {
        canvas.drawParagraph(piece.paragraph, offset);
      } else {
        canvas
          ..save()
          ..clipRect(ui.Rect.fromLTRB(0, top, width, bottom))
          ..drawParagraph(piece.paragraph, offset)
          ..restore();
      }
    }
    first = end;
  }
}

/// Draws [image] in [rect]: its decoded file from [images], else its alt
/// text in the reader's font, clipped to [rect], when the file cannot
/// decode, else an outline.
void _image(
  ui.Canvas canvas,
  DrawnImage image,
  PageImages images,
  ui.Rect rect,
  PageSettings settings,
) {
  final decoded = images[image.path];
  if (decoded != null) {
    final paint = ui.Paint()..filterQuality = ui.FilterQuality.medium;
    if (image.invert > 0) {
      // CSS invert(p) maps each channel c in 0 to 1 to (1 − 2p)c + p. The
      // matrix's last column is in 0 to 255.
      final scale = 1 - 2 * image.invert;
      final offset = 255 * image.invert;
      paint.colorFilter = ui.ColorFilter.matrix([
        scale, 0, 0, 0, offset, //
        0, scale, 0, 0, offset, //
        0, 0, scale, 0, offset, //
        0, 0, 0, 1, 0, //
      ]);
    }
    canvas.drawImageRect(
      decoded,
      ui.Rect.fromLTWH(
        0,
        0,
        decoded.width.toDouble(),
        decoded.height.toDouble(),
      ),
      rect,
      paint,
    );
    return;
  }
  if (images.containsKey(image.path) && image.alt.isNotEmpty) {
    final builder =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(
              fontFamily: readerFontFamily,
              fontSize: settings.fontSize,
            ),
          )
          ..pushStyle(ui.TextStyle(color: settings.ink))
          ..addText(image.alt);
    final alt = builder.build()
      ..layout(ui.ParagraphConstraints(width: rect.width));
    canvas
      ..save()
      ..clipRect(rect)
      ..drawParagraph(alt, rect.topLeft)
      ..restore();
    alt.dispose();
    return;
  }
  canvas.drawRect(
    rect,
    ui.Paint()
      ..color = settings.ink.withValues(alpha: .3)
      ..style = ui.PaintingStyle.stroke,
  );
}

/// Decodes the images that [pages] show, from the bytes that [bytes] gives
/// for a publication path, at the size that they are drawn at [scale] image
/// pixels per layout pixel. An image that cannot decode has no entry, so it
/// draws as an outline. The trial tests use it; the reader decodes through
/// its page source.
Future<Map<String, ui.Image>> decodeImages(
  Iterable<LaidPage> pages,
  Uint8List? Function(String path) bytes, {
  double scale = 1,
}) async {
  final wanted = <String, ui.Rect>{};
  for (final page in pages) {
    for (final piece in page.pieces) {
      for (final (box, held) in piece.inlines) {
        if (held is DrawnImage) wanted[held.path] = box;
      }
    }
    for (final decoration in page.decorations) {
      if (decoration is ImageDecoration) {
        wanted[decoration.path] = decoration.rect;
      }
    }
  }
  final images = <String, ui.Image>{};
  await Future.wait([
    for (final MapEntry(key: path, value: rect) in wanted.entries)
      if (bytes(path) case final encoded?)
        () async {
          try {
            final codec = await ui.instantiateImageCodec(
              encoded,
              targetWidth: (rect.width * scale).ceil().clamp(1, 4096),
            );
            images[path] = (await codec.getNextFrame()).image;
            codec.dispose();
          } catch (_) {
            // A broken image draws as an outline.
          }
        }(),
  ]);
  return images;
}
