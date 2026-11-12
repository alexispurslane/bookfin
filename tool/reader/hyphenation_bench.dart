// Tool code: an on-demand host benchmark of the hyphenation patterns, the
// old way against the new way (boo-yjq6). It is not part of Bookfin.
//
// Before boo-yjq6, each worker isolate built its pattern tables from the
// strings of hyphenation_en.dart at its first hyphenation. Now the tables
// are const data that every worker shares. It measures:
//
// - first use: the first breaks of an American and a British word in a new
//   worker, with tables built from the strings against the const tables;
// - words: the breaks of 400,000 words with each kind of table.
//
// In the dev shell, from the repository root:
//
//   dart compile exe tool/reader/hyphenation_bench.dart -o /tmp/hyphenation
//   /tmp/hyphenation
//
// It prints the median of 7 rounds of each measure.
import 'dart:isolate';

import 'package:bookfin/reader/epub/hyphenate.dart';
import 'package:bookfin/reader/epub/hyphenation_en.dart';

const _words = [
  'hyphenation', 'extraordinary', 'typesetter', 'considered', //
  'unbelievable', 'manuscript', 'university', 'throughout', 'something',
  'everywhere', 'philosophy', 'remarkable', 'continuation', 'nevertheless',
  'circumstances', 'acquaintance', 'disappointment', 'neighbourhood',
  'conversation', 'particularly',
];

/// The first breaks of [hyphenators] in a new worker, in microseconds.
Future<int> _firstUse(List<Hyphenator> Function() hyphenators) =>
    Isolate.run(() {
      final watch = Stopwatch()..start();
      for (final hyphenator in hyphenators()) {
        hyphenator.breaks('hyphenation');
      }
      return watch.elapsedMicroseconds;
    });

int _words400k(Hyphenator hyphenator) {
  final watch = Stopwatch()..start();
  for (var round = 0; round < 20000; round++) {
    for (final word in _words) {
      hyphenator.breaks(word);
    }
  }
  return watch.elapsedMicroseconds;
}

double _median(List<int> microseconds) =>
    (microseconds..sort())[microseconds.length ~/ 2] / 1000;

Future<void> main() async {
  final built = <int>[];
  final shared = <int>[];
  final builtWords = <int>[];
  final sharedWords = <int>[];
  final american = Hyphenator(
    hyphenationPatterns(enUsPatterns),
    hyphenationExceptions(enUsExceptions),
  );
  for (var round = 0; round < 7; round++) {
    built.add(
      await _firstUse(
        () => [
          Hyphenator(
            hyphenationPatterns(enUsPatterns),
            hyphenationExceptions(enUsExceptions),
          ),
          Hyphenator(
            hyphenationPatterns(enGbPatterns),
            hyphenationExceptions(enGbExceptions),
          ),
        ],
      ),
    );
    shared.add(
      await _firstUse(
        () => [
          Hyphenator.forLanguage('en-US')!,
          Hyphenator.forLanguage('en-GB')!,
        ],
      ),
    );
    builtWords.add(_words400k(american));
    sharedWords.add(_words400k(Hyphenator.forLanguage('en-US')!));
  }
  print(
    'first use in a new worker: ${_median(built)} -> ${_median(shared)} ms; '
    '400,000 words: ${_median(builtWords)} -> ${_median(sharedWords)} ms',
  );
}
