import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset, Rect;

import 'package:bookfin/reader/column_layout.dart';
import 'package:bookfin/reader/page_analysis.dart';
import 'package:bookfin/reader/page_geometry.dart';
import 'package:bookfin/reader/pdf.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart' as native;

import 'ocr_hop_test.dart' show runInWorker;
import 'page_analysis_test.dart'
    show
        DrawnPage,
        DrawnPdf,
        FixtureRecognition,
        equationPage,
        footnotePage,
        proseLines,
        ravenPage,
        wordTexts;
import 'page_geometry_test.dart' show layoutFixture;

/// The device pixels for one logical pixel on a Pixel 8.
const devicePixelRatio = 2.625;

/// One device pixel, in logical pixels.
const devicePixel = 1 / devicePixelRatio;

/// A reflowed page and the text of each of its words. Only the tests read
/// the text, to find words. The layout never reads it.
typedef Fixture = ({
  PageGeometry geometry,
  PageAnalysis analysis,
  double bodyLineHeight,
  List<String> texts,
});

ReflowColumn lay(
  Fixture page, {
  double width = 360,
  double fontSize = 20,
  double screenHeight = 640,
}) {
  final column = layoutColumn((
    geometry: page.geometry,
    analysis: page.analysis,
    bodyLineHeight: page.bodyLineHeight,
    settings: ColumnSettings(
      width: width,
      fontSize: fontSize,
      screenHeight: screenHeight,
    ),
  ));
  column.checkInvariants();
  return column;
}

/// The piece that shows [word], which shows once.
int pieceOf(ReflowColumn column, int word) => [
  for (var piece = 0; piece < column.pieceCount; piece++)
    if (column.word(piece) == word) piece,
].single;

/// The line that holds [piece].
int lineOf(ReflowColumn column, int piece) {
  var line = 0;
  while (column.lineStarts[line + 1] <= piece) {
    line++;
  }
  return line;
}

/// The screen that holds [line].
int screenOf(ReflowColumn column, int line) {
  var screen = 0;
  while (column.screenStarts[screen + 1] <= line) {
    screen++;
  }
  return screen;
}

/// The pieces of [line].
Iterable<int> piecesOf(ReflowColumn column, int line) sync* {
  for (
    var piece = column.lineStarts[line];
    piece < column.lineStarts[line + 1];
    piece++
  ) {
    yield piece;
  }
}

/// Where the point ([x], [y]) of the page lands in the column, when the
/// source image of [piece] is drawn on its target.
Offset toColumn(ReflowColumn column, int piece, double x, double y) {
  final source = column.source(piece), target = column.target(piece);
  final scale = target.width / source.width;
  final dx = (x - source.center.dx) * scale;
  final dy = (y - source.center.dy) * scale;
  final turn = column.rotation(piece);
  return target.center +
      Offset(
        dx * math.cos(turn) - dy * math.sin(turn),
        dx * math.sin(turn) + dy * math.cos(turn),
      );
}

/// The box around the drawn image of [piece], turned.
Rect drawn(ReflowColumn column, int piece) {
  final source = column.source(piece);
  final corners = [
    for (final corner in [
      source.topLeft,
      source.topRight,
      source.bottomLeft,
      source.bottomRight,
    ])
      toColumn(column, piece, corner.dx, corner.dy),
  ];
  return Rect.fromLTRB(
    corners.map((point) => point.dx).reduce(math.min),
    corners.map((point) => point.dy).reduce(math.min),
    corners.map((point) => point.dx).reduce(math.max),
    corners.map((point) => point.dy).reduce(math.max),
  );
}

/// The source line of [word].
int sourceLineOf(PageGeometry geometry, int word) {
  var line = 0;
  while (geometry.lineStarts[line + 1] <= word) {
    line++;
  }
  return line;
}

