// An on-demand host benchmark of a jump deep into a large section: the time
// from a new page source to the anchored page of a place, by two routes.
// The whole route asks for the prepared section, finds the place in its
// DOM and asks for the page, as the pager did before t7-49gt. The part
// route asks the page source to find the place (PageSource.findPlace),
// which prepares a part of a large section beside the whole section. It is
// not part of Bookfin's normal test run, because its times come from a
// shared machine.
//
// In the dev shell, from the repository root, with the books in
// .cache/epub-corpus/books (see corpus_test.dart):
//
//   BOOKFIN_EPUB_PART_BENCHMARK=1 flutter test \
//     test/reader/epub/part_open_benchmark_test.dart
//
// The routes alternate in each round, so that the load of the shared
// machine affects both in the same way. It prints one line per section and
// place: the median of the rounds of each route in milliseconds, and their
// ratio. It also makes sure that both routes give the same page.
import 'dart:io';

import 'package:bookfin/reader/epub/dom.dart';
import 'package:bookfin/reader/epub/page_source.dart';
import 'package:bookfin/reader/epub/places.dart';
import 'package:bookfin/reader/epub/publication.dart';
import 'package:flutter_test/flutter_test.dart';

import 'corpus/book.dart';
import 'corpus/list.dart';
import 'helpers.dart';
import 'page_source_test.dart' show TestScheduler;

/// The sections, by book id and spine index, that the benchmark jumps into.
/// The list can name others with BOOKFIN_EPUB_PART_SECTIONS, as
/// `book:index,book:index`.
const _sections = [
  ('se-poetry', 2),
  ('se-dialogues', 30),
  ('se-van-dyke-poetry', 2),
];

const _places = [.5, .97];
const _rounds = 3;

/// Finds the place [fraction] of the way through the text of section
/// [index]. Static, so that a worker can run it.
EpubPlace? Function(DomSection dom) _progressIn(int index, double fraction) =>
    (dom) => placeAt(dom, index, fraction);

void main() {
  final on = Platform.environment['BOOKFIN_EPUB_PART_BENCHMARK'] == '1';
  if (!on) {
    test(
      'the part open benchmark',
      () {},
      skip: 'set BOOKFIN_EPUB_PART_BENCHMARK=1 to run',
    );
    return;
  }
  setUpAll(loadReaderFont);
  final named = Platform.environment['BOOKFIN_EPUB_PART_SECTIONS'];
  final sections = named == null
      ? _sections
      : [
          for (final entry in named.split(','))
            (entry.split(':')[0], int.parse(entry.split(':')[1])),
        ];
  final books = {for (final book in corpusList()) book.id: book};

  for (final (id, index) in sections) {
    test('$id $index', () async {
      final publication = CorpusBook.open(await books[id]!.file.readAsBytes())
          .publication;
      final bytes = publication.textFiles[publication.spine[index]]!.length;
      for (final fraction in _places) {
        final find = _progressIn(index, fraction);
        final times = {'whole': <double>[], 'part': <double>[]};
        final shown = <String, List<Object?>>{};
        for (var round = 0; round < _rounds; round++) {
          final order = round.isEven ? ['whole', 'part'] : ['part', 'whole'];
          for (final route in order) {
            final (ms, key) = await _open(publication, index, find, route);
            times[route]!.add(ms);
            shown[route] ??= key;
          }
        }
        expect(shown['part'], shown['whole'], reason: '$id $index $fraction');
        final whole = _median(times['whole']!);
        final part = _median(times['part']!);
        // ignore: avoid_print
        print(
          'PART_BENCHMARK $id $index ${bytes ~/ 1024} KiB at $fraction: '
          'whole ${whole.toStringAsFixed(1)} ms, '
          'part ${part.toStringAsFixed(1)} ms, '
          'part/whole ${(part / whole).toStringAsFixed(2)} '
          '(whole ${times['whole']}, part ${times['part']})',
        );
      }
    }, timeout: Timeout.none);
  }
}

/// The time in milliseconds from a new page source to the anchored page of
/// the place that [find] picks in section [index], by [route], and the
/// page as a reader sees it.
Future<(double, List<Object?>)> _open(
  Publication publication,
  int index,
  EpubPlace? Function(DomSection dom) find,
  String route,
) async {
  final scheduler = TestScheduler();
  final source = PageSource(publication, schedule: scheduler.schedule)
    ..settings = readerPage;
  try {
    final watch = Stopwatch()..start();
    final place = route == 'whole'
        ? find((await scheduler.until(source.section(index))).dom)
        : await scheduler.until(source.findPlace(index, find));
    final page = await scheduler.until(
      source.pageAt(place!, anchored: true, urgent: true),
    );
    final ms = watch.elapsedMicroseconds / 1000;
    final key = pageKey(page);
    // The whole section's prepare ends before the next open.
    await scheduler.until(source.section(index));
    return (ms, key);
  } finally {
    source.dispose();
  }
}

double _median(List<double> values) {
  final sorted = [...values]..sort();
  return sorted[sorted.length ~/ 2];
}
