import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/ocr.dart';
import 'package:bookfin/reader/page_analysis.dart';
import 'package:bookfin/reader/page_geometry.dart';
import 'package:bookfin/reader/pdf.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart' as native;

import 'ocr_hop_test.dart' show runInWorker;
import 'page_geometry_test.dart' show hocrFixture, layoutFixture, layoutOf;
import 'text_layer_geometry_test.dart' show printedLines;

const equationPage = 'test/reader/fixtures/reflow/equation-page.pdf';
const footnotePage = 'test/reader/fixtures/reflow/footnote-page.pdf';
const ravenPage =
    'tool/research/readers/evidence/text-quality/raven-raster-only.pdf';

/// A text supply for one scanned fixture page: its words come from the
/// layout record [name] and its text from the hOCR [name]. The text waits
/// for [textArrives].
class FixtureRecognition implements PdfTextSupply {
  FixtureRecognition(this.name);
  final String name;
  final textArrives = Completer<void>();
  @override
  final recognizing = ValueNotifier(false);
  @override
  void bind(PdfTextLease lease) {}
  @override
  void cancel() {}
  @override
  Future<PdfText> text(PdfBook book, int page, PdfText extracted) async {
    await textArrives.future;
    return decodeRecognizedPage(hocrFixture(name)).text;
  }

  @override
  Future<PageGeometry?> geometry(
    PdfBook book,
    int page,
    PdfText extracted, {
    bool background = false,
  }) async => pageGeometryFromLayout(layoutFixture(name));
  @override
  Future<({PdfText text, TextAttachment? attachment})> attachedText(
    PdfBook book,
    int page,
    PdfText extracted,
    PageGeometry geometry,
  ) async {
    await textArrives.future;
    final recognized = decodeRecognizedPage(hocrFixture(name));
    return (
      text: recognized.text,
      attachment: attachText((geometry: geometry, words: recognized.words)),
    );
  }

  @override
  Future<void> close() async {}
}

/// A made-up page 1600 pixels wide: its geometry and its raster, white
/// paper with black ink.
class DrawnPage {
  DrawnPage(this.lines, {this.height = 2400})
    : raster = PdfRaster(1600, height, Uint8List(1600 * height * 4))
        ..bgra.fillRange(0, 1600 * height * 4, 255) {
    for (final line in lines) {
      for (final box in line) {
        ink(box);
      }
    }
  }

  /// The word boxes of each line, in pixels: left, top, right and bottom.
  final List<List<List<int>>> lines;
  final int height;
  final PdfRaster raster;

  /// Draws black ink over [box] (left, top, right and bottom in pixels).
  void ink(List<int> box) {
    for (var y = box[1]; y < box[3]; y++) {
      for (var x = box[0]; x < box[2]; x++) {
        raster.bgra.fillRange((y * 1600 + x) * 4, (y * 1600 + x) * 4 + 3, 0);
      }
    }
  }

  /// Draws gray print of [luminance] over [box] (left, top, right and
  /// bottom in pixels).
  void shade(List<int> box, int luminance) {
    for (var y = box[1]; y < box[3]; y++) {
      for (var x = box[0]; x < box[2]; x++) {
        raster.bgra.fillRange(
          (y * 1600 + x) * 4,
          (y * 1600 + x) * 4 + 3,
          luminance,
        );
      }
    }
  }

  /// Clears [box] to white paper.
  void clear(List<int> box) {
    for (var y = box[1]; y < box[3]; y++) {
      for (var x = box[0]; x < box[2]; x++) {
        raster.bgra.fillRange((y * 1600 + x) * 4, (y * 1600 + x) * 4 + 3, 255);
      }
    }
  }

  PageGeometry get geometry =>
      pageGeometryFromLayout(layoutOf(1600, height, lines));
}

