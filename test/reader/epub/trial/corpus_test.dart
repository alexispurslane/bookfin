// Tool code: the on-demand trial run of the renderer on real books. It is
// not part of Bookfin's normal test run.
//
// It runs the support check, the CFI round trip and the host benchmark. The
// books are public-domain EPUBs that are not committed (see
// docs/research/native-epub.md). Run with BOOKFIN_EPUB_TRIAL=1; the test
// writes its results to .cache/epub-trial/results.
import 'dart:convert';
import 'dart:io';

import 'package:bookfin/reader/epub/layout.dart';
import 'package:bookfin/reader/epub/places.dart';
import 'package:bookfin/reader/epub/prepare.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../tool/showcase_media.dart' as media;
import '../helpers.dart';
import 'benchmark.dart';
import 'book.dart';
import 'support.dart';

final _enabled = Platform.environment['BOOKFIN_EPUB_TRIAL'] == '1';
final _results = Directory('.cache/epub-trial/results');

void _write(String name, Object value) {
  _results.createSync(recursive: true);
  File('${_results.path}/$name.json')
      .writeAsStringSync(const JsonEncoder.withIndent(' ').convert(value));
}

/// Writes the showcase fixture's made-up EPUBs beside the downloaded books.
void _writeShowcase() {
  final books = Directory('.cache/epub-trial/books')
    ..createSync(recursive: true);
  for (final (id, title, chapters) in [
    ('frost', 'First Frost', media.firstFrost),
    ('salt', 'Salt and Lantern', media.saltAndLantern),
    ('winter', 'The Winter Ledger', media.winterLedger),
  ]) {
    File('${books.path}/showcase-$id.epub')
        .writeAsBytesSync(media.epub(id, title, 'Bookfin Showcase', chapters));
  }
}

void main() {
  setUpAll(() async {
    await loadReaderFont();
    if (_enabled) _writeShowcase();
  });

  test('the support check passes most prose books', () {
    final report = <String, Object>{};
    for (final file in trialBooks()) {
      final bytes = file.readAsBytesSync();
      for (final original in [false, true]) {
        final book = TrialBook.open(bytes, originalCss: original);
        final support = checkSupport(book);
        report['${bookName(file)}${original ? '' : ' (admitted CSS)'}'] = {
          'supported': support.supported,
          'sections': support.sections,
          'supportedSections': support.supportedSections,
          'unsupported': {
            for (final MapEntry(:key, :value) in support.unsupported.entries)
              key: value.toList()..sort(),
          },
          'approximated': {
            for (final MapEntry(:key, :value) in support.approximated.entries)
              key: value.length,
          },
        };
      }
    }
    _write('support', report);
    final passed = report.values
        .where((entry) => (entry as Map)['supported'] == true)
        .length;
    expect(passed, greaterThan(report.length ~/ 2));
  }, skip: !_enabled);

  test(
    'every page start of every book survives the CFI round trip',
    () async {
      final report = <String, Object>{};
      for (final file in trialBooks()) {
        final book = TrialBook.open(file.readAsBytesSync());
        var pages = 0;
        var samePage = 0;
        var sameString = 0;
        var sameQuote = 0;
        final failures = <String>[];
        for (var index = 0; index < book.sections; index++) {
          final prepared = prepareSections([
            book.source(index),
          ], readerPage).single;
          final chapter = layoutSection(prepared);
          final dom = prepared.dom;
          for (var page = 0; page < chapter.pages.length; page++) {
            final start = chapter.pages[page].startPlace;
            if (start == null) continue;
            pages++;
            final place = wordStart(dom, start);
            final cfi = cfiOf(book.spine(index), dom, place);
            final back = placeOf(dom, index, cfi);
            if (spineIndexOf(cfi) != index || back == null) {
              failures.add(cfi);
              continue;
            }
            final found = chapter.pageAt(back);
            if (found == page) {
              samePage++;
            } else {
              failures.add('$cfi: page $page opens page $found');
            }
            if (cfiOf(book.spine(index), dom, back) == cfi) sameString++;
            if (quoteAt(dom, back) == quoteAt(dom, place)) sameQuote++;
          }
        }
        report[bookName(file)] = {
          'pages': pages,
          'samePage': samePage,
          'sameCfi': sameString,
          'sameQuote': sameQuote,
          'failures': failures,
        };
      }
      _write('cfi-round-trip', report);
      for (final MapEntry(:key, :value) in report.entries) {
        expect((value as Map)['failures'], isEmpty, reason: key);
      }
    },
    skip: !_enabled,
    timeout: const Timeout(Duration(minutes: 10)),
  );

  test(
    'a run from every page start of every book cuts the same pages',
    () {
      // Each run from a page start is compared over the pages that it cuts
      // in [compared] pages' worth of steps, so that the 430,000-character
      // Keats section stays within minutes.
      const compared = 5;
      final report = <String, Object>{};
      for (final file in trialBooks()) {
        final book = TrialBook.open(file.readAsBytesSync());
        var starts = 0;
        var pagesCompared = 0;
        final failures = <String>[];
        for (var index = 0; index < book.sections; index++) {
          final section = prepareSections([
            book.source(index),
          ], readerPage).single;
          final main = layoutSection(section).pages;
          // The main run stopped after every item cuts the same pages.
          final stepped = LayoutRun(section);
          while (!stepped.done) {
            stepped.step(Duration.zero);
          }
          if (!_same(keys(stepped.pages), keys(main))) {
            failures.add('section $index: stepped run');
          }
          for (final page in stepped.pages) {
            page.dispose();
          }
          for (var page = 1; page < main.length; page++) {
            final run = LayoutRun(section, from: main[page].start)
              ..step(const Duration(days: 1), want: compared);
            starts++;
            pagesCompared += run.pages.length;
            final expected = main.skip(page).take(run.pages.length);
            if (!_same(keys(run.pages), keys(expected))) {
              failures.add('section $index: page $page');
            }
            for (final laid in run.pages) {
              laid.dispose();
            }
            run.dispose();
          }
          for (final page in main) {
            page.dispose();
          }
        }
        report[bookName(file)] = {
          'pageStarts': starts,
          'pagesCompared': pagesCompared,
          'failures': failures,
        };
      }
      _write('page-starts', report);
      for (final MapEntry(:key, :value) in report.entries) {
        expect((value as Map)['failures'], isEmpty, reason: key);
      }
    },
    skip: !_enabled,
    timeout: const Timeout(Duration(minutes: 20)),
  );

  test(
    'the host benchmark lays out and draws every book',
    () async {
      final report = <Object>[];
      for (final file in trialBooks()) {
        final book = TrialBook.open(file.readAsBytesSync());
        final timing = await benchmarkBook(bookName(file), book, readerPage);
        final retained = await retainedMemory(book, readerPage);
        report.add({
          ...timing.toJson(),
          'retainedSections': retained.sections,
          'retainedCharacters': retained.characters,
          'retainedMiB': retained.bytes / 1048576,
        });
      }
      _write('host-benchmark', report);
    },
    skip: !_enabled,
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

bool _same(List<List<Object?>> a, List<List<Object?>> b) =>
    equals(b).matches(a, {});
