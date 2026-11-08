// Draws one page of a laid-out section into a picture, for the trial
// renderer.
import 'dart:ui' as ui;

import 'layout.dart';

/// The decoded images of a section, by path. A page whose image is missing
/// draws an outline in its place.
typedef PageImages = Map<String, ui.Image>;

/// Draws page [index] of [chapter], with the images in [images].
ui.Picture drawPage(ChapterLayout chapter, int index, PageImages images) {
  final theme = chapter.theme;
  final page = chapter.pages[index];
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final bounds = ui.Rect.fromLTWH(0, 0, theme.width, theme.height);
  canvas.drawRect(bounds, ui.Paint()..color = theme.paper);
  final height = (page.endY - page.startY).clamp(0, theme.height).toDouble();
  canvas
    ..save()
    ..clipRect(ui.Rect.fromLTWH(0, 0, theme.width, height))
    ..translate(0, -page.startY);
  final window = ui.Rect.fromLTRB(0, page.startY, theme.width, page.endY);
  final ink = ui.Paint()..color = theme.ink;
  for (final piece in chapter.piecesOn(page)) {
    canvas.save();
    if (piece.shown.isFinite) {
      canvas.clipRect(ui.Rect.fromLTWH(0, piece.y, theme.width, piece.shown));
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
  for (final decoration in chapter.decorations) {
    switch (decoration) {
      case RuleDecoration(:final rect) when rect.overlaps(window):
        canvas.drawRect(rect, ink);
      case ImageDecoration(:final rect, :final path) when rect.overlaps(window):
        _image(canvas, images[path], rect, ink);
      case MarkerDecoration(:final paragraph, :final offset)
          when offset.dy >= page.startY && offset.dy < page.endY:
        canvas.drawParagraph(paragraph, offset);
      default:
        break;
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

/// Decodes the images that [chapter]'s pages [pages] show, at the size
/// that they are drawn at [scale] image pixels per layout pixel.
Future<PageImages> decodeImages(
  ChapterLayout chapter,
  Iterable<int> pages, {
  double scale = 1,
}) async {
  final wanted = <String, ui.Rect>{};
  for (final index in pages) {
    final page = chapter.pages[index];
    final window = ui.Rect.fromLTRB(
      0,
      page.startY,
      chapter.theme.width,
      page.endY,
    );
    for (final piece in chapter.piecesOn(page)) {
      for (final (box, held) in piece.inlines) {
        if (held is String) wanted[held] = box;
      }
    }
    for (final decoration in chapter.decorations) {
      if (decoration is ImageDecoration && decoration.rect.overlaps(window)) {
        wanted[decoration.path] = decoration.rect;
      }
    }
  }
  final images = <String, ui.Image>{};
  await Future.wait([
    for (final MapEntry(key: path, value: rect) in wanted.entries)
      if (chapter.section.input.resource(path) case final bytes?)
        () async {
          try {
            final codec = await ui.instantiateImageCodec(
              bytes,
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