/// Prose lines of words 40 pixels tall: [count] lines from [top], each
/// [pitch] pixels below the one before it, of words 100 pixels wide with
/// gaps of 16 pixels between them.
List<List<List<int>>> proseLines(
  int count, {
  int top = 200,
  int pitch = 60,
  int words = 10,
  int lineHeight = 40,
}) => [
  for (var line = 0; line < count; line++)
    [
      for (var word = 0; word < words; word++)
        [
          100 + word * 116,
          top + line * pitch,
          200 + word * 116,
          top + line * pitch + lineHeight,
        ],
    ],
];

/// A scanned PDF of made-up pages. Its pages have no text layer, so their
/// words come from [pages] and their hyphens from pixels.
class DrawnPdf extends PdfBook {
  DrawnPdf(this.pages, {required super.hop});
  final List<DrawnPage> pages;
  final renders = <int>[];

  /// How many more times the pages have no geometry, as when a reader
  /// stopped waiting for the layout pass.
  var withoutGeometry = 0;

  /// How many more times the reading text fails, as when the person
  /// canceled recognition.
  var failedTexts = 0;
  @override
  String get originalDigest => 'drawn';
  @override
  String get identity => 'drawn';
  @override
  String get engine => 'drawn';
  @override
  String get policy => 'drawn';
  @override
  String get format => 'pdf';
  @override
  int get pageCount => pages.length;
  @override
  bool accepts(ReaderAddress address) => address is PdfAddress;
  @override
  ReaderAddress decodeAddress(Map<String, dynamic> value) =>
      throw UnimplementedError();
  @override
  Future<void> dispose() async {}
  @override
  Future<PdfText> textLayer(int sourcePage) async => const PdfText(
    source: '',
    text: '',
    sourceOffsets: [],
    status: PdfTextStatus.absent,
  );
  @override
  Future<PageGeometry?> geometry(
    int sourcePage, {
    bool background = false,
  }) async {
    if (withoutGeometry > 0) {
      withoutGeometry--;
      return null;
    }
    return pages[sourcePage - 1].geometry;
  }

  @override
  Future<({PdfText text, TextAttachment? attachment})> attachedText(
    int sourcePage,
    PageGeometry geometry,
  ) async {
    if (failedTexts > 0) {
      failedTexts--;
      return (
        text: const PdfText(
          source: '',
          text: '',
          sourceOffsets: [],
          status: PdfTextStatus.failed,
          reason: 'Recognition stopped.',
        ),
        attachment: null,
      );
    }
    final words = geometry.wordCount;
    final source = List.filled(words, 'word').join(' ');
    return (
      text: PdfText(
        source: source,
        text: source,
        sourceOffsets: List.generate(source.length, (index) => index),
        status: PdfTextStatus.candidate,
        digest: pdfTextDigest(source),
      ),
      attachment: Int32List.fromList([
        for (var word = 0; word < words; word++) ...[word * 5, word * 5 + 4],
      ]),
    );
  }

  @override
  Future<PdfRaster> render(int sourcePage, double width) async {
    renders.add(sourcePage);
    return pages[sourcePage - 1].raster;
  }

  @override
  Future<ui.Image> renderPart(
    int sourcePage,
    int pixelsPerPageUnit,
    ui.Rect area,
  ) => throw UnimplementedError('A drawn page draws no word view.');
}

/// The words of [page] that lie in [line], as indexes of its geometry.
Iterable<int> lineWords(PageGeometry page, int line) sync* {
  for (
    var word = page.lineStarts[line];
    word < page.lineStarts[line + 1];
    word++
  ) {
    yield word;
  }
}

/// The text of each word of [page], as [attachment] names it in [source].
List<String> wordTexts(
  PageGeometry page,
  TextAttachment attachment,
  String source,
) => [
  for (var word = 0; word < page.wordCount; word++)
    source.substring(attachment[word * 2], attachment[word * 2 + 1]),
];

