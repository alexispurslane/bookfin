import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bookfin/reader/column_layout.dart';
import 'package:bookfin/reader/page_geometry.dart';
import 'package:bookfin/reader/pdf.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart' as native;

import 'ocr_hop_test.dart' show runInWorker;
import 'page_analysis_test.dart'
    show FixtureRecognition, equationPage, footnotePage, ravenPage;
import 'running_lines_test.dart' show marginsBook;

/// The boxes, in pixels (left, top, right and bottom), of the marks of ink
/// in the text lines of a page that [column] does not show.
///
/// [raster] is the page drawn 1600 pixels wide, and [geometry] its reflow
/// geometry. A pixel is ink when its luminance is below half of the paper's,
/// the luminance that 90 percent of the pixels do not exceed. A text line
/// spans from its top to its bottom, and from one line height before its
/// first word to one line height after its last. A piece shows the pixels of
/// its source rectangle. The hyphen of a rejoined hyphen pair is left out on
/// purpose, so the whole box of a word with a hyphen counts as shown. Marks
/// smaller than a sixth of the median line height in both directions are
/// specks.
List<List<int>> lostInk(
  PageGeometry geometry,
  ReflowColumn column,
  PdfRaster raster,
) {
  final width = raster.width, height = raster.height;
  final luma = Uint8List(width * height);
  final histogram = Int32List(256);
  for (var pixel = 0; pixel < luma.length; pixel++) {
    final byte = pixel * 4;
    luma[pixel] =
        (raster.bgra[byte] * 29 +
            raster.bgra[byte + 1] * 150 +
            raster.bgra[byte + 2] * 77) >>
        8;
    histogram[luma[pixel]]++;
  }
  var paper = 0;
  for (var count = 0; paper < 255; paper++) {
    count += histogram[paper];
    if (count * 10 >= luma.length * 9) break;
  }

  // 1 for a pixel of a text line that no piece shows.
  final open = Uint8List(width * height);
  void fill(double left, double top, double right, double bottom, int value) {
    for (
      var y = (top * width).floor().clamp(0, height);
      y < (bottom * width).ceil().clamp(0, height);
      y++
    ) {
      open.fillRange(
        y * width + (left * width).floor().clamp(0, width),
        y * width + (right * width).ceil().clamp(0, width),
        value,
      );
    }
  }

  final heights = <double>[];
  for (var line = 0; line < geometry.lineCount; line++) {
    final lineHeight = geometry.lineHeight(line);
    heights.add(lineHeight * width);
    final left = geometry.lineLeft(line), right = geometry.lineRight(line);
    final atLeft = geometry.lineBaselineAt(line, left);
    final atRight = geometry.lineBaselineAt(line, right);
    final descender = geometry.lineDescender(line);
    fill(
      left - lineHeight,
      math.min(atLeft, atRight) + descender - lineHeight,
      right + lineHeight,
      math.max(atLeft, atRight) + descender,
      1,
    );
  }
  heights.sort();
  final speck = heights[heights.length ~/ 2] / 6;
  for (var piece = 0; piece < column.pieceCount; piece++) {
    final source = column.source(piece);
    fill(source.left, source.top, source.right, source.bottom, 0);
    final word = column.word(piece);
    if (word >= 0 && geometry.hyphens[word] > 0) {
      final box = geometry.boxes;
      fill(
        box[word * 4],
        box[word * 4 + 1],
        box[word * 4 + 2],
        box[word * 4 + 3],
        0,
      );
    }
  }

  bool lost(int pixel) => open[pixel] != 0 && luma[pixel] * 2 < paper;
  final marks = <List<int>>[];
  final stack = <int>[];
  for (var start = 0; start < luma.length; start++) {
    if (!lost(start)) continue;
    var left = width, top = height, right = 0, bottom = 0;
    open[start] = 0;
    stack.add(start);
    while (stack.isNotEmpty) {
      final pixel = stack.removeLast();
      final x = pixel % width, y = pixel ~/ width;
      left = math.min(left, x);
      top = math.min(top, y);
      right = math.max(right, x + 1);
      bottom = math.max(bottom, y + 1);
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          final nx = x + dx, ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= width || ny >= height) continue;
          final next = ny * width + nx;
          if (!lost(next)) continue;
          open[next] = 0;
          stack.add(next);
        }
      }
    }
    if (right - left >= speck || bottom - top >= speck) {
      marks.add([left, top, right, bottom]);
    }
  }
  return marks;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  native.Pdfrx.pdfiumModulePath = Platform.environment['PDFIUM_LIBRARY'];
  native.Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;
  tearDownAll(() => PdfRuntime.instance.shutdown());

  test('no mark of ink in a text line of a fixture page is left out of the '
      'word view, except the hyphen of a rejoined hyphen pair', () async {
    final settings = ColumnSettings(
      width: 360,
      fontSize: 20,
      screenHeight: 640,
    );
    for (final (path, supply) in [
      (ravenPage, FixtureRecognition('scanned-page')),
      (footnotePage, FixtureRecognition('footnote-page')),
      (equationPage, null),
      (marginsBook, null),
    ]) {
      supply?.textArrives.complete();
      final book = await PdfRuntime.instance.open(
        await File(path).readAsBytes(),
        'i' * 64,
        textSupply: supply,
        hop: runInWorker,
      );
      for (var number = 1; number <= book.pageCount; number++) {
        final page = (await book.reflowPage(number))!;
        final column = await page.column(settings);
        expect(
          lostInk(page.geometry, column, await book.render(number, 1600)),
          isEmpty,
          reason: '$path, page $number',
        );
      }
      await book.dispose();
    }
  });
}
