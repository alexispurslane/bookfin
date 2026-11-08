// Draws one laid page into a picture.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'layout.dart';

/// The decoded images of a section, by path. A page whose image is missing
/// draws an outline in its place.
typedef PageImages = Map<String, ui.Image>;

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
      } else if (held is String) {
        _image(canvas, images[held], rect, ink);
      }
    }
    canvas.restore();
  }
  for (final decoration in page.decorations) {
    switch (decoration) {
      case RuleDecoration(:final rect):
        canvas.drawRect(rect.shift(up), ink);
      case ImageDecoration(:final rect, :final path):
        _image(canvas, images[path], rect.shift(up), ink);
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

void _image(ui.Canvas canvas, ui.Image? image, ui.Rect rect, ui.Paint ink) {
  if (image == null) {
    canvas.drawRect(
      rect,
      ui.Paint()
        ..color = ink.color.withValues(alpha: .3)
        ..style = ui.PaintingStyle.stroke,
    );
    return;
  }
  canvas.drawImageRect(
    image,
    ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    rect,
    ui.Paint()..filterQuality = ui.FilterQuality.medium,
  );
}

/// Decodes the images that [pages] show, from the bytes that [bytes] gives
/// for a publication path, at the size that they are drawn at [scale] image
/// pixels per layout pixel.
Future<PageImages> decodeImages(
  Iterable<LaidPage> pages,
  Uint8List? Function(String path) bytes, {
  double scale = 1,
}) async {
  final wanted = <String, ui.Rect>{};
  for (final page in pages) {
    for (final piece in page.pieces) {
      for (final (box, held) in piece.inlines) {
        if (held is String) wanted[held] = box;
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
