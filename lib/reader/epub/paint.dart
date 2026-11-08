// Draws one laid page into a picture.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'layout.dart';

/// The decoded images of a section, by path. A page whose image is missing
/// draws an outline in its place.
typedef PageImages = Map<String, ui.Image>;

/// Draws [page], with the images in [images].
ui.Picture drawPage(LaidPage page, PageImages images) {
  final settings = page.settings;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final bounds = ui.Rect.fromLTWH(0, 0, settings.width, settings.height);
  canvas.drawRect(bounds, ui.Paint()..color = settings.paper);
  final height = page.height.clamp(0, settings.height).toDouble();
  canvas
    ..save()
    ..clipRect(ui.Rect.fromLTWH(0, 0, settings.width, height))
    ..translate(0, -page.top);
  final ink = ui.Paint()..color = settings.ink;
  for (final piece in page.pieces) {
    canvas.save();
    if (piece.shown.isFinite) {
      canvas.clipRect(
        ui.Rect.fromLTWH(0, piece.y, settings.width, piece.shown),
      );
    }
    canvas.drawParagraph(piece.paragraph, ui.Offset(piece.x, piece.y));
    for (final (box, held) in piece.inlines) {
      final rect = box.shift(ui.Offset(piece.x, piece.y));
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
        canvas.drawRect(rect, ink);
      case ImageDecoration(:final rect, :final path):
        _image(canvas, images[path], rect, ink);
      case MarkerDecoration(:final paragraph, :final offset):
        canvas.drawParagraph(paragraph, offset);
    }
  }
  canvas.restore();
  return recorder.endRecording();
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
