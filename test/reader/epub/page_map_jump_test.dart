// The on-demand check of a jump with a kept page map in real books
// (t5-q0hs, t5-s1vy). Before the map kept each page's first place, a jump
// into the middle of the largest section took a line search of 2.5 s on
// the host in Gutenberg's Roget's Thesaurus (one table of 1,187 cells),
// 164 ms in Standard Ebooks' Ulysses and 63 ms in Bleak House (long
// paragraphs). Before the map kept table cell widths, the page from the
// kept start measured the whole table instead. It is not part of
// Bookfin's normal test run. Each book prints its times.
//
// In the dev shell, from the repository root, after
// python3 -I tool/reader/fetch_epub_corpus.py:
//
//   BOOKFIN_EPUB_CORPUS=1 flutter test test/reader/epub/page_map_jump_test.dart
import 'dart:io';
import 'dart:math' as math;

import 'package:bookfin/reader/epub/dom.dart';
import 'package:bookfin/reader/epub/fonts.dart';
import 'package:bookfin/reader/epub/layout.dart';
import 'package:bookfin/reader/epub/page_maps.dart';
import 'package:bookfin/reader/epub/page_source.dart';
import 'package:bookfin/reader/epub/prepare.dart';
import 'package:flutter_test/flutter_test.dart';

import 'corpus/book.dart';
import 'corpus/list.dart';
import 'helpers.dart';
import 'page_source_test.dart' show TestScheduler, placeIn;

final _enabled = Platform.environment['BOOKFIN_EPUB_CORPUS'] == '1';

void main() {
  if (!_enabled) {
    test('the jumps into real books', () {}, skip: 'set BOOKFIN_EPUB_CORPUS=1');
    return;
  }
  setUpAll(loadReaderFont);

  for (final (id, where) in [
    ('pg-10681-rogets-thesaurus', _Where.largestSection),
    ('se-ulysses', _Where.largestSection),
    ('se-bleak-house', _Where.largestSection),
    ('pg-1322-leaves-of-grass', _Where.longestParagraph),
    ('pg-24264-hong-lou-meng', _Where.longestParagraph),
    ('pg-1228-origin-of-species', _Where.longestParagraph),
    ('se-ulysses', _Where.longestParagraph),
  ]) {
    test('a jump into the middle of the ${where.name} of $id with a kept '
        'page map does no line search', () async {
      final entry = corpusList().singleWhere((book) => book.id == id);
      final book = CorpusBook.open(await entry.file.readAsBytes());
      final publication = book.publication;
      final (index, picked) = switch (where) {
        _Where.largestSection => (_largestSection(book), null),
        _Where.longestParagraph => _longestParagraph(book),
      };
      final folder = await Directory.systemTemp.createTemp('bookfin-jump-');
      addTearDown(() => folder.delete(recursive: true));
      final download = await File('${folder.path}/complete').writeAsBytes([0]);
      final pageMaps = BookPageMaps(
        download,
        book: publication.identity,
        engine: Future.value('install-1\nbuild-1\nen-US'),
      );
      await pageMaps.write(readerPage, [
        for (var index = 0; index < book.sections; index++)
          await _keptSection(book, index),
      ]);

      /// A jump to the place, after its section's prepare: to the page at
      /// the line that holds the place when [anchored], else to the true
      /// page that holds it.
      Future<
        ({
          Duration took,
          int lineSearches,
          int measuredCells,
          int laidOutUnits,
          LaidPage page,
        })
      >
      jump(BookPageMaps? pageMaps, {bool anchored = false}) async {
        final scheduler = TestScheduler();
        final source = PageSource(
          publication,
          schedule: scheduler.schedule,
          pageMaps: pageMaps,
        )..settings = readerPage;
        addTearDown(source.dispose);
        final section = await scheduler.until(source.section(index));
        final place = picked?.place ?? placeIn(section, .5);
        final cells = LayoutRun.measuredCells;
        final units = LayoutRun.laidOutUnits;
        final clock = Stopwatch()..start();
        final page = await scheduler.until(
          source.pageAt(place, anchored: anchored, urgent: true),
        );
        return (
          took: clock.elapsed,
          lineSearches: source.lineSearches,
          measuredCells: LayoutRun.measuredCells - cells,
          laidOutUnits: LayoutRun.laidOutUnits - units,
          page: page,
        );
      }

      final plain = await jump(null);
      final anchored = await jump(null, anchored: true);
      final kept = await jump(pageMaps);

      // The same jump through PageSource.findPlace, which can lay the page
      // out from a part of the section (t7-49gt), with the kept map.
      final scheduler = TestScheduler();
      final source = PageSource(
        publication,
        schedule: scheduler.schedule,
        pageMaps: pageMaps,
      )..settings = readerPage;
      addTearDown(source.dispose);
      var dropped = 0;
      source.keptMapDropped.addListener(() => dropped++);
      final place = await scheduler.until(
        source.findPlace(index, _fixed(plain.page.startPlace!)),
      );
      final fromPart = await scheduler.until(
        source.pageAt(place!, anchored: false, urgent: true),
      );
      expect(dropped, 0, reason: 'a part keeps the kept map');
      expect(pageKey(fromPart), pageKey(plain.page));
      // ignore: avoid_print
      print(
        'JUMP $id ${where.name} section $index'
        '${picked == null ? '' : ' (${picked.length} code units)'}: '
        'without a map ${plain.took.inMilliseconds} ms to the true page, '
        '${anchored.took.inMilliseconds} ms to the anchored page; '
        'with a map ${kept.took.inMilliseconds} ms to the true page; '
        'table cells measured ${plain.measuredCells} without a map, '
        '${kept.measuredCells} with one; code units laid out '
        '${anchored.laidOutUnits} for the anchored page, '
        '${kept.laidOutUnits} with a map',
      );

      expect(kept.lineSearches, 0);
      // With a map, a jump checks the kept widths of the rows that it lays
      // out, and measures no other table cell.
      expect(
        kept.measuredCells,
        plain.measuredCells == 0 ? 0 : lessThan(plain.measuredCells ~/ 10),
      );
      // With a map, a jump into the middle of a long paragraph lays out the
      // segments of its pages, and none before them.
      if (picked != null) {
        expect(kept.laidOutUnits, lessThan(picked.length ~/ 4));
      }
      expect(plain.lineSearches, 1);
      expect(kept.page.start, plain.page.start);
      expect(kept.page.startPlace, plain.page.startPlace);
    }, timeout: Timeout.none);
  }
}

