// The trial renderer on real books: the support check, the CFI round trip
// and the host benchmark. The books are public-domain EPUBs that are not
// committed (see docs/research/native-epub.md). Run with
// BOOKFIN_EPUB_TRIAL=1; the test writes its results to
// .cache/epub-trial/results.
import 'dart:convert';
import 'dart:io';

import 'package:bookfin/reader/native_epub/benchmark.dart';
import 'package:bookfin/reader/native_epub/book.dart';
import 'package:bookfin/reader/native_epub/cfi.dart';
import 'package:bookfin/reader/native_epub/layout.dart';
import 'package:bookfin/reader/native_epub/support.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/showcase_media.dart' as media;
import 'helpers.dart';

final _enabled = Platform.environment['BOOKFIN_EPUB_TRIAL'] == '1';
final _results = Directory('.cache/epub-trial/results');

void _write(String name, Object value) {
  _results.createSync(recursive: true);
  File('${_results.path}/$name.json')
      .writeAsStringSync(const JsonEncoder.withIndent(' ').convert(value));
}

/// Writes the showcase fixture's made-up EPUBs beside the downloaded books.
void _writeShowcase() {
  for (final (id, title, chapters) in [
    ('frost', 'First Frost', media.firstFrost),
    ('salt', 'Salt and Lantern', media.saltAndLantern),
    ('winter', 'The Winter Ledger', media.winterLedger),
  ]) {
    File('.cache/epub-trial/books/showcase-$id.epub')
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
      const theme = PageTheme();
      for (final file in trialBooks()) {
        final book = TrialBook.open(file.readAsBytesSync());
        var pages = 0;
        var samePage = 0;
        var sameString = 0;
        var sameQuote = 0;
        final failures = <String>[];
        for (var index = 0; index < book.sections; index++) {
          final prepared = await prepareSection(book.section(index), theme);
          final chapter = layoutSection(prepared, theme);
          final dom = prepared.dom;
          for (var page = 0; page < chapter.pages.length; page++) {
            final start = chapter.pages[page].start;
            if (start == null) continue;
            pages++;
            final place = wordStart(start);
            final cfi = cfiOf(book.spine(index), place);
            final back = positionOf(dom, cfi);
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
            if (cfiOf(book.spine(index), back) == cfi) sameString++;
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
    'the host benchmark lays out and draws every book',
    () async {
      final report = <Object>[];
      for (final file in trialBooks()) {
        final book = TrialBook.open(file.readAsBytesSync());
        final timing = await benchmarkBook(
          bookName(file),
          book,
          const PageTheme(),
        );
        final retained = await retainedMemory(book, const PageTheme());
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
