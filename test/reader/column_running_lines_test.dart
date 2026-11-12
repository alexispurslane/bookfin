import 'dart:io';

import 'package:bookfin/reader/column_layout.dart';
import 'package:bookfin/reader/page_analysis.dart';
import 'package:bookfin/reader/pdf.dart';
import 'package:bookfin/reader/running_lines.dart';
import 'package:bookfin/reader/survey_files.dart';
import 'package:bookfin/reader/word_pages.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart' as native;

import 'book_survey_test.dart' show leaseOf, until;
import 'column_layout_test.dart' show lineOf, pieceOf, screenOf;
import 'ocr_hop_test.dart' show runInWorker;
import 'running_lines_test.dart'
    show ScannedCopy, bookTitle, chapterOf, lineTexts, marginsBook, wordsOf;

/// The lines of page [number] of margins-book.pdf, whose line texts are
/// [texts], that print its running header or its folio. The title page
/// has neither, and a chapter's first page has only its folio. Each folio
/// is its source page number minus one.
Set<int> headerAndFolio(int number, List<String> texts) => {
  for (var line = 0; line < texts.length; line++)
    if (number > 1 &&
        (texts[line] == '${number - 1}' ||
            number != 8 &&
                number != 2 &&
                texts[line] == (number.isOdd ? chapterOf(number) : bookTitle)))
      line,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  native.Pdfrx.pdfiumModulePath = Platform.environment['PDFIUM_LIBRARY'];
  native.Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;
  tearDownAll(() => PdfRuntime.instance.shutdown());

  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('bookfin-column-running-');
  });
  tearDown(() => root.delete(recursive: true));

  final settings = ColumnSettings(width: 360, fontSize: 20, screenHeight: 240);

  Future<PdfBook> margins() async {
    final book = await PdfRuntime.instance.open(
      marginsBook,
      'f' * 64,
      hop: runInWorker,
    );
    addTearDown(book.dispose);
    return book;
  }

  /// [book] once its survey froze the book profile.
  Future<PdfBook> surveyed(PdfBook book) async {
    final original = await File('${root.path}/${book.originalDigest}')
        .writeAsString('%PDF-');
    book.survey.start(
      SurveyFiles(
        leaseOf(original, book.originalDigest),
        book: book.originalDigest,
        hop: book.hop,
      ),
      from: 1,
    );
    await until(() => book.survey.profile != null, 'the profile froze');
    return book;
  }

  /// Page [number] of [book] with its reflow geometry and analysis, and the
  /// text of the same page of [textOf], which shares its word geometry.
  Future<AnalyzedSourcePage> withText(
    PdfBook book,
    int number, {
    PdfBook? textOf,
  }) async {
    final page = (await book.reflowPage(number))!;
    final text = textOf ?? book;
    final read = await text.attachedText(
      number,
      (await text.geometry(number))!,
    );
    return (
      sourcePage: number,
      geometry: page.geometry,
      analysis: page.analysis,
      text: (
        source: read.text.source,
        attachment: reflowAttachment(read.attachment!, page.analysis),
      ),
    );
  }

  /// Whether [word] of [page] shows in [column], alone or in its region.
  bool shows(ReflowColumn column, AnalyzedSourcePage page, int word) {
    final region = page.analysis.wordRegions[word];
    for (var piece = 0; piece < column.pieceCount; piece++) {
      if (region < 0
          ? column.word(piece) == word
          : column.region(piece) == region) {
        return true;
      }
    }
    return false;
  }

  /// Expects that [column] of [page] shows no word of a running header or
  /// folio, and every other word and region of the page.
  void expectContent(ReflowColumn column, AnalyzedSourcePage page) {
    final number = page.sourcePage;
    final running = headerAndFolio(number, lineTexts(page)!);
    expect(
      running,
      hasLength(
        number == 1
            ? 0
            : number == 2 || number == 8
            ? 1
            : 2,
      ),
    );
    for (var line = 0; line < page.geometry.lineCount; line++) {
      for (final word in wordsOf(page.geometry, line)) {
        expect(
          shows(column, page, word),
          !running.contains(line),
          reason: 'page $number, line $line, word $word',
        );
      }
    }
    for (var region = 0; region < page.analysis.regionCount; region++) {
      expect(
        [
          for (var piece = 0; piece < column.pieceCount; piece++)
            column.region(piece),
        ],
        contains(region),
        reason: 'page $number, region $region',
      );
    }
  }

  test('the word view of the margins book shows no running header and no '
      'folio, and shows every other word and region, such as its footnotes '
      'and its figure', () async {
    final book = await surveyed(await margins());
    for (var number = 1; number <= book.pageCount; number++) {
      final column = await (await book.reflowPage(number))!.column(settings);
      column.checkInvariants();
      expectContent(column, await withText(book, number));
    }
  });

  test('the word pages that the viewport draws leave out the running '
      'headers and folios that the frozen profile marks', () async {
    final book = await surveyed(await margins());
    final pages = PdfWordPages(book);
    addTearDown(pages.dispose);
    final wordSettings = (
      width: settings.width,
      fontSize: settings.fontSize,
      screenHeight: settings.screenHeight,
      devicePixelRatio: 2.625,
    );
    for (final number in [3, 4, 9]) {
      final column = (await pages.column(number, wordSettings))!.column;
      expectContent(column, await withText(book, number));
    }
  });

  test('a shown word column stays unchanged when the book profile freezes '
      'and a text size change then uses the frozen profile', () async {
    final book = await margins();
    final pages = PdfWordPages(book);
    addTearDown(pages.dispose);
    final beforeSettings = (
      width: settings.width,
      fontSize: settings.fontSize,
      screenHeight: settings.screenHeight,
      devicePixelRatio: 2.625,
    );
    final before = (await pages.column(3, beforeSettings))!;
    await pages.show(3, beforeSettings, 0);
    final page = await withText(book, 3);
    final running = headerAndFolio(3, lineTexts(page)!);
    final headerWord = page.geometry.lineStarts[running.first];
    expect(shows(before.column, page, headerWord), isTrue);
    await surveyed(book);
    expect(await pages.column(3, beforeSettings), same(before));
    expect(shows(before.column, page, headerWord), isTrue);
    final afterSettings = (
      width: beforeSettings.width,
      fontSize: 30.0,
      screenHeight: beforeSettings.screenHeight,
      devicePixelRatio: beforeSettings.devicePixelRatio,
    );
    final after = (await pages.column(3, afterSettings))!;
    expectContent(after.column, page);
    await pages.show(3, afterSettings, 0);
    final returned = (await pages.column(3, beforeSettings))!;
    expectContent(returned.column, page);
    await pages.show(3, beforeSettings, 0);
    expect(pages.shown.value!.column, same(returned));
    pages.checkInvariants();
  });

  test('returning to a page after the profile freezes replaces its old '
      'running-header column', () async {
    final book = await margins();
    final pages = PdfWordPages(book);
    addTearDown(pages.dispose);
    final wordSettings = (
      width: settings.width,
      fontSize: settings.fontSize,
      screenHeight: settings.screenHeight,
      devicePixelRatio: 2.625,
    );
    await pages.show(3, wordSettings, 0);
    final before = pages.shown.value!.column;
    await surveyed(book);
    expect(pages.shown.value!.column, same(before));
    await pages.show(4, wordSettings, 0);
    await pages.show(3, wordSettings, 0);
    expectContent(pages.shown.value!.column.column, await withText(book, 3));
    pages.checkInvariants();
  });

  test('a search hit in a running header opens the page\'s first screen, a '
      'place inside the folio opens the screen of the next shown word, and a '
      'place in the text opens its own screen', () async {
    final book = await surveyed(await margins());
    // Page 4 has a running header, footnotes and a folio, on 4 screens.
    final reflow = (await book.reflowPage(4))!;
    final column = await reflow.column(settings);
    final attached = await reflow.attachedText();
    final source = attached.text.source;
    final ranges = attached.attachment!;
    expect(column.screenCount, greaterThan(2));

    final hit = source.indexOf(bookTitle);
    expect(hit, greaterThanOrEqualTo(0));
    expect(column.screenAt(hit + 8, ranges, reflow.analysis), 0);

    // The folio "3" ends the page's reading text, so no shown word follows
    // it, and its place opens the page's last screen.
    final folio = source.lastIndexOf('3');
    expect(source.substring(folio).trim(), '3');
    expect(
      column.screenAt(folio, ranges, reflow.analysis),
      column.screenCount - 1,
    );

    final page = await withText(book, 4);
    final texts = lineTexts(page)!;
    final note = texts.indexWhere((text) => text.startsWith('2Christiaan'));
    final word = page.geometry.lineStarts[note] + 1;
    expect(
      column.screenAt(ranges[word * 2] + 1, ranges, reflow.analysis),
      screenOf(column, lineOf(column, pieceOf(column, word))),
    );
  });

  test('a scanned copy without text leaves out its running headers and '
      'folios from their place and size, and its column reads no text, so '
      'the arrival of its text cannot change its screens', () async {
    final born = await margins();
    final scanned = await surveyed(ScannedCopy(born));
    for (var number = 1; number <= scanned.pageCount; number++) {
      // ScannedCopy fails the test when anything reads its text.
      final column = await (await scanned.reflowPage(number))!.column(settings);
      expectContent(column, await withText(scanned, number, textOf: born));
    }
  });
}