/// The first word whose text and the texts after it are [words].
int find(Fixture page, List<String> words) => [
  for (var word = 0; word + words.length <= page.texts.length; word++)
    if ([
          for (var index = 0; index < words.length; index++)
            page.texts[word + index],
        ].join(' ') ==
        words.join(' '))
      word,
].first;

const _block = 1, _paragraph = 2, _line = 3, _word = 4;

/// A layout record of a page [width] by [height] pixels with the blocks
/// [blocks]: a picture block has a box and no lines, and a text block has
/// one paragraph of lines of word boxes on flat baselines.
Int32List layoutOfBlocks(
  int width,
  int height,
  List<({List<int>? picture, List<List<List<int>>> lines})> blocks,
) {
  final values = <int>[0, 0, 0, width, height, 0, 0, 0, 0];
  for (final block in blocks) {
    final picture = block.picture;
    if (picture != null) {
      values.addAll([_block, ...picture, 9, 0, 0, 0]);
      continue;
    }
    final boxes = block.lines.expand((line) => line);
    final box = [
      boxes.map((box) => box[0]).reduce(math.min),
      boxes.map((box) => box[1]).reduce(math.min),
      boxes.map((box) => box[2]).reduce(math.max),
      boxes.map((box) => box[3]).reduce(math.max),
    ];
    values.addAll([_block, ...box, 1, 0, 0, 0]);
    values.addAll([_paragraph, ...box, 1, 0, 0, 0]);
    for (final line in block.lines) {
      final left = line.first[0], right = line.last[2];
      final top = line.map((box) => box[1]).reduce(math.min);
      final bottom = line.map((box) => box[3]).reduce(math.max);
      values.addAll([
        _line,
        left,
        top,
        right,
        bottom,
        left,
        bottom,
        right,
        bottom,
      ]);
      for (final box in line) {
        values.addAll([_word, ...box, box[0], box[3], box[2], box[3]]);
      }
    }
  }
  return Int32List.fromList(values);
}

/// A made-up page of blocks, drawn as black word boxes on white paper.
class BlockPage extends DrawnPage {
  BlockPage(this.blocks) : super([for (final block in blocks) ...block.lines]);
  final List<({List<int>? picture, List<List<List<int>>> lines})> blocks;

  @override
  PageGeometry get geometry =>
      pageGeometryFromLayout(layoutOfBlocks(1600, height, blocks));
}

