import 'dart:io';
import 'dart:typed_data';

import 'package:bookfin/reader/book_crop.dart';
import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/page_geometry.dart';
import 'package:bookfin/reader/pdf.dart';
import 'package:bookfin/reader/running_lines.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart' as native;

import 'ocr_hop_test.dart' show runInWorker;
import 'page_analysis_test.dart'
    show DrawnPage, DrawnPdf, FixtureRecognition, proseLines, ravenPage;
import 'running_lines_test.dart' show marginsBook;

/// A book whose pages come from other books: page n of this book is the
/// page [pages] names at index n - 1. It counts the pages that it draws at
/// the analysis width.
class SplicedBook extends PdfBook {
  SplicedBook(this.pages) : super(hop: runInWorker);
  final List<(PdfBook, int)> pages;

  /// The source pages that were drawn for an analysis, in order.
  final analyzed = <int>[];

  @override
  String get originalDigest => 'spliced';
  @override
  String get identity => 'spliced';
  @override
  String get engine => 'spliced';
  @override
  String get policy => 'spliced';
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
  PdfTextSupply? get textSupply => null;
  @override
  Future<PdfText> textLayer(int sourcePage) {
    final (book, page) = pages[sourcePage - 1];
    return book.textLayer(page);
  }

  @override
  Future<PdfText> text(int sourcePage) {
    final (book, page) = pages[sourcePage - 1];
    return book.text(page);
  }

  @override
  Future<PageGeometry?> geometry(int sourcePage, {bool background = false}) {
    final (book, page) = pages[sourcePage - 1];
    return book.geometry(page, background: background);
  }

  @override
  Future<({PdfText text, TextAttachment? attachment})> attachedText(
    int sourcePage,
    PageGeometry geometry,
  ) {
    final (book, page) = pages[sourcePage - 1];
    return book.attachedText(page, geometry);
  }

  @override
  Future<PdfRaster> render(int sourcePage, double width) {
    if (width == 1600) analyzed.add(sourcePage);
    final (book, page) = pages[sourcePage - 1];
    return book.render(page, width);
  }
}

/// A scanned book of one blank page: no ink and no words.
class BlankPdf extends DrawnPdf {
  BlankPdf() : super([DrawnPage(const [])], hop: runInWorker);
  @override
  Future<PageGeometry?> geometry(
    int sourcePage, {
    bool background = false,
  }) async => pageGeometryFromLayout(
    Int32List.fromList([0, 0, 0, 1600, 2400, 0, 0, 0, 0]),
  );
}

/// [page] as the template finder reads it, with its text when its text
/// layer is a candidate.
Future<AnalyzedSourcePage> analyzedPage(PdfBook book, int number) async {
  final page = (await book.reflowPage(number))!;
  final layer = await book.textLayer(number);
  final attached = layer.status == PdfTextStatus.candidate
      ? await page.attachedText()
      : null;
  return (
    sourcePage: number,
    geometry: page.geometry,
    analysis: page.analysis,
    text: attached == null
        ? null
        : (source: attached.text.source, attachment: attached.attachment!),
  );
}

/// Whether [outer] holds [inner].
bool holds(PageBox outer, PageBox inner) =>
    outer.left <= inner.left + 1e-6 &&
    outer.top <= inner.top + 1e-6 &&
    outer.right >= inner.right - 1e-6 &&
    outer.bottom >= inner.bottom - 1e-6;

/// [page] as source page [number] of another book.
AnalyzedSourcePage renumbered(AnalyzedSourcePage page, int number) => (
  sourcePage: number,
  geometry: page.geometry,
  analysis: page.analysis,
  text: page.text,
);

