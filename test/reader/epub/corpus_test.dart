// The on-demand corpus run of the native renderer over the public-domain
// books of tool/reader/epub_corpus.json. It is not part of Bookfin's normal
// test run. docs/research/native-epub-corpus.md describes it.
//
// In the dev shell, from the repository root:
//
//   python3 -I tool/reader/fetch_epub_corpus.py
//   BOOKFIN_EPUB_CORPUS=1 flutter test test/reader/epub/corpus_test.dart
//
// Each book is one test. After each book, the run writes what it found to
// .cache/epub-corpus/results.json. To check some books only, add
// --plain-name with a book id from the list.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bookfin/reader/mobi.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'corpus/book.dart';
import 'corpus/check.dart';
import 'corpus/list.dart';
import 'corpus/support.dart';
import 'helpers.dart';

final _enabled = Platform.environment['BOOKFIN_EPUB_CORPUS'] == '1';
final _results = File('.cache/epub-corpus/results.json');

void main() {
  if (!_enabled) {
    test('the corpus run', () {}, skip: 'set BOOKFIN_EPUB_CORPUS=1 to run');
    return;
  }
  final books = corpusList();
  final reports = <String, BookReport>{};
  setUpAll(loadReaderFont);

  for (final book in books) {
    test(book.id, () async {
      final bytes = book.url == null
          ? showcaseBooks()[book.id]!
          : await _download(book);
      expect(
        sha256.convert(bytes).toString(),
        book.sha256,
        reason: '${book.id} is not the book that the list pins',
      );
      final report = await checkBook(book.id, () => _open(book, bytes));
      reports[book.id] = report;
      // The results are written after each book, so that a stopped run
      // keeps what it found.
      _write(books, reports);
      expect(report.exceptions.map((each) => each.toJson()), isEmpty);
      for (final each in report.settings) {
        expect(each.brokenPlaces, isEmpty, reason: settingsName(each.settings));
        expect(each.blankPages, isEmpty, reason: settingsName(each.settings));
        expect(each.runFailures, isEmpty, reason: settingsName(each.settings));
        expect(
          each.keptPlaceFailures,
          isEmpty,
          reason: settingsName(each.settings),
        );
      }
    }, timeout: Timeout.none);
  }

  test('most books use no feature that the renderer does not support', () {
    final supported = reports.values.where(
      (report) => report.support?.supported ?? false,
    );
    expect(supported.length, greaterThan(reports.length ~/ 2));
  });
}

void _write(List<CorpusEntry> books, Map<String, BookReport> reports) {
  _results.parent.createSync(recursive: true);
  _results.writeAsStringSync(
    const JsonEncoder.withIndent(' ').convert({
      'settings': [for (final each in corpusSettings) settingsName(each)],
      'summary': _summary(books, reports),
      'books': {
        for (final book in books)
          if (reports[book.id] case final report?)
            book.id: {
              'title': book.title,
              'source': book.source,
              'format': book.format,
              ...report.toJson(),
            },
      },
    }),
  );
}

Future<Uint8List> _download(CorpusEntry book) async {
  if (!await book.file.exists()) {
    fail(
      '${book.file.path} is missing. '
      'Run python3 -I tool/reader/fetch_epub_corpus.py in the dev shell.',
    );
  }
  return book.file.readAsBytes();
}

/// Admits [bytes], after it converts a Kindle file as Bookfin does.
Future<CorpusBook> _open(CorpusEntry book, Uint8List bytes) async =>
    book.format == 'azw3'
    ? CorpusBook(
        (await importMobi(
          book.file,
          sha256.convert(bytes).toString(),
        )).publication,
      )
    : CorpusBook.open(bytes);

/// The totals of the run over [books].
Map<String, Object> _summary(
  List<CorpusEntry> books,
  Map<String, BookReport> reports,
) => {
  'books': books.length,
  'checked': reports.length,
  'passed': reports.values.where((report) => report.passed).length,
  'exceptions': reports.values.fold<int>(
    0,
    (total, report) => total + report.exceptions.length,
  ),
  'unsupportedBooks': _featureBooks(
    reports.values,
    (support) => support.unsupported,
  ),
  'approximatedBooks': _featureBooks(
    reports.values,
    (support) => support.approximated,
  ),
  for (final (index, settings) in corpusSettings.indexed)
    settingsName(settings): _settingsSummary([
      for (final report in reports.values)
        if (report.settings.length > index) report.settings[index],
    ]),
};

/// How many of [reports] use each feature that [features] gives, most used
/// first.
Map<String, int> _featureBooks(
  Iterable<BookReport> reports,
  Map<String, Set<int>> Function(SupportReport support) features,
) {
  final found = <String, int>{};
  for (final report in reports) {
    if (report.support case final support?) {
      for (final feature in features(support).keys) {
        found[feature] = (found[feature] ?? 0) + 1;
      }
    }
  }
  return Map.fromEntries(
    found.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
  );
}

/// The totals of [found], the books' reports at one page settings value.
Map<String, Object> _settingsSummary(List<SettingsReport> found) {
  int total(int Function(SettingsReport each) of) =>
      found.fold(0, (sum, each) => sum + of(each));
  final rates = [for (final each in found) each.layoutMsPer10k]..sort();
  return {
    'pages': total((each) => each.pages),
    'pageStarts': total((each) => each.pageStarts),
    'samePage': total((each) => each.samePage),
    'sameCfi': total((each) => each.sameCfi),
    'sameQuote': total((each) => each.sameQuote),
    'brokenPlaces': total((each) => each.brokenPlaces.length),
    'blankPages': total((each) => each.blankPages.length),
    'runs': total((each) => each.runs),
    'runFailures': total((each) => each.runFailures.length),
    'keptPlaces': total((each) => each.keptPlaces),
    'keptPlaceMisses': total((each) => each.keptPlaceMisses),
    'lineStartDisagreements': total((each) => each.lineStartDisagreements),
    'mapBytes': total((each) => each.mapBytes),
    'formatThreeMapBytes': total((each) => each.formatThreeMapBytes),
    'formatTwoMapBytes': total((each) => each.formatTwoMapBytes),
    'slowItems': total((each) => each.slow.length),
    'layoutMsPer10kMedian': rates.isEmpty ? 0 : rates[rates.length ~/ 2],
    'layoutMsPer10kMax': rates.isEmpty ? 0 : rates.last,
  };
}