/// The bytes of every list that [page] keeps.
int keptBytes(ReflowPage page) {
  final geometry = page.geometry, analysis = page.analysis;
  return [
    geometry.boxes,
    geometry.ownBaselines,
    geometry.hyphens,
    geometry.lineStarts,
    geometry.lineMetrics,
    geometry.blockStarts,
    geometry.blockBoxes,
    geometry.blockKinds,
    geometry.paragraphStarts,
    geometry.paragraphJustifications,
    geometry.paragraphIndents,
    analysis.regionBoxes,
    analysis.regionKinds,
    analysis.wordRegions,
    analysis.proseLines,
    analysis.sourceWords,
  ].fold(0, (sum, list) => sum + list.lengthInBytes);
}

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
      path,
      'd' * 64,
      textSupply: textSupply,
      hop: hop,
    );
    addTearDown(book.dispose);
    return book;
  }

  /// The reflowed equation page, with its reading text attached.
  Future<(ReflowPage, List<String>)> equation() async {
    final pdf = await open(equationPage);
    final page = (await pdf.reflowPage(1))!;
    final attached = await page.attachedText();
    pdf.checkInvariants();
    return (
      page,
      wordTexts(page.geometry, attached.attachment!, attached.text.source),
    );
  }

  /// The reflowed footnote page, with its recognized text attached.
  Future<(ReflowPage, List<String>, String)> footnotes() async {
    final supply = FixtureRecognition('footnote-page')..textArrives.complete();
    final pdf = await open(footnotePage, textSupply: supply);
    final page = (await pdf.reflowPage(1))!;
    final attached = await page.attachedText();
    pdf.checkInvariants();
    return (
      page,
      wordTexts(page.geometry, attached.attachment!, attached.text.source),
      attached.text.source,
    );
  }

  /// The regions that hold [words], and whether they hold no other word.
  (Set<int>, bool) regionsOf(ReflowPage page, Iterable<int> words) {
    final regions = {for (final word in words) page.analysis.wordRegions[word]};
    final others = [
      for (var word = 0; word < page.geometry.wordCount; word++)
        if (!words.contains(word) &&
            regions.contains(page.analysis.wordRegions[word]))
          word,
    ];
    return (regions, others.isEmpty);
  }

  group('regions that reflow keeps whole', () {
    test('the display equation becomes one ink region that keeps its text '
        'in the reading text', () async {
      final (page, texts) = await equation();
      final line = printedLines.indexOf('𝑣 2 = 𝑢 2 + 2𝑔ℎ');
      final words = lineWords(page.geometry, line).toList();
      expect(words.map((word) => texts[word]).join(' '), printedLines[line]);

      final (regions, alone) = regionsOf(page, words);
      expect(regions, hasLength(1));
      expect(regions.single, isNot(-1));
      expect(alone, isTrue);
      expect(page.analysis.regionKind(regions.single), RegionKind.ink);
      expect(page.analysis.isProse(line), isFalse);
    });

    test('the table becomes one ink region that keeps the text of its '
        'cells', () async {
      final (page, texts) = await equation();
      final first = printedLines.indexOf('Body Height Time');
      final words = [
        for (var line = first; line < first + 3; line++)
          ...lineWords(page.geometry, line),
      ];
      expect(
        words.map((word) => texts[word]).join(' '),
        'Body Height Time Stone 5 m 1.0 s Apple 20 m 2.0 s',
      );

      final (regions, alone) = regionsOf(page, words);
      expect(regions, hasLength(1));
      expect(regions.single, isNot(-1));
      expect(alone, isTrue);
      expect(page.analysis.regionKind(regions.single), RegionKind.ink);
    });

    test('a justified line with wide word gaps stays prose', () async {
      final (page, _) = await equation();
      final first = printedLines.indexWhere(
        (line) => line.startsWith('Measurements'),
      );
      for (var line = first; line < first + 3; line++) {
        expect(page.analysis.isProse(line), isTrue, reason: 'line $line');
        for (final word in lineWords(page.geometry, line)) {
          expect(page.analysis.wordRegions[word], -1);
        }
      }
    });

    test('a heading in larger type stays prose', () async {
      final (page, _) = await equation();
      expect(page.analysis.isProse(0), isTrue);
      expect(
        lineWords(
          page.geometry,
          0,
        ).map((word) => page.analysis.wordRegions[word]),
        everyElement(-1),
      );
    });

    test('a table without rules becomes one region from the aligned gaps of '
        'its rows', () async {
      // Three rows of three columns: the gaps between the columns are 120
      // pixels wide and line up, and the gaps inside a cell are 16.
      List<List<int>> row(int top) => [
        [100, top, 260, top + 40],
        [380, top, 440, top + 40],
        [456, top, 500, top + 40],
        [620, top, 700, top + 40],
        [716, top, 760, top + 40],
      ];
      final above = proseLines(4);
      final table = [row(460), row(520), row(580)];
      final below = proseLines(4, top: 700);
      final pdf = DrawnPdf([
        DrawnPage([...above, ...table, ...below]),
      ], hop: hop);
      final page = (await pdf.reflowPage(1))!;

      final words = [
        for (var line = 4; line < 7; line++) ...lineWords(page.geometry, line),
      ];
      final (regions, alone) = regionsOf(page, words);
      expect(regions, hasLength(1));
      expect(regions.single, isNot(-1));
      expect(alone, isTrue);
      for (final line in [0, 1, 2, 3, 7, 8, 9, 10]) {
        expect(page.analysis.isProse(line), isTrue, reason: 'line $line');
      }
    });

    test(
      'a picture block of the layout pass becomes a picture region',
      () async {
        final supply = FixtureRecognition('scanned-page')
          ..textArrives.complete();
        final pdf = await open(ravenPage, textSupply: supply);
        final page = (await pdf.reflowPage(1))!;
        final geometry = page.geometry, analysis = page.analysis;
        final picture = [
          for (var block = 0; block < geometry.blockCount; block++)
            if (geometry.blockKind(block) == PageBlockKind.picture) block,
        ].single;
        final block = geometry.blockBoxes.sublist(picture * 4, picture * 4 + 4);
        final holding = [
          for (var region = 0; region < analysis.regionCount; region++)
            if (analysis.regionBoxes[region * 4] <= block[0] &&
                analysis.regionBoxes[region * 4 + 1] <= block[1] &&
                analysis.regionBoxes[region * 4 + 2] >= block[2] &&
                analysis.regionBoxes[region * 4 + 3] >= block[3])
              region,
        ];
        expect(holding, hasLength(1));
        expect(analysis.regionKind(holding.single), RegionKind.picture);
        // The verse under the engraving stays prose.
        final verse = geometry.lineCount - 1;
        expect(analysis.isProse(verse), isTrue);
        expect(
          lineWords(geometry, verse).map((word) => analysis.wordRegions[word]),
          everyElement(-1),
        );
        await page.attachedText();
        pdf.checkInvariants();
      },
    );
  });

  group('ink that no word covers', () {
    test('the footnote mark that recognition leaves between two words shows '
        'as a raised extra word of its line, with no text', () async {
      final (page, texts, _) = await footnotes();
      final geometry = page.geometry;
      final city = [
        for (var word = 0; word + 2 < geometry.wordCount; word++)
          if (texts[word] == 'city.' && texts[word + 2] == 'But') word,
      ].single;
      final mark = city + 1;
      expect(page.analysis.sourceWords[mark], -1);
      expect(texts[mark], isEmpty);
      final line = [
        for (var line = 0; line < geometry.lineCount; line++)
          if (geometry.lineStarts[line] <= mark &&
              mark < geometry.lineStarts[line + 1])
            line,
      ].single;
      expect(geometry.lineStarts[line], lessThanOrEqualTo(city));
      expect(geometry.lineStarts[line + 1], greaterThan(city + 2));
      final left = geometry.boxes[mark * 4],
          right = geometry.boxes[mark * 4 + 2];
      expect(left, greaterThanOrEqualTo(geometry.boxes[city * 4 + 2] - 0.002));
      expect(right, lessThanOrEqualTo(geometry.boxes[(city + 2) * 4] + 0.002));
      final baseline = geometry.lineBaselineAt(line, (left + right) / 2);
      expect(
        geometry.boxes[mark * 4 + 3],
        lessThan(baseline - geometry.lineHeight(line) / 3),
      );
      expect(page.analysis.wordRegions[mark], -1);
    });

    test(
      'specks are dropped, and a mark as large as a footnote mark stays',
      () async {
        final drawn = DrawnPage(proseLines(10));
        // Specks of 6 pixels, less than a sixth of the 40 pixel line, in the
        // margin, between lines and in a word gap.
        for (final speck in [
          [30, 300, 36, 306],
          [700, 247, 706, 253],
          [1300, 1500, 1306, 1506],
          [204, 222, 210, 228],
        ]) {
          drawn.ink(speck);
        }
        // A raised mark 16 pixels wide and 18 tall in a word gap.
        drawn.ink([432, 380, 438, 398]);
        drawn.ink([442, 380, 448, 398]);
        final pdf = DrawnPdf([drawn], hop: hop);
        final page = (await pdf.reflowPage(1))!;
        final extra = [
          for (var word = 0; word < page.geometry.wordCount; word++)
            if (page.analysis.sourceWords[word] < 0) word,
        ];
        expect(extra, hasLength(1));
        expect(page.geometry.boxes[extra.single * 4] * 1600, closeTo(432, 4));
        expect(
          page.geometry.boxes[extra.single * 4 + 2] * 1600,
          closeTo(448, 4),
        );
        expect(page.analysis.regionCount, 0);
      },
    );
  });

  group('a printed word that the layout pass splits', () {
    test('two words of a line join when faint print bridges every column of '
        'the gap between them, and stay apart when the gap keeps a white '
        'column', () async {
      final drawn = DrawnPage(proseLines(10))
        // Line 0: gray print at 0.6 of the paper's luminance across the
        // whole gap of 16 pixels between its first two words, as a faint
        // letter.
        ..shade([200, 210, 216, 230], 150)
        // Line 1: gray print that touches the first word but leaves the last
        // 4 columns of the gap white, as the soft edge of a letter.
        ..shade([200, 270, 212, 290], 150);
      final page = (await DrawnPdf([drawn], hop: hop).reflowPage(1))!;
      final geometry = page.geometry;
      final joined = geometry.lineStarts[0], apart = geometry.lineStarts[1];
      expect(geometry.boxes[joined * 4 + 2] * 1600, closeTo(216, 0.01));
      expect(geometry.boxes[apart * 4 + 2] * 1600, closeTo(200, 0.01));
      // Gray print is no ink, so it makes no extra word.
      expect(page.analysis.sourceWords, isNot(contains(-1)));
      page.analysis.checkInvariants(geometry);
    });
  });

  group('line-end hyphens of a scanned page', () {
    test('are found from pixels', () async {
      final (page, texts, _) = await footnotes();
      final geometry = page.geometry;
      expect(
        [
          for (var word = 0; word < geometry.wordCount; word++)
            if (geometry.hyphens[word] > 0) texts[word],
        ],
        [
          'arse-', 'num-', 'es-', 'Tou-', 'pro-', 'en-', //
          'ascer-', 'justi-', 'tran-', 'Thu-',
        ],
      );
    });

    test('have the width from the white gap before the hyphen to the word\'s '
        'right edge', () async {
      final lines = proseLines(10);
      final drawn = DrawnPage(lines);
      // The last word of the first line ends in a white gap of 6 pixels and
      // a hyphen 14 pixels wide and 4 tall, a quarter of the line height
      // above the baseline (the line is 200 to 240, its baseline at 240).
      final last = lines.first.last;
      drawn.clear([last[2] - 20, last[1], last[2], last[3]]);
      drawn.ink([last[2] - 14, 228, last[2], 232]);
      final pdf = DrawnPdf([drawn], hop: hop);
      final page = (await pdf.reflowPage(1))!;
      final word = page.geometry.lineStarts[1] - 1;
      expect(page.geometry.hyphens[word] * 1600, closeTo(14, 1));
      expect([
        for (var other = 0; other < page.geometry.wordCount; other++)
          if (other != word && page.geometry.hyphens[other] > 0) other,
      ], isEmpty);
    });
  });

  group('the reflow page of a source page', () {
    test(
      'gives its geometry and analysis before its text arrives: the '
      'analysis reads no text, runs through the hop, and keeps no raster',
      () async {
        final supply = FixtureRecognition('footnote-page');
        final pdf = await open(footnotePage, textSupply: supply);
        final page = (await pdf.reflowPage(1))!;
        expect(hopped, contains(analyzePage));
        page.analysis.checkInvariants(page.geometry);
        final raster = await pdf.render(1, 1600);
        expect(keptBytes(page), lessThan(raster.bgra.lengthInBytes / 100));

        var attached = false;
        final text = page.attachedText().then((value) {
          attached = true;
          return value;
        });
        await pumpEventQueue();
        expect(attached, isFalse);
        supply.textArrives.complete();
        final arrived = await text;
        page.geometry.checkInvariants(
          attachment: arrived.attachment,
          source: arrived.text.source,
        );
        pdf.checkInvariants();
      },
    );

    test('keeps the last 16 pages, and draws a kept page only once', () async {
      final pdf = DrawnPdf([
        for (var page = 0; page < 18; page++) DrawnPage(proseLines(3)),
      ], hop: hop);
      for (var page = 1; page <= 17; page++) {
        await pdf.reflowPage(page);
      }
      await (await pdf.reflowPage(17))!.attachedText();
      pdf.checkInvariants();
      pdf.renders.clear();
      await pdf.reflowPage(17);
      await pdf.reflowPage(2);
      expect(pdf.renders, isEmpty);
      await pdf.reflowPage(1);
      expect(pdf.renders, [1]);
      pdf.checkInvariants();
    });

    test('a page with few prose lines takes the body line height of the '
        'book, once a page with 8 prose lines gives one', () async {
      final pdf = DrawnPdf([
        DrawnPage(proseLines(10)),
        DrawnPage(proseLines(3, pitch: 90, lineHeight: 60)),
      ], hop: hop);
      final few = (await pdf.reflowPage(2))!;
      expect(few.bodyLineHeight * 1600, closeTo(60, 0.5));
      final many = (await pdf.reflowPage(1))!;
      expect(many.bodyLineHeight * 1600, closeTo(40, 0.5));
      expect(many.analysis.bodyLineHeight * 1600, closeTo(40, 0.5));
      final again = (await pdf.reflowPage(2))!;
      expect(again.bodyLineHeight * 1600, closeTo(40, 0.5));
      expect(again.analysis.bodyLineHeight * 1600, closeTo(60, 0.5));
    });

    test('a page that had no geometry is asked again', () async {
      final pdf = DrawnPdf([DrawnPage(proseLines(3))], hop: hop)
        ..withoutGeometry = 1;
      expect(await pdf.reflowPage(1), isNull);
      expect(await pdf.reflowPage(1), isNotNull);
      pdf.checkInvariants();
    });

    test('a reading text that failed, such as a canceled recognition, is '
        'asked again, and a text that arrived is shared', () async {
      final pdf = DrawnPdf([DrawnPage(proseLines(3))], hop: hop)
        ..failedTexts = 1;
      final page = (await pdf.reflowPage(1))!;
      expect((await page.attachedText()).text.status, PdfTextStatus.failed);
      final arrived = await (await pdf.reflowPage(1))!.attachedText();
      expect(arrived.text.status, PdfTextStatus.candidate);
      expect(identical(await page.attachedText(), arrived), isTrue);
      pdf.checkInvariants();
    });
  });
}
