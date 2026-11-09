// An on-demand benchmark of the layout steps that run on the UI isolate
// between frames (docs/plans/native-epub-reader.md, "Steps"). A step lays
// out flow items until its budget of 4 ms is spent, so no step may take much
// longer than the budget plus one ordinary paragraph. It is not part of the
// normal test run, because its limits are times on a shared machine.
//
// In the dev shell, from the repository root:
//
//   BOOKFIN_EPUB_STEPS=1 flutter test test/reader/epub/step_budget_test.dart
import 'dart:io';

import 'package:bookfin/reader/epub/dom.dart';
import 'package:bookfin/reader/epub/layout.dart';
import 'package:bookfin/reader/epub/prepare.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

final _enabled = Platform.environment['BOOKFIN_EPUB_STEPS'] == '1';

const forever = Duration(days: 1);

/// The two page settings of the corpus run.
const _settings = [
  readerPage,
  PageSettings(width: 360, height: 640, fontSize: 26, night: false),
];

final _watch = Stopwatch()..start();

/// The least of [times] measures.
Duration _fastest(Duration Function() measure, {int times = 3}) {
  var best = measure();
  for (var time = 1; time < times; time++) {
    final took = measure();
    if (took < best) best = took;
  }
  return best;
}

/// The longest step of the main run of [section], each step one flow item.
Duration _slowestStep(PreparedSection section) {
  var slowest = Duration.zero;
  final run = LayoutRun(section);
  while (!run.done) {
    final begin = _watch.elapsed;
    run.step(Duration.zero);
    final took = _watch.elapsed - begin;
    if (took > slowest) slowest = took;
  }
  for (final page in run.pages) {
    page.dispose();
  }
  run.dispose();
  return slowest;
}

String _ms(Duration duration) =>
    (duration.inMicroseconds / 1000).toStringAsFixed(1);

void main() {
  if (!_enabled) {
    test('the step budget', () {}, skip: 'set BOOKFIN_EPUB_STEPS=1 to run');
    return;
  }
  setUpAll(loadReaderFont);

  test('the layout step of a verse paragraph grows in proportion to its '
      'lines', () {
    // Song of Myself in Gutenberg's Leaves of Grass is one pre element of
    // thousands of lines. Four times the lines take about four times as
    // long when each line costs the same, and sixteen times when each line
    // costs as much as the lines before it. The limit lies between, above
    // the engine's own shaping, which grows a little faster than the lines.
    String verse(int count) => [
      for (var line = 0; line < count; line++)
        'I celebrate myself, and sing line $line',
    ].join('\n');
    for (final settings in _settings) {
      Duration step(int lines) {
        final section = prepared(
          '<pre>${verse(lines)}</pre>',
          settings: settings,
        );
        return _fastest(() => _slowestStep(section));
      }

      final short = step(1000);
      final long = step(4000);
      stdout.writeln(
        '${settings.fontSize} px: 1,000 lines ${_ms(short)} ms, '
        '4,000 lines ${_ms(long)} ms',
      );
      expect(long, lessThan(short * 8));
    }
  }, timeout: Timeout.none);

  test('no step of a long dialogue table takes much longer than its budget, '
      'and a page or a place inside it opens without the rows above it', () {
    // Gorgias in Standard Ebooks' Plato, Dialogues is one table of 1,082
    // rows of speaker and speech.
    final body =
        '<table>${[for (var row = 0; row < 1000; row++) '<tr><td>Socrates $row</td><td>${prose(2, 'Speech $row')}</td></tr>'].join()}'
        '</table>';
    const budget = Duration(milliseconds: 4);
    const row = Duration(milliseconds: 30);
    for (final settings in _settings) {
      final section = prepared(body, settings: settings);
      var slowest = Duration.zero;
      final main = LayoutRun(section);
      while (!main.done) {
        final begin = _watch.elapsed;
        main.step(budget);
        final took = _watch.elapsed - begin;
        if (took > slowest) slowest = took;
      }
      main.dispose();
      final pages = main.pages;
      final middle = pages[pages.length ~/ 2].start;
      final fromMiddle = _fastest(() {
        final begin = _watch.elapsed;
        final run = LayoutRun(section, from: middle)..step(forever, want: 1);
        final took = _watch.elapsed - begin;
        for (final page in run.pages) {
          page.dispose();
        }
        run.dispose();
        return took;
      });
      final late = section.dom.texts.firstWhere(
        (text) => text.text.contains('Speech 900 passage 2.'),
      );
      final place = EpubPlace(section.index, late.order, 0);
      final opening = _fastest(() {
        final begin = _watch.elapsed;
        final run = LayoutRun(section, from: lineStart(section, place))
          ..step(forever, want: 1);
        final took = _watch.elapsed - begin;
        for (final page in run.pages) {
          page.dispose();
        }
        run.dispose();
        return took;
      });
      for (final page in pages) {
        page.dispose();
      }
      stdout.writeln(
        '${settings.fontSize} px: slowest step ${_ms(slowest)} ms, '
        'first page from the middle ${_ms(fromMiddle)} ms, '
        'first page of a late place ${_ms(opening)} ms',
      );
      expect(slowest, lessThan(budget + row));
      expect(fromMiddle, lessThan(row));
      expect(opening, lessThan(row));
    }
  }, timeout: Timeout.none);
}
