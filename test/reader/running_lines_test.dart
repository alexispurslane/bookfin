import 'dart:io';
import 'dart:typed_data';

import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/page_analysis.dart';
import 'package:bookfin/reader/page_geometry.dart';
import 'package:bookfin/reader/pdf.dart';
import 'package:bookfin/reader/running_lines.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart' as native;

import 'ocr_hop_test.dart' show runInWorker;
import 'page_analysis_test.dart'
    show DrawnPage, DrawnPdf, FixtureRecognition, proseLines, ravenPage;

const marginsBook = 'test/reader/fixtures/reflow/margins-book.pdf';

/// The book's title, which the even pages of margins-book.pdf carry as their
/// running header.
const bookTitle = 'A Short Book of Motion';

/// The chapter that each page of margins-book.pdf belongs to. Page 1 is the
/// title page, and pages 2 and 8 start a chapter.
String chapterOf(int page) => page < 8 ? 'Falling Bodies' : 'The Pendulum';

/// A scanned copy of [book]: the same pages and words, but without text, as a
/// scanned book is before recognition. Reading its text fails the test.
class ScannedCopy extends PdfBook {
  ScannedCopy(this.book) : super(hop: runInWorker);
  final PdfBook book;
  @override
  String get originalDigest => 'scanned';
  @override
  String get identity => 'scanned';
  @override
  String get engine => 'scanned';
  @override
  String get policy => 'scanned';
  @override
  String get format => 'pdf';
  @override
  int get pageCount => book.pageCount;
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
  Future<PdfText> text(int sourcePage) =>
      throw StateError('A scanned page without text was read.');
  @override
  Future<({PdfText text, TextAttachment? attachment})> attachedText(
    int sourcePage,
    PageGeometry geometry,
  ) => throw StateError('A scanned page without text was read.');
  @override
  Future<PageGeometry?> geometry(int sourcePage) => book.geometry(sourcePage);
  @override
  Future<PdfRaster> render(int sourcePage, double width) =>
      book.render(sourcePage, width);
}

/// The text of each line of [page], or null when it has no text.
List<String>? lineTexts(AnalyzedSourcePage page) {
  final text = page.text;
  if (text == null) return null;
  final geometry = page.geometry;
  return [
    for (var line = 0; line < geometry.lineCount; line++)
      text.source
          .substring(
            text.attachment[geometry.lineStarts[line] * 2],
            text.attachment[(geometry.lineStarts[line + 1] - 1) * 2 + 1],
          )
          .replaceAll(RegExp(r'\s+'), ' '),
  ];
}

/// The lines of [analysis] that are running lines.
List<int> runningLinesOf(PageAnalysis analysis) => [
  for (var line = 0; line < analysis.runningLines.length; line++)
    if (analysis.isRunning(line)) line,
];

/// Whether box [index] of [boxes] (left, top, right and bottom) lies inside
/// [outer], within a hundredth of a pixel at 1600 pixels wide.
bool inside(Float32List outer, List<double> boxes, int index) =>
    outer[0] <= boxes[index * 4] + 1e-5 &&
    outer[1] <= boxes[index * 4 + 1] + 1e-5 &&
    outer[2] >= boxes[index * 4 + 2] - 1e-5 &&
    outer[3] >= boxes[index * 4 + 3] - 1e-5;

/// Whether box [index] of [boxes] overlaps [outer].
bool overlaps(Float32List outer, List<double> boxes, int index) =>
    outer[0] < boxes[index * 4 + 2] &&
    boxes[index * 4] < outer[2] &&
    outer[1] < boxes[index * 4 + 3] &&
    boxes[index * 4 + 1] < outer[3];

/// The words of [line] of [geometry].
Iterable<int> wordsOf(PageGeometry geometry, int line) => Iterable.generate(
  geometry.lineStarts[line + 1] - geometry.lineStarts[line],
  (index) => geometry.lineStarts[line] + index,
);

/// [page] as the template finder reads it, with the text [lines]: for each
/// line of the page's word geometry, the text of each of its words.
AnalyzedSourcePage withText(
  int sourcePage,
  ReflowPage page,
  List<List<String>> lines,
) {
  final source = StringBuffer();
  final ranges = <int>[];
  for (final words in lines) {
    for (final word in words) {
      if (source.isNotEmpty) source.write(' ');
      ranges.addAll([source.length, source.length + word.length]);
      source.write(word);
    }
  }
  return (
    sourcePage: sourcePage,
    geometry: page.geometry,
    analysis: page.analysis,
    text: (
      source: source.toString(),
      attachment: reflowAttachment(Int32List.fromList(ranges), page.analysis),
    ),
  );
}

