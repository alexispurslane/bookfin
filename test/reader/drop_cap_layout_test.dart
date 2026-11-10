import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bookfin/reader/column_layout.dart';
import 'package:bookfin/reader/page_analysis.dart';
import 'package:bookfin/reader/pdf.dart';
import 'package:bookfin/reader/word_bands.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart' as native;

import 'column_layout_test.dart'
    show Fixture, drawn, lay, lineOf, pieceOf, piecesOf, screenOf, wordsAt;
import 'page_analysis_test.dart' show DrawnPage, FixtureRecognition, ravenPage;

Fixture opening({bool separate = false, int height = 120}) {
  final lines = [
    for (var line = 0; line < 6; line++)
      line * 60 < height
          ? wordsAt(240, 200 + line * 60, 9)
          : wordsAt(100, 200 + line * 60, 10),
  ];
  if (!separate) lines.first.insert(0, [100, 200, 220, 200 + height]);
  final page = DrawnPage(lines);
  if (separate) page.ink([100, 200, 220, 200 + height]);
  final geometry = page.geometry;
  if (!separate) {
    geometry.lineMetrics[0] = 240 / 1600;
    geometry.lineMetrics[3] = (height - 40) / 1600;
  }
  final analyzed = analyzePage((
    width: 1600,
    height: page.height,
    bgra: page.raster.bgra,
    geometry: geometry,
    scanned: true,
  ));
  analyzed.geometry.checkInvariants();
  analyzed.analysis.checkInvariants(analyzed.geometry);
  return (
    geometry: analyzed.geometry,
    analysis: analyzed.analysis,
    bodyLineHeight: analyzed.analysis.bodyLineHeight,
    texts: const [],
  );
}

