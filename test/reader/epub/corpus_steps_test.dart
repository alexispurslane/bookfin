// An on-demand run over the corpus books of tool/reader/epub_corpus.json
// that times the layout steps of every section's main run and writes a
// page dump. It is not part of Bookfin's normal test run, because its
// times come from a shared machine.
//
// In the dev shell, from the repository root, with the books in
// .cache/epub-corpus/books (see corpus_test.dart):
//
//   BOOKFIN_EPUB_CORPUS_STEPS=before flutter test \
//     test/reader/epub/corpus_steps_test.dart
//
// The value names the run. It writes .cache/epub-corpus/steps/<name>.json:
// for each book and page settings, the longest unit of work and the longest
// step of the page source's budget of 4 ms in the sections' main runs, and
// for each section two hashes per page. The page hash covers the page's
// key (helpers.dart, pageKey). The line hash covers the same, but by line
// and not by the paragraph pieces that draw the lines ([lineKey]). Two runs
// have the same pages when their hashes are equal.
// tool/reader/compare_corpus_steps.py compares two runs.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bookfin/downloads/downloads.dart';
import 'package:bookfin/reader/epub/fonts.dart';
import 'package:bookfin/reader/epub/layout.dart';
import 'package:bookfin/reader/epub/prepare.dart';
import 'package:bookfin/reader/mobi.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'corpus/book.dart';
import 'corpus/check.dart';
import 'corpus/list.dart';
import 'helpers.dart';

final _name = Platform.environment['BOOKFIN_EPUB_CORPUS_STEPS'];

/// The page source's step budget, in milliseconds.
const _budget = 4.0;

/// How many times each section is laid out. Each unit of work counts at
/// its fastest, so that a pause of the shared machine does not count.
const _times = 3;

final _watch = Stopwatch()..start();

String _hash(Object? key) => sha1
    .convert(
      utf8.encode(jsonEncode(key, toEncodable: (value) => value.toString())),
    )
    .toString()
    .substring(0, 16);

/// What a reader sees of [page], as [pageKey] gives it, but by line, not
/// by the paragraph pieces that draw the lines: each line's place, its
/// first and last character, and where its text sits, to a tenth of a
/// pixel. A segment of a paragraph measures with less float noise than the
/// whole paragraph, which moves its lines by thousandths of a pixel.
List<Object?> lineKey(LaidPage page) {
  final top = page.top;
  String tenth(double value) => value.toStringAsFixed(1);
  List<Object?> sliceKey(Slice slice) {
    final piece = slice.piece;
    final line = piece == null
        ? null
        : piece.paragraph.computeLineMetrics()[slice.line];
    return [
      tenth(slice.top - top),
      tenth(slice.bottom - top),
      slice.start,
      if (piece != null && line != null) ...[
        piece.map.placeAtUnit(slice.units.$1),
        piece.map.textPlaceAt(slice.units.$2 - 1),
        tenth(piece.x + line.left),
      ],
      [for (final cell in slice.cellSlices) ...sliceKey(cell)],
    ];
  }

  final key = pageKey(page);
  return [
    ...key.take(8),
    tenth(page.height),
    [for (final each in page.slices) sliceKey(each)],
    key.last,
  ];
}

void main() {
  final name = _name;
  if (name == null || name.isEmpty) {
    test(
      'the corpus steps',
      () {},
      skip: 'set BOOKFIN_EPUB_CORPUS_STEPS to a run name to run',
    );
    return;
  }
  setUpAll(loadReaderFont);
  final results = <String, Object>{};
  final file = File('.cache/epub-corpus/steps/$name.json');
  for (final book in corpusList()) {
    test(book.id, () async {
      final bytes = book.url == null
          ? showcaseBooks()[book.id]!
          : await book.file.readAsBytes();
      final opened = await _open(book, bytes);
      final found = <String, Object>{};
      for (final settings in corpusSettings) {
        var longest = 0.0;
        String? where;
        var longestUnit = 0.0;
        String? unitWhere;
        final sections = <String, List<String>>{};
        final sectionLines = <String, List<String>>{};
        for (var index = 0; index < opened.sections; index++) {
          final section = prepareSections([
            opened.source(index),
          ], settings).single;
          if (section.fonts.isNotEmpty) {
            await BookFonts.load(
              section.fonts,
              opened.resource,
              opened.fontPrefix,
            );
          }
          // Each unit of work timed in three runs, at its fastest. Each run
          // lays out the section prepared again, because a run keeps what it
          // found for the other runs of its prepared section, such as a
          // table's column widths, so that the units of later runs differ.
          List<double>? fastest;
          late List<int> items;
          late List<String> hashes;
          late List<String> lines;
          for (var time = 0; time < _times; time++) {
            final run = LayoutRun(
              time == 0
                  ? section
                  : prepareSections([opened.source(index)], settings).single,
            );
            final took = <double>[];
            final reached = <int>[];
            while (!run.done) {
              reached.add(run.reached);
              final begin = _watch.elapsed;
              run.step(Duration.zero);
              took.add((_watch.elapsed - begin).inMicroseconds / 1000);
            }
            run.dispose();
            if (fastest == null) {
              fastest = took;
              items = reached;
              hashes = [for (final page in run.pages) _hash(pageKey(page))];
              lines = [for (final page in run.pages) _hash(lineKey(page))];
            } else {
              for (var unit = 0; unit < took.length; unit++) {
                if (took[unit] < fastest[unit]) fastest[unit] = took[unit];
              }
            }
            for (final page in run.pages) {
              page.dispose();
            }
          }
          // The steps of the page source's budget: units until one
          // crosses it.
          var step = 0.0;
          var first = 0;
          for (var unit = 0; unit < fastest!.length; unit++) {
            step += fastest[unit];
            if (fastest[unit] > longestUnit) {
              longestUnit = fastest[unit];
              unitWhere = 'section $index, item ${items[unit]}';
            }
            if (step >= _budget || unit + 1 == fastest.length) {
              if (step > longest) {
                longest = step;
                where =
                    'section $index, items ${items[first]} to '
                    '${items[unit]}';
              }
              step = 0;
              first = unit + 1;
            }
          }
          sections['$index'] = hashes;
          sectionLines['$index'] = lines;
        }
        found[settingsName(settings)] = {
          'longestStepMs': longest,
          'where': ?where,
          'longestUnitMs': longestUnit,
          'unitWhere': ?unitWhere,
          'pages': sections,
          'lines': sectionLines,
        };
      }
      results[book.id] = found;
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(jsonEncode(results));
    }, timeout: Timeout.none);
  }
}

/// Admits [bytes], after it converts a Kindle file as Bookfin does.
Future<CorpusBook> _open(CorpusEntry book, Uint8List bytes) async =>
    book.format == 'azw3'
    ? CorpusBook(
        (await importMobi(
          VerifiedFile(book.file.uri, sha256.convert(bytes).toString()),
        )).publication,
      )
    : CorpusBook.open(bytes);
