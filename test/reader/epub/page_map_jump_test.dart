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
    test('the jump into Roget', () {}, skip: 'set BOOKFIN_EPUB_CORPUS=1');
    return;
  }
  setUpAll(loadReaderFont);

  for (final id in [
    'pg-10681-rogets-thesaurus',
    'se-ulysses',
    'se-bleak-house',
  ]) {
    test('a jump into the middle of the largest section of $id with a kept '
        'page map does no line search', () async {
      final entry = corpusList().singleWhere((book) => book.id == id);
      final book = CorpusBook.open(await entry.file.readAsBytes());
      final publication = book.publication;
      final largest =
          [for (var index = 0; index < book.sections; index++) index].reduce(
            (a, b) =>
                publication.resources[publication.spine[a]]!.length >=
                    publication.resources[publication.spine[b]]!.length
                ? a
                : b,
          );
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

      /// A jump to the middle of the largest section, after its prepare: to
      /// the page at the line that holds the place when [anchored], else to
      /// the true page that holds it.
      Future<
        ({Duration took, int lineSearches, int measuredCells, LaidPage page})
      >
      jump(BookPageMaps? pageMaps, {bool anchored = false}) async {
        final scheduler = TestScheduler();
        final source = PageSource(
          publication,
          schedule: scheduler.schedule,
          pageMaps: pageMaps,
        )..settings = readerPage;
        addTearDown(source.dispose);
        final section = await scheduler.until(source.section(largest));
        final place = placeIn(section, .5);
        final cells = LayoutRun.measuredCells;
        final clock = Stopwatch()..start();
        final page = await scheduler.until(
          source.pageAt(place, anchored: anchored, urgent: true),
        );
        return (
          took: clock.elapsed,
          lineSearches: source.lineSearches,
          measuredCells: LayoutRun.measuredCells - cells,
          page: page,
        );
      }

      final plain = await jump(null);
      final anchored = await jump(null, anchored: true);
      final kept = await jump(pageMaps);
      // ignore: avoid_print
      print(
        'JUMP $id section $largest: '
        'without a map ${plain.took.inMilliseconds} ms to the true page, '
        '${anchored.took.inMilliseconds} ms to the anchored page; '
        'with a map ${kept.took.inMilliseconds} ms to the true page; '
        'table cells measured ${plain.measuredCells} without a map, '
        '${kept.measuredCells} with one',
      );

      expect(kept.lineSearches, 0);
      // With a map, a jump checks the kept widths of the rows that it lays
      // out, and measures no other table cell.
      expect(
        kept.measuredCells,
        plain.measuredCells == 0 ? 0 : lessThan(plain.measuredCells ~/ 10),
      );
      expect(plain.lineSearches, 1);
      expect(kept.page.start, plain.page.start);
      expect(kept.page.startPlace, plain.page.startPlace);
    }, timeout: Timeout.none);
  }
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