/// A line of [count] words 100 pixels wide and 40 tall, from [left] at
/// [top], with gaps of 16 pixels.
List<List<int>> wordsAt(int left, int top, int count) => [
  for (var word = 0; word < count; word++)
    [left + word * 116, top, left + word * 116 + 100, top + 40],
];

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

  Future<Fixture> reflowed(String path, {PdfTextSupply? textSupply}) async {
    final pdf = await open(path, textSupply: textSupply);
    final page = (await pdf.reflowPage(1))!;
    final attached = await page.attachedText();
    return (
      geometry: page.geometry,
      analysis: page.analysis,
      bodyLineHeight: page.bodyLineHeight,
      texts: wordTexts(
        page.geometry,
        attached.attachment!,
        attached.text.source,
      ),
    );
  }

  Future<Fixture> equation() => reflowed(equationPage);
  Future<Fixture> gibbon() => reflowed(
    footnotePage,
    textSupply: FixtureRecognition('footnote-page')..textArrives.complete(),
  );
  Future<Fixture> raven() => reflowed(
    ravenPage,
    textSupply: FixtureRecognition('scanned-page')..textArrives.complete(),
  );

  /// The skewed Raven page. Its PDF is not kept, so it is analyzed on white
  /// paper: its words and regions come from its layout record alone.
  Fixture skewed() {
    final record = layoutFixture('skewed-page');
    final width = record[3], height = record[4];
    final analyzed = analyzePage((
      width: width,
      height: height,
      bgra: Uint8List(width * height * 4)
        ..fillRange(0, width * height * 4, 255),
      geometry: pageGeometryFromLayout(record),
      scanned: true,
    ));
    return (
      geometry: analyzed.geometry,
      analysis: analyzed.analysis,
      bodyLineHeight: analyzed.analysis.bodyLineHeight,
      texts: const [],
    );
  }

  group('wrapping', () {
    test('words wrap in reading order, every region of the content shows, and '
        'no line is wider than the column', () async {
      for (final page in [await gibbon(), await equation(), await raven()]) {
        for (final (width, fontSize) in [
          (240.0, 20.0),
          (360.0, 14.0),
          (600.0, 40.0),
        ]) {
          final column = lay(page, width: width, fontSize: fontSize);
          final words = [
            for (var piece = 0; piece < column.pieceCount; piece++)
              if (column.word(piece) >= 0) column.word(piece),
          ];
          expect(words, [
            for (var word = 0; word < page.geometry.wordCount; word++)
              if (page.analysis.wordRegions[word] < 0) word,
          ]);
          expect(
            [
              for (var piece = 0; piece < column.pieceCount; piece++)
                if (column.region(piece) >= 0) column.region(piece),
            ]..sort(),
            [
              for (var region = 0; region < page.analysis.regionCount; region++)
                if (page.analysis.isContentRegion(region, page.geometry))
                  region,
            ],
          );
          for (var piece = 0; piece < column.pieceCount; piece++) {
            final target = column.target(piece);
            expect(target.left, greaterThanOrEqualTo(-0.01));
            expect(target.right, lessThanOrEqualTo(width + 0.01));
          }
          expect(column.lineCount, greaterThan(page.geometry.lineCount ~/ 2));
        }
      }
    });

    test('a raised footnote mark and a closing quote that split off their '
        'word stay at their source gap and height beside it', () async {
      final page = await gibbon();
      final geometry = page.geometry;
      final city = find(page, ['city.']);
      final marks = [
        for (var word = 1; word < geometry.wordCount; word++)
          if (page.analysis.sourceWords[word] < 0 &&
              sourceLineOf(geometry, word) == sourceLineOf(geometry, word - 1))
            word,
      ];
      expect(marks, contains(city + 1));
      for (final fontSize in [14.0, 20.0, 40.0]) {
        final column = lay(page, width: 300, fontSize: fontSize);
        for (final mark in marks) {
          final piece = pieceOf(column, mark),
              before = pieceOf(column, mark - 1);
          final line = lineOf(column, piece);
          expect(lineOf(column, before), line, reason: 'mark $mark');
          final scale = column.target(piece).width / column.source(piece).width;
          final sourceGap =
              geometry.boxes[mark * 4] - geometry.boxes[(mark - 1) * 4 + 2];
          expect(
            column.target(piece).left - column.target(before).right,
            closeTo(sourceGap * scale, devicePixel),
            reason: 'mark $mark',
          );
          final x =
              (geometry.boxes[mark * 4] + geometry.boxes[mark * 4 + 2]) / 2;
          final sourceLine = sourceLineOf(geometry, mark);
          final baseline = geometry.lineBaselineAt(sourceLine, x);
          final bottom = geometry.boxes[mark * 4 + 3];
          expect(
            baseline - bottom,
            greaterThan(geometry.lineHeight(sourceLine) / 3),
          );
          expect(
            column.lineBaseline(line) - toColumn(column, piece, x, bottom).dy,
            closeTo((baseline - bottom) * scale, devicePixel),
            reason: 'mark $mark',
          );
        }
      }
    });
  });

  group('baselines', () {
    test('on the skewed page, the words of each reflowed line share one '
        'level baseline within one device pixel', () {
      final page = skewed();
      final geometry = page.geometry;
      for (final fontSize in [20.0, 40.0]) {
        final column = lay(page, width: 360, fontSize: fontSize);
        var words = 0;
        for (var piece = 0; piece < column.pieceCount; piece++) {
          final word = column.word(piece);
          if (word < 0 || page.analysis.sourceWords[word] < 0) continue;
          final baseline = column.lineBaseline(lineOf(column, piece));
          final left = geometry.boxes[word * 4];
          final right = geometry.boxes[word * 4 + 2];
          for (final (x, y) in [
            (left, geometry.ownBaselines[word * 2]),
            (right, geometry.ownBaselines[word * 2 + 1]),
          ]) {
            final dy = toColumn(column, piece, x, y).dy;
            expect(
              dy,
              closeTo(baseline, devicePixel),
              reason: 'word $word at size $fontSize',
            );
          }
          words++;
        }
        expect(words, greaterThan(30));
      }
    });
  });

  group('paragraphs', () {
    test('a paragraph starts a new line and keeps its first-line indent, '
        'scaled', () async {
      final page = await gibbon();
      final geometry = page.geometry;
      final start = find(page, ['The', 'name', 'of', 'the', 'Alemanni']);
      final next = find(page, ['their', 'imaginary']);
      for (final (width, fontSize) in [(300.0, 20.0), (1000.0, 14.0)]) {
        final column = lay(page, width: width, fontSize: fontSize);
        final piece = pieceOf(column, start);
        expect(column.lineStarts, contains(piece));
        expect(
          column.target(piece).left,
          closeTo(
            (geometry.boxes[start * 4] - geometry.boxes[next * 4]) *
                column.scale,
            1,
          ),
        );
        // The lines beside the side note are set narrower, not indented,
        // and they continue their justified paragraph: a word of theirs that
        // wraps starts the next line after a full line.
        for (final words in [
          ['executioner.'],
          ['king', 'of', 'the', 'Franks,'],
        ]) {
          final piece = pieceOf(column, find(page, words));
          final line = lineOf(column, piece);
          if (column.lineStarts[line] != piece) continue;
          expect(column.target(piece).left, closeTo(0, 0.01));
          expect(
            column.target(column.lineStarts[line] - 1).right,
            closeTo(width, 0.5),
            reason: words.join(' '),
          );
        }
      }
    });

    test('the lines of a ragged paragraph flow on as one paragraph', () async {
      // Four source lines that fill about 3.4 reflowed lines as wide as one
      // source line. In a column as wide as 2.7 source lines, they take two.
      final page = await equation();
      final column = lay(page, width: 1000, fontSize: 14);
      final first = lineOf(column, pieceOf(column, find(page, ['A', 'stone'])));
      final last = lineOf(column, pieceOf(column, find(page, ['long.'])));
      expect(last - first + 1, 2);
    });
  });

  group('rejoined hyphens', () {
    test('a hyphen pair on one line draws no hyphen and no gap, and a pair '
        'across two lines draws the hyphen', () async {
      for (final page in [await gibbon(), await equation()]) {
        final geometry = page.geometry;
        final pairs = [
          for (var line = 0; line + 1 < geometry.lineCount; line++)
            if (geometry.hyphens[geometry.lineStarts[line + 1] - 1] > 0)
              geometry.lineStarts[line + 1] - 1,
        ];
        expect(pairs, isNotEmpty);
        var joined = 0, apart = 0;
        for (var width = 150.0; width <= 600; width += 15) {
          final column = lay(page, width: width);
          for (final first in pairs) {
            final a = pieceOf(column, first), b = pieceOf(column, first + 1);
            final right = geometry.boxes[first * 4 + 2];
            if (lineOf(column, a) == lineOf(column, b)) {
              joined++;
              expect(
                column.source(a).right,
                closeTo(right - geometry.hyphens[first], 1e-6),
              );
              expect(
                column.target(b).left,
                closeTo(column.target(a).right, 0.01),
              );
            } else {
              apart++;
              expect(column.source(a).right, closeTo(right, 1e-6));
            }
          }
        }
        expect(joined, greaterThan(0));
        expect(apart, greaterThan(0));
      }
    });
  });

  group('regions', () {
    test('the display equation and the table each show whole as one '
        'centered piece that fits the column', () async {
      final page = await equation();
      for (final width in [150.0, 360.0]) {
        final column = lay(page, width: width);
        final regions = [
          for (var piece = 0; piece < column.pieceCount; piece++)
            if (column.region(piece) >= 0) piece,
        ];
        expect(regions, hasLength(page.analysis.regionCount));
        for (final piece in regions) {
          final target = column.target(piece);
          expect(target.left, closeTo(width - target.right, 0.5));
          expect(target.width, lessThanOrEqualTo(width + 0.01));
          expect(piecesOf(column, lineOf(column, piece)), [piece]);
        }
        final widest = regions
            .map((piece) => column.target(piece).width)
            .reduce(math.max);
        if (width == 150) expect(widest, closeTo(150, 0.01));
      }
    });

    test(
      'a region taller than the screen is scaled to fit one screen',
      () async {
        final page = await raven();
        final column = lay(page, width: 360, screenHeight: 300);
        final engraving =
            [
              for (var piece = 0; piece < column.pieceCount; piece++)
                if (column.region(piece) >= 0) piece,
            ].reduce(
              (a, b) =>
                  column.target(a).height > column.target(b).height ? a : b,
            );
        final target = column.target(engraving);
        expect(target.height, closeTo(300, 0.01));
        final top = column.screenTop(
          screenOf(column, lineOf(column, engraving)),
        );
        expect(target.top, greaterThanOrEqualTo(top - 0.01));
        expect(target.bottom, lessThanOrEqualTo(top + 300 + 0.01));
      },
    );

    test('the dark bottom edge of the Raven scan does not show, so the word '
        'view ends with the folio, and the engraving still shows', () async {
      final page = await raven();
      final column = lay(page);
      // The folio ends 2263 pixels down a page 2594 pixels tall, and the dark
      // edge of the scan starts at 2580.
      final bottoms = [
        for (var piece = 0; piece < column.pieceCount; piece++)
          column.source(piece).bottom * 1600,
      ];
      expect(bottoms.reduce(math.max), closeTo(2263, 2));
      final last = column.lineStarts[column.lineCount - 1];
      expect(column.source(last).bottom * 1600, closeTo(2263, 2));
      expect([
        for (var piece = 0; piece < column.pieceCount; piece++)
          if (column.region(piece) >= 0) column.source(piece).height,
      ], contains(greaterThan(0.5)));
    });

    test('a figure\'s caption shows centered on its figure\'s screen, above '
        'or below it', () async {
      for (final above in [false, true]) {
        final figure = [300, above ? 620 : 520, 1300, above ? 1100 : 1000];
        final caption = [wordsAt(620, above ? 570 : 1020, 3)];
        final drawn = BlockPage([
          (picture: null, lines: proseLines(4)),
          if (above) (picture: null, lines: caption),
          (picture: figure, lines: const []),
          if (!above) (picture: null, lines: caption),
          (picture: null, lines: proseLines(8, top: 1140)),
        ]);
        final pdf = DrawnPdf([drawn], hop: hop);
        final reflow = (await pdf.reflowPage(1))!;
        final page = (
          geometry: reflow.geometry,
          analysis: reflow.analysis,
          bodyLineHeight: reflow.bodyLineHeight,
          texts: const <String>[],
        );
        final first = reflow.geometry.lineStarts[4];
        for (var screenHeight = 220.0; screenHeight < 900; screenHeight += 9) {
          final column = lay(page, width: 360, screenHeight: screenHeight);
          final region = [
            for (var piece = 0; piece < column.pieceCount; piece++)
              if (column.region(piece) >= 0) piece,
          ].single;
          final words = [
            for (var word = first; word < first + 3; word++)
              pieceOf(column, word),
          ];
          final screen = screenOf(column, lineOf(column, region));
          for (final piece in words) {
            expect(
              screenOf(column, lineOf(column, piece)),
              screen,
              reason: 'screen height $screenHeight, caption above: $above',
            );
          }
          expect(
            column.target(words.first).left,
            closeTo(360 - column.target(words.last).right, 0.5),
          );
          expect(
            lineOf(column, words.first),
            above ? lineOf(column, region) - 1 : lineOf(column, region) + 1,
          );
        }
      }
    });
  });

  group('the invariant check', () {
    test('finds lines that overlap', () {
      final column = ReflowColumn(
        width: 100,
        screenHeight: 100,
        scale: 100,
        pieces: Float32List.fromList([
          ...[0, 0, 0.1, 0.1, 0, 0, 10, 10, 0],
          ...[0.2, 0, 0.3, 0.1, 0, 5, 10, 15, 0],
        ]),
        pieceItems: Int32List.fromList([0, 1]),
        lineStarts: Int32List.fromList([0, 1, 2]),
        lineExtents: Float32List.fromList([0, 10, 10, 5, 15, 15]),
        screenStarts: Int32List.fromList([0, 2]),
      );
      expect(column.checkInvariants, throwsStateError);
    });
  });

  group('text size', () {
    test(
      'a size step changes the height of a word by the size ratio',
      () async {
        final page = await gibbon();
        final word = find(page, ['hostile']);
        final at20 = lay(page, fontSize: 20), at22 = lay(page, fontSize: 22);
        expect(
          at22.target(pieceOf(at22, word)).height /
              at20.target(pieceOf(at20, word)).height,
          closeTo(1.1, 1e-4),
        );
      },
    );
  });

  group('screens', () {
    test('no screen cuts a line or starts with a paragraph gap, and each '
        'screen holds every line that fits', () async {
      for (final page in [await gibbon(), await equation(), skewed()]) {
        for (final (fontSize, screenHeight) in [
          (14.0, 300.0),
          (20.0, 640.0),
          (40.0, 500.0),
        ]) {
          final column = lay(
            page,
            fontSize: fontSize,
            screenHeight: screenHeight,
          );
          expect(column.screenCount, greaterThan(0));
          for (var screen = 0; screen < column.screenCount; screen++) {
            final top = column.screenTop(screen);
            final first = column.screenStarts[screen];
            final end = column.screenStarts[screen + 1];
            final firstTop = piecesOf(
              column,
              first,
            ).map((piece) => drawn(column, piece).top).reduce(math.min);
            expect(firstTop, closeTo(top, 0.01), reason: 'screen $screen');
            for (var line = first; line < end; line++) {
              for (final piece in piecesOf(column, line)) {
                final box = drawn(column, piece);
                expect(box.top, greaterThanOrEqualTo(top - 0.01));
                expect(
                  box.bottom,
                  lessThanOrEqualTo(top + screenHeight + 0.01),
                );
              }
            }
            if (end < column.lineCount) {
              expect(
                column.lineBottom(end) - top,
                greaterThan(screenHeight),
                reason: 'line $end fits on screen $screen',
              );
            }
          }
        }
      }
    });

    test('the column of a scanned page is the same before and after its '
        'text attaches, and it is laid out through the hop', () async {
      final supply = FixtureRecognition('footnote-page');
      final pdf = await open(footnotePage, textSupply: supply);
      final settings = ColumnSettings(
        width: 360,
        fontSize: 20,
        screenHeight: 640,
      );
      final before = await (await pdf.reflowPage(1))!.column(settings);
      expect(hopped, contains(layoutColumn));
      supply.textArrives.complete();
      final page = (await pdf.reflowPage(1))!;
      await page.attachedText();
      final after = await page.column(settings);
      expect(after.pieces, before.pieces);
      expect(after.pieceItems, before.pieceItems);
      expect(after.lineStarts, before.lineStarts);
      expect(after.lineExtents, before.lineExtents);
      expect(after.screenStarts, before.screenStarts);
      expect(before.lineCount, greaterThan(40));
    });
  });
}