/// The pages [parts] as source pages 1, 2, 3 and on of one book, surveyed.
List<SurveyedPage> bookOf(List<AnalyzedSourcePage> parts) => [
  for (final (index, page) in parts.indexed)
    surveyPage(renumbered(page, index + 1)),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  native.Pdfrx.pdfiumModulePath = Platform.environment['PDFIUM_LIBRARY'];
  native.Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;

  /// The 13 analyzed pages of the margins book, page n at index n - 1.
  late List<AnalyzedSourcePage> margins;

  /// The analyzed blank page and Raven plate.
  late AnalyzedSourcePage blank, raven;

  setUpAll(() async {
    final book = await PdfRuntime.instance.open(
      await File(marginsBook).readAsBytes(),
      'e' * 64,
      hop: runInWorker,
    );
    final scan = await PdfRuntime.instance.open(
      await File(ravenPage).readAsBytes(),
      'f' * 64,
      textSupply: FixtureRecognition('scanned-page')..textArrives.complete(),
      hop: runInWorker,
    );
    margins = [
      for (var number = 1; number <= book.pageCount; number++)
        await analyzedPage(book, number),
    ];
    raven = await analyzedPage(scan, 1);
    blank = await analyzedPage(BlankPdf(), 1);
    await book.dispose();
    await scan.dispose();
  });
  tearDownAll(() => PdfRuntime.instance.shutdown());

  /// Margins book page [number].
  AnalyzedSourcePage m(int number) => margins[number - 1];

  group('the book crop', () {
    test('a cover, a plate and a blank page do not change the side boxes, '
        'and their own crops hold their content', () {
      final plain = bookProfile(bookOf(margins));
      // The margins book has 13 pages, so these pages keep the parity of
      // the pages before them.
      final pages = bookOf([...margins, blank, raven, m(1)]);
      final profile = bookProfile(pages);

      expect(profile.boxes, plain.boxes);
      expect(profile.boxes.every((box) => box != null), isTrue);
      for (final number in [14, 15, 16]) {
        final page = pages[number - 1];
        expect(page.body, isFalse, reason: 'page $number');
        final crop = cropOf(page, profile);
        final content = contentOf(page, profile.templates);
        if (content != null) {
          expect(holds(crop, content), isTrue, reason: 'page $number');
        }
      }
      // The blank page shows its side's box.
      expect(cropOf(pages[13], profile), profile.boxes[0]);
    });

    test('every body page of a side gets its side\'s box as its crop', () {
      final pages = bookOf(margins);
      final profile = bookProfile(pages);
      for (final page in pages) {
        if (!page.body || page.sourcePage == 10) continue;
        expect(
          cropOf(page, profile),
          profile.boxes[page.sourcePage % 2],
          reason: 'page ${page.sourcePage}',
        );
      }
      // The two sides mirror their margins: 20 mm inside and 14 mm outside
      // on a page 148 mm wide.
      final even = profile.boxes[0]!, odd = profile.boxes[1]!;
      expect(odd.left - even.left, closeTo(6 / 148, 0.005));
      expect(odd.right - even.right, closeTo(6 / 148, 0.005));
    });

    test('a side box is the body pages\' content padded by half a body line '
        'height', () {
      final pages = bookOf(margins);
      final profile = bookProfile(pages);
      final even = profile.boxes[0]!;
      // Page 12 has only text, on the even side.
      final content = contentOf(pages[11], profile.templates)!;
      final padding = pages[11].edges.bodyLineHeight / 2;
      expect(content.left - even.left, closeTo(padding, 1e-3));
      expect(even.right - content.right, closeTo(padding, 1e-3));
      expect(content.top - even.top, closeTo(padding, 2e-3));
    });

    test('a page with a table wider than the text gets a larger crop that '
        'holds all of it', () {
      final pages = bookOf(margins);
      final profile = bookProfile(pages);
      final table = pages[9];
      final crop = cropOf(table, profile);
      final content = contentOf(table, profile.templates)!;
      expect(holds(crop, content), isTrue);
      expect(holds(crop, profile.boxes[0]!), isTrue);
      expect(crop.left, lessThan(profile.boxes[0]!.left - 0.03));
      expect(crop.right, greaterThan(profile.boxes[0]!.right + 0.03));
    });

    test('a page whose parity a plate flipped takes the other side\'s box '
        'when only that box holds its content', () {
      // A longer book, as the survey samples it: pages 2 to 9 seven times,
      // so each side has 28 body pages, then a plate, and pages 2 to 4
      // again, each on the other side now. Their folios keep one offset
      // from the source page numbers, as after a plate in a book.
      final pages = bookOf([
        m(1),
        for (var copy = 0; copy < 7; copy++)
          for (var number = 2; number <= 9; number++) m(number),
        raven,
        m(2),
        m(3),
        m(4),
      ]);
      final profile = bookProfile(pages);
      final flipped = pages.sublist(pages.length - 3);
      expect([for (final page in flipped) page.sourcePage % 2], [1, 0, 1]);
      for (final (index, page) in pages.sublist(1, 4).indexed) {
        expect(cropOf(page, profile), profile.boxes[page.sourcePage % 2]);
        expect(
          cropOf(flipped[index], profile),
          profile.boxes[page.sourcePage % 2],
          reason: 'page ${index + 2} after the plate',
        );
      }
    });

    test('a page\'s content without its running lines is its marked content '
        'box', () {
      final templates = findRunningTemplates(margins);
      final profile = bookProfile(bookOf(margins));
      for (final page in margins) {
        final box = templates.mark(page).contentBox(page.geometry);
        final content = contentOf(surveyPage(page), profile.templates)!;
        expect(
          [content.left, content.top, content.right, content.bottom],
          box,
          reason: 'page ${page.sourcePage}',
        );
      }
    });

    test('the profile is found in another isolate', () async {
      final pages = bookOf(margins);
      final profile = await runInWorker(bookProfile, pages);
      expect(profile.boxes, bookProfile(pages).boxes);
    });

    test('a pencil number that repeats in the margin of a scan stays out of '
        'the side boxes and the crops', () async {
      final pdf = DrawnPdf([
        for (var page = 1; page <= 8; page++)
          DrawnPage(proseLines(30, top: 300))
            ..ink(page.isEven ? [101, 61, 119, 94] : [1481, 61, 1499, 94]),
      ], hop: runInWorker);
      final pages = bookOf([
        for (var number = 1; number <= 8; number++)
          await analyzedPage(pdf, number),
      ]);
      final profile = bookProfile(pages);
      final padding = pages.first.edges.bodyLineHeight / 2;
      for (final side in [0, 1]) {
        expect(profile.boxes[side]!.top, closeTo(300 / 1600 - padding, 1e-3));
      }
      for (final page in pages) {
        expect(cropOf(page, profile), profile.boxes[page.sourcePage % 2]);
      }
    });
  });
}