/// A line of [texts] at [top], as word boxes 40 pixels tall that start at
/// [left], each 20 pixels wide for each letter, 16 pixels apart.
List<List<int>> lineOf(List<String> texts, {required int top, int left = 600}) {
  final boxes = <List<int>>[];
  var x = left;
  for (final text in texts) {
    boxes.add([x, top, x + 20 * text.length, top + 40]);
    x += 20 * text.length + 16;
  }
  return boxes;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  native.Pdfrx.pdfiumModulePath = Platform.environment['PDFIUM_LIBRARY'];
  native.Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;
  tearDownAll(() => PdfRuntime.instance.shutdown());

  Future<PdfBook> open(String path, {PdfTextSupply? textSupply}) async {
    final book = await PdfRuntime.instance.open(
      await File(path).readAsBytes(),
      'e' * 64,
      textSupply: textSupply,
      hop: runInWorker,
    );
    addTearDown(book.dispose);
    return book;
  }

  /// Every page of [book], analyzed, with its text unless [scanned].
  Future<List<AnalyzedSourcePage>> analyzed(
    PdfBook book, {
    bool scanned = false,
  }) async => [
    for (var number = 1; number <= book.pageCount; number++)
      await book.reflowPage(number).then((page) async {
        final attached = scanned ? null : await page!.attachedText();
        return (
          sourcePage: number,
          geometry: page!.geometry,
          analysis: page.analysis,
          text: attached == null
              ? null
              : (
                  source: attached.text.source,
                  attachment: attached.attachment!,
                ),
        );
      }),
  ];

  /// The pages of margins-book.pdf with their text, and the same pages with
  /// their running lines marked.
  Future<(List<AnalyzedSourcePage>, List<PageAnalysis>)> book() async {
    final pages = await analyzed(await open(marginsBook));
    final templates = findRunningTemplates(pages);
    return (pages, [for (final page in pages) templates.mark(page)]);
  }

  group('running headers and folios of a born-digital book', () {
    test(
      'are marked on every page that has them, and no other line is',
      () async {
        final (pages, marked) = await book();
        expect(pages, hasLength(13));
        for (final page in pages) {
          final number = page.sourcePage;
          final texts = lineTexts(page)!;
          final analysis = marked[number - 1];
          analysis.checkInvariants(page.geometry);
          expect(
            {for (final line in runningLinesOf(analysis)) texts[line]},
            switch (number) {
              1 => <String>{},
              2 || 8 => {'${number - 1}'},
              _ => {
                number.isOdd ? chapterOf(number) : bookTitle,
                '${number - 1}',
              },
            },
            reason: 'page $number',
          );
        }
      },
    );

    test('a chapter title at the top of a chapter start is not marked, '
        'though the running header of its chapter has its words', () async {
      final (pages, marked) = await book();
      for (final number in [2, 8]) {
        final page = pages[number - 1];
        final title = lineTexts(page)!.indexOf(chapterOf(number));
        expect(title, 0, reason: 'page $number');
        final box = page.geometry.boxes;
        final first = page.geometry.lineStarts[title];
        // The title's middle lies within 12 percent of the page height from
        // the top edge, where a running header can be.
        expect(
          (box[first * 4 + 1] + box[first * 4 + 3]) / 2,
          lessThan(0.12 * page.geometry.height),
        );
        expect(marked[number - 1].isRunning(title), isFalse);
      }
    });

    test('footnotes and a figure near the bottom of a page stay in the '
        'content box', () async {
      final (pages, marked) = await book();
      final footnotes = pages[3];
      final texts = lineTexts(footnotes)!;
      final notes = [
        for (var line = 0; line < texts.length; line++)
          if (texts[line].startsWith('1Galileo') ||
              texts[line].startsWith('2Christiaan'))
            line,
      ];
      expect(notes, hasLength(2));
      final noteBox = marked[3].contentBox(footnotes.geometry);
      for (final line in notes) {
        expect(marked[3].isRunning(line), isFalse);
        for (final word in wordsOf(footnotes.geometry, line)) {
          expect(inside(noteBox, footnotes.geometry.boxes, word), isTrue);
        }
      }

      final figure = pages[5];
      final figureBox = marked[5].contentBox(figure.geometry);
      expect(figure.analysis.regionCount, greaterThan(0));
      for (var region = 0; region < figure.analysis.regionCount; region++) {
        expect(inside(figureBox, figure.analysis.regionBoxes, region), isTrue);
      }
      final caption = lineTexts(figure)!
          .indexWhere((text) => text.startsWith('Figure 1:'));
      expect(marked[5].isRunning(caption), isFalse);
      for (final word in wordsOf(figure.geometry, caption)) {
        expect(inside(figureBox, figure.geometry.boxes, word), isTrue);
      }
    });

    test('the content box holds every word and region that is not in a '
        'running line, and no word of a running line', () async {
      final (pages, marked) = await book();
      for (final page in pages) {
        final geometry = page.geometry;
        final analysis = marked[page.sourcePage - 1];
        final box = analysis.contentBox(geometry);
        for (var line = 0; line < geometry.lineCount; line++) {
          for (final word in wordsOf(geometry, line)) {
            expect(
              analysis.isRunning(line)
                  ? !overlaps(box, geometry.boxes, word)
                  : inside(box, geometry.boxes, word),
              isTrue,
              reason: 'page ${page.sourcePage}, line $line, word $word',
            );
          }
        }
        for (var region = 0; region < analysis.regionCount; region++) {
          expect(inside(box, analysis.regionBoxes, region), isTrue);
        }
      }
    });

    test('a table wider than the text widens the content box past the text '
        'column', () async {
      final (pages, marked) = await book();
      final page = pages[9];
      final box = marked[9].contentBox(page.geometry);
      final text = marked[11].contentBox(pages[11].geometry);
      expect(page.analysis.regionCount, 1);
      expect(inside(box, page.analysis.regionBoxes, 0), isTrue);
      // Page 12, on the same side, has only text.
      expect(box[0], lessThan(text[0] - 0.03));
      expect(box[2], greaterThan(text[2] + 0.03));
    });

    test('the template finder runs in another isolate', () async {
      final (pages, marked) = await book();
      final templates = await runInWorker(findRunningTemplates, pages);
      for (final page in pages) {
        expect(
          runningLinesOf(templates.mark(page)),
          runningLinesOf(marked[page.sourcePage - 1]),
        );
      }
    });
  });

  group('templates found by repetition', () {
    /// Analyzed made-up pages [first] and on, each with a header [header] of
    /// that page and a bottom line [bottom] of that page (null for none),
    /// over 30 lines of prose.
    Future<List<AnalyzedSourcePage>> pagesWith(
      List<int> numbers, {
      List<String>? Function(int number)? header,
      (String, int)? Function(int number)? bottom,
    }) async {
      final drawn = <DrawnPage>[];
      final texts = <List<List<String>>>[];
      for (final number in numbers) {
        final top = header?.call(number);
        final end = bottom?.call(number);
        final body = proseLines(30, top: 300);
        drawn.add(
          DrawnPage([
            if (top != null) lineOf(top, top: 120),
            ...body,
            if (end != null) lineOf([end.$1], top: 2240, left: end.$2),
          ]),
        );
        texts.add([
          ?top,
          for (final line in body)
            ['word', for (final _ in line.skip(1)) 'text'],
          if (end != null) [end.$1],
        ]);
      }
      final pdf = DrawnPdf(drawn, hop: runInWorker);
      return [
        for (final (index, number) in numbers.indexed)
          withText(number, (await pdf.reflowPage(index + 1))!, texts[index]),
      ];
    }

    test('a number whose difference from the source page number stays the '
        'same on 3 pages is a folio, wherever it sits', () async {
      final pages = await pagesWith([
        11,
        12,
        13,
        14,
      ], bottom: (number) => ('${number + 4}', 200 + number % 3 * 500));
      final templates = findRunningTemplates(pages);
      for (final page in pages) {
        expect(runningLinesOf(templates.mark(page)), [30]);
      }
    });

    test('roman numbers count as folios too', () async {
      final pages = await pagesWith([
        3,
        4,
        5,
      ], bottom: (number) => (['i', 'ii', 'iii'][number - 3], 700));
      final templates = findRunningTemplates(pages);
      for (final page in pages) {
        expect(runningLinesOf(templates.mark(page)), [30]);
      }
    });

    test('a number that does not keep its difference from the source page '
        'number is not a folio', () async {
      final pages = await pagesWith([
        11,
        12,
        13,
        14,
      ], bottom: (number) => ('${number * 3}', 200 + number % 3 * 500));
      final templates = findRunningTemplates(pages);
      for (final page in pages) {
        expect(runningLinesOf(templates.mark(page)), isEmpty);
      }
    });

    test('a header text that changes only in its digits repeats', () async {
      final pages = await pagesWith([
        11,
        12,
        13,
      ], header: (number) => ['Chapter', 'Two,', 'page', '${number * 7}']);
      final templates = findRunningTemplates(pages);
      for (final page in pages) {
        expect(runningLinesOf(templates.mark(page)), [0]);
      }
    });

    test('a header text on only 2 pages within 20 source pages is not a '
        'header', () async {
      final pages = await pagesWith([
        1,
        2,
        30,
        31,
      ], header: (number) => ['The', 'Same', 'Words']);
      final templates = findRunningTemplates(pages);
      for (final page in pages) {
        expect(runningLinesOf(templates.mark(page)), isEmpty);
      }
    });
  });

  group('a scanned book without text', () {
    test('its running headers and folios are marked from the place and size '
        'of their lines, as the born-digital book marks them', () async {
      final (_, withText) = await book();
      final scanned = await analyzed(
        ScannedCopy(await open(marginsBook)),
        scanned: true,
      );
      final templates = findRunningTemplates(scanned);
      for (final page in scanned) {
        expect(page.text, isNull);
        final marked = templates.mark(page);
        marked.checkInvariants(page.geometry);
        expect(
          runningLinesOf(marked),
          runningLinesOf(withText[page.sourcePage - 1]),
          reason: 'page ${page.sourcePage}',
        );
      }
    });

    test('a first body line at the same place on every page is not a running '
        'line, and a folio set apart below the text is', () async {
      final pdf = DrawnPdf([
        for (var page = 0; page < 8; page++)
          DrawnPage([
            ...proseLines(30, top: 100),
            lineOf(['${page + 1}'], top: 2280, left: 780),
          ]),
      ], hop: runInWorker);
      final pages = [
        for (var number = 1; number <= 8; number++)
          await pdf
              .reflowPage(number)
              .then(
                (page) => (
                  sourcePage: number,
                  geometry: page!.geometry,
                  analysis: page.analysis,
                  text: null,
                ),
              ),
      ];
      final templates = findRunningTemplates(pages);
      for (final page in pages) {
        expect(runningLinesOf(templates.mark(page)), [30]);
      }
    });

    test('a mark that repeats in the margin but is no text line is never a '
        'running line, and stays in the content box', () async {
      final drawn = [
        for (var page = 0; page < 6; page++)
          DrawnPage(proseLines(30, top: 300))..ink([700, 100, 900, 160]),
      ];
      final pdf = DrawnPdf(drawn, hop: runInWorker);
      final pages = [
        for (var number = 1; number <= 6; number++)
          await pdf
              .reflowPage(number)
              .then(
                (page) => (
                  sourcePage: number,
                  geometry: page!.geometry,
                  analysis: page.analysis,
                  text: null,
                ),
              ),
      ];
      final templates = findRunningTemplates(pages);
      for (final page in pages) {
        final marked = templates.mark(page);
        expect(runningLinesOf(marked), isEmpty);
        expect(marked.contentBox(page.geometry)[1] * 1600, closeTo(100, 1));
      }
    });
  });

  group('scan edges', () {
    test('the dark bottom edge of the Raven scan does not stretch its content '
        'box to the edge of the page', () async {
      final supply = FixtureRecognition('scanned-page')..textArrives.complete();
      final pdf = await open(ravenPage, textSupply: supply);
      final page = (await pdf.reflowPage(1))!;
      final geometry = page.geometry, analysis = page.analysis;
      final box = analysis.contentBox(geometry);
      // The verse ends 2223 pixels down a page 2594 pixels tall, the folio
      // ends at 2263, and the dark edge of the scan starts at 2580.
      expect(box[3] * 1600, closeTo(2263, 2));
      for (var line = 0; line < geometry.lineCount; line++) {
        for (final word in wordsOf(geometry, line)) {
          expect(inside(box, geometry.boxes, word), isTrue);
        }
      }
      final engraving = [
        for (var region = 0; region < analysis.regionCount; region++)
          if (analysis.regionKind(region) == RegionKind.picture &&
              analysis.regionBoxes[region * 4 + 3] -
                      analysis.regionBoxes[region * 4 + 1] >
                  0.5)
            region,
      ].single;
      expect(inside(box, analysis.regionBoxes, engraving), isTrue);
    });

    test('a thin dark band along a page edge stays out of the content box, '
        'and a picture that touches the edge stays in', () async {
      final drawn = DrawnPage(proseLines(30, top: 300))
        ..ink([0, 0, 12, 2400])
        ..ink([1300, 2000, 1600, 2400]);
      final pdf = DrawnPdf([drawn], hop: runInWorker);
      final page = (await pdf.reflowPage(1))!;
      final box = page.analysis.contentBox(page.geometry);
      expect(box[0] * 1600, closeTo(100, 1));
      expect(box[2] * 1600, closeTo(1600, 1));
      expect(box[3] * 1600, closeTo(2400, 1));
    });
  });
}