void expectFloat(ReflowColumn column, int cap, {int? linesBeside}) {
  final box = column.target(cap);
  final first = lineOf(column, cap);
  expect(box.left, closeTo(0, 0.01));
  expect(box.top, closeTo(column.lineTop(first), 0.01));
  var beside = 0;
  var after = first;
  for (var line = first; line < column.lineCount; line++) {
    final body = piecesOf(column, line).where((piece) => piece != cap).toList();
    if (body.isEmpty) continue;
    final top = body.map((piece) => drawn(column, piece).top).reduce(math.min);
    if (top >= box.bottom - 0.01) {
      after = line;
      break;
    }
    expect(
      body.map((piece) => drawn(column, piece).left).reduce(math.min),
      greaterThanOrEqualTo(box.right),
    );
    expect(screenOf(column, line), screenOf(column, first));
    beside++;
  }
  expect(beside, inInclusiveRange(1, 3));
  if (linesBeside != null) expect(beside, linesBeside);
  expect(after, greaterThan(first));
  expect(
    piecesOf(
      column,
      after,
    ).map((piece) => drawn(column, piece).left).reduce(math.min),
    closeTo(0, 0.01),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  native.Pdfrx.pdfiumModulePath = Platform.environment['PDFIUM_LIBRARY'];
  native.Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;
  tearDownAll(() => PdfRuntime.instance.shutdown());

  test(
    'an oversized opening word stays whole beside shorter neighboring lines',
    () {
      final page = opening();
      final column = lay(page, width: 240);
      final cap = pieceOf(column, 0);
      expect(column.source(cap).height, closeTo(120 / 1600, 1e-6));
      expect(column.target(cap).height, closeTo(55.2, 0.01));
      expectFloat(column, cap, linesBeside: 2);
      expect(
        column.pieceItems,
        List.generate(page.geometry.wordCount, (word) => word),
      );
    },
  );

  test('uncovered opening ink floats instead of taking a line of its own', () {
    final page = opening(separate: true);
    final column = lay(page, width: 240);
    final cap = [
      for (var piece = 0; piece < column.pieceCount; piece++)
        if (column.region(piece) >= 0) piece,
    ].single;
    expectFloat(column, cap, linesBeside: 2);
  });

  test('a cap region keeps the saved place of the word it contains', () {
    final page = opening();
    final analysis = PageAnalysis(
      regionBoxes: Float32List.fromList(page.geometry.boxes.take(4).toList()),
      regionKinds: Uint8List.fromList([RegionKind.ink.index]),
      wordRegions: Int32List(page.geometry.wordCount)
        ..fillRange(0, page.geometry.wordCount, -1)
        ..[0] = 0,
      proseLines: Uint8List.fromList(page.analysis.proseLines)..[0] = 0,
      sourceWords: page.analysis.sourceWords,
      bodyLineHeight: page.bodyLineHeight,
    );
    analysis.checkInvariants(page.geometry);
    final column = lay((
      geometry: page.geometry,
      analysis: analysis,
      bodyLineHeight: page.bodyLineHeight,
      texts: const [],
    ), width: 240);
    final cap = column.pieceItems.indexOf(-1);
    expectFloat(column, cap, linesBeside: 2);
    final ranges = Int32List.fromList([
      for (var word = 0; word < page.geometry.wordCount; word++) ...[
        word * 5,
        word * 5 + 4,
      ],
    ]);
    expect(column.firstCharacter(0, ranges, analysis), 0);
    expect(column.screenAt(2, ranges, analysis), 0);
  });

  test('ink beside a continuing paragraph keeps the ordinary region order', () {
    final page = DrawnPage([
      wordsAt(100, 200, 10),
      wordsAt(240, 260, 9),
      wordsAt(240, 320, 9),
      wordsAt(100, 380, 10),
    ])..ink([100, 260, 220, 380]);
    final analyzed = analyzePage((
      width: 1600,
      height: page.height,
      bgra: page.raster.bgra,
      geometry: page.geometry,
      scanned: true,
    ));
    final column = lay((
      geometry: analyzed.geometry,
      analysis: analyzed.analysis,
      bodyLineHeight: analyzed.analysis.bodyLineHeight,
      texts: const [],
    ), width: 240);
    expect(column.pieceItems.indexOf(-1), greaterThan(pieceOf(column, 27)));
  });

  test(
    'a very tall cap holds at most three shorter lines before full width',
    () {
      final page = opening(height: 240);
      final column = lay(page, width: 240);
      expectFloat(column, pieceOf(column, 0), linesBeside: 3);
    },
  );

  test('screens keep a whole cap and its neighboring lines together', () {
    final page = opening();
    for (final height in [40.0, 60.0, 80.0]) {
      final column = lay(page, width: 240, screenHeight: height);
      final cap = pieceOf(column, 0);
      final screen = screenOf(column, lineOf(column, cap));
      final top = column.screenTop(screen);
      expect(column.target(cap).top, greaterThanOrEqualTo(top - 0.01));
      expect(column.target(cap).bottom, lessThanOrEqualTo(top + height + 0.01));
      expectFloat(column, cap);
    }
  });

  test('a taller neighboring word does not split the cap across screens', () {
    final page = opening();
    page.geometry.boxes[11] = 275 / 1600;
    page.geometry.ownBaselines[4] = 275 / 1600;
    page.geometry.ownBaselines[5] = 275 / 1600;
    final column = lay(page, width: 240, screenHeight: 60);
    expectFloat(column, pieceOf(column, 0));
  });

  test('whole caps never cover neighboring words at narrow widths or large sizes', () {
    for (final separate in [false, true]) {
      for (final height in [80, 120, 240]) {
        final page = opening(separate: separate, height: height);
        for (final (width, fontSize, screenHeight) in [
          (60.0, 40.0, 40.0),
          (120.0, 40.0, 80.0),
          (240.0, 20.0, 60.0),
          (360.0, 14.0, 200.0),
        ]) {
          final column = lay(
            page,
            width: width,
            fontSize: fontSize,
            screenHeight: screenHeight,
          );
          final cap = separate
              ? [
                  for (var piece = 0; piece < column.pieceCount; piece++)
                    if (column.region(piece) >= 0) piece,
                ].single
              : pieceOf(column, 0);
          final capBox = drawn(column, cap);
          for (var piece = 0; piece < column.pieceCount; piece++) {
            if (piece == cap) continue;
            final overlap = drawn(column, piece).intersect(capBox);
            expect(
              overlap.width <= 0.01 || overlap.height <= 0.01,
              isTrue,
              reason:
                  'piece $piece; separate $separate; cap $height; width $width; size $fontSize; screen $screenHeight',
            );
          }
          final screen = screenOf(column, lineOf(column, cap));
          expect(
            capBox.bottom,
            lessThanOrEqualTo(column.screenTop(screen) + screenHeight + 0.01),
          );
        }
      }
    }
  });

  test(
    'the public opening-letter fixture keeps its cap in the image bands',
    () async {
      final book = await PdfRuntime.instance.open(
        await File('test/reader/fixtures/reflow/drop-cap-page.pdf')
            .readAsBytes(),
        'e' * 64,
      );
      addTearDown(book.dispose);
      final text = await book.text(1);
      final page = (await book.reflowPage(1))!;
      final attached = await page.attachedText();
      final column = await page.column(
        ColumnSettings(width: 240, fontSize: 20, screenHeight: 200),
      );
      final cap = [
        for (var piece = 0; piece < column.pieceCount; piece++)
          if (column.region(piece) >= 0) piece,
      ].single;
      expectFloat(column, cap, linesBeside: 3);
      final bands = planWordColumn((
        geometry: page.geometry,
        analysis: page.analysis,
        bodyLineHeight: page.bodyLineHeight,
        settings: (
          width: 240.0,
          fontSize: 20.0,
          screenHeight: 200.0,
          devicePixelRatio: 2.625,
        ),
      )).bands;
      bands.checkInvariants(column);
      expect(bands.spritePieces.where((piece) => piece == cap), hasLength(1));
      expect(attached.text.source, text.source);
      expect(attached.text.digest, text.digest);
      for (var screen = 0; screen < column.screenCount; screen++) {
        final place = column.firstCharacter(
          screen,
          attached.attachment!,
          page.analysis,
        );
        expect(place, isNotNull);
        expect(
          column.screenAt(place!, attached.attachment!, page.analysis),
          screen,
        );
      }
    },
  );

  test(
    'Raven floats the whole ONCE word without changing text or saved places',
    () async {
      final supply = FixtureRecognition('scanned-page')..textArrives.complete();
      final book = await PdfRuntime.instance.open(
        await File(ravenPage).readAsBytes(),
        'd' * 64,
        textSupply: supply,
      );
      addTearDown(book.dispose);
      final page = (await book.reflowPage(1))!;
      final attached = await page.attachedText();
      final text = attached.text.source;
      final digest = attached.text.digest;
      final ranges = Int32List.fromList(attached.attachment!);
      final once = text.indexOf('(ee');
      expect(once, greaterThanOrEqualTo(0));
      final word = [
        for (var word = 0; word < page.geometry.wordCount; word++)
          if (ranges[word * 2] == once) word,
      ].single;
      final column = await page.column(
        ColumnSettings(width: 240, fontSize: 20, screenHeight: 200),
      );
      final cap = pieceOf(column, word);
      final next = pieceOf(column, word + 1);
      expect(column.target(cap).top, closeTo(column.target(next).top, 4));
      expect(
        column.target(cap).bottom,
        greaterThan(column.target(next).bottom + 10),
      );
      expectFloat(column, cap, linesBeside: 2);
      for (var screen = 0; screen < column.screenCount; screen++) {
        final character = column.firstCharacter(screen, ranges, page.analysis);
        if (character != null) {
          expect(column.screenAt(character, ranges, page.analysis), screen);
        }
      }
      final again = await page.attachedText();
      expect(again.text.source, text);
      expect(again.text.digest, digest);
      expect(again.attachment, ranges);
    },
  );
}