/// Finds [place]. Static, so that a worker can run it.
EpubPlace? Function(DomSection dom) _fixed(EpubPlace place) =>
    (_) => place;

/// Where a jump goes: to the middle of a book's largest section, or to the
/// middle of its longest paragraph.
enum _Where { largestSection, longestParagraph }

/// The index of the largest section of [book], by its XHTML's bytes.
int _largestSection(CorpusBook book) {
  final publication = book.publication;
  return [for (var index = 0; index < book.sections; index++) index].reduce(
    (a, b) =>
        publication.textFiles[publication.spine[a]]!.length >=
            publication.textFiles[publication.spine[b]]!.length
        ? a
        : b,
  );
}

/// The section of the longest paragraph of [book], the place at its middle
/// code unit, and its length in code units.
(int, ({EpubPlace place, int length})) _longestParagraph(CorpusBook book) {
  var best = (0, const EpubPlace(0, 0, 0), 0);
  for (var index = 0; index < book.sections; index++) {
    final section = prepareSections([book.source(index)], readerPage).single;
    for (final item in section.flow) {
      if (item is! ParagraphItem) continue;
      final runs = item.text.runs;
      final length = runs.fold(
        0,
        (sum, run) => sum + (run is TextRun ? run.text.length : 1),
      );
      if (length <= best.$3) continue;
      var at = 0;
      for (final run in runs) {
        if (run is TextRun && at + run.text.length > length ~/ 2) {
          best = (
            index,
            EpubPlace(index, run.node, run.offsets[length ~/ 2 - at]),
            length,
          );
          break;
        }
        at += run is TextRun ? run.text.length : 1;
      }
    }
  }
  return (best.$1, (place: best.$2, length: best.$3));
}

/// The kept page map section of section [index] of [book], as the page
/// source keeps it once the section's main run ended.
Future<KeptSection> _keptSection(CorpusBook book, int index) async {
  final section = prepareSections([book.source(index)], readerPage).single;
  if (section.fonts.isNotEmpty) {
    await BookFonts.load(section.fonts, book.resource, book.fontPrefix);
  }
  final chapter = layoutSection(section);
  try {
    final visible = <int>[];
    for (final page in chapter.pages) {
      visible.add(
        visible.isEmpty ? 0 : math.max(page.startVisible, visible.last),
      );
    }
    return KeptSection(
      [for (final page in chapter.pages) page.start],
      firsts: [for (final page in chapter.pages) page.startPlace],
      visible: (starts: visible, length: section.dom.visibleLength),
      complete: true,
      measures: measuresOf(section),
    );
  } finally {
    chapter.dispose();
  }
}
