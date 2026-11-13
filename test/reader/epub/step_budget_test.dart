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

  test('the layout of a verse paragraph grows in proportion to its lines', () {
    // Song of Myself in Gutenberg's Leaves of Grass is one pre element of
    // thousands of lines. Four times the lines take about four times as
    // long when each line costs the same, and sixteen times when each line
    // costs as much as the lines before it. The limit lies between, above
    // the engine's own shaping, which grows a little faster than the lines.
    // The run lays the paragraph out in segments, one step each, so the
    // whole run counts.
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
        return _fastest(() {
          final begin = _watch.elapsed;
          final run = LayoutRun(section)..step(forever);
          final took = _watch.elapsed - begin;
          for (final page in run.pages) {
            page.dispose();
          }
          run.dispose();
          return took;
        });
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

  test('no layout step of a long verse paragraph takes much longer than its '
      'budget, and a page or a place deep inside it opens in steps', () {
    // Song of Myself in Gutenberg's Leaves of Grass is one pre element of
    // 91,000 characters. A step stops between its segments of hard-broken
    // lines, and a search for a place counts the lines of the segments
    // before it in steps.
    String verse(int count) => [
      for (var line = 0; line < count; line++)
        'I celebrate myself, and sing myself, line $line',
    ].join('\n');
    const budget = Duration(milliseconds: 4);
    const segment = Duration(milliseconds: 8);
    final body = '<pre>${verse(2000)}</pre>';
    for (final settings in _settings) {
      final section = prepared(body, settings: settings);
      final measurements = LayoutMeasurements();
      late List<LaidPage> pages;
      final slowest = _fastest(() {
        var slowest = Duration.zero;
        final main = LayoutRun(section, measurements: measurements);
        while (!main.done) {
          final begin = _watch.elapsed;
          main.step(budget);
          final took = _watch.elapsed - begin;
          if (took > slowest) slowest = took;
        }
        main.dispose();
        pages = main.pages;
        return slowest;
      });
      final middle = pages[pages.length * 3 ~/ 4].start;
      final fromMiddle = _fastest(() {
        final begin = _watch.elapsed;
        final run = LayoutRun(section, measurements: measurements, from: middle)
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
      // Sections that no run laid out yet.
      late LineSearch search;
      late PreparedSection fresh;
      late LayoutMeasurements freshMeasurements;
      final slowestSearch = _fastest(() {
        fresh = prepared(body, settings: settings);
        freshMeasurements = LayoutMeasurements();
        final text = fresh.dom.texts.single;
        search = LineSearch(
          fresh,
          EpubPlace(fresh.index, text.order, text.text.indexOf('line 1900')),
          measurements: freshMeasurements,
        );
        var slowest = Duration.zero;
        while (search.found == null) {
          final begin = _watch.elapsed;
          search.step(budget);
          final took = _watch.elapsed - begin;
          if (took > slowest) slowest = took;
        }
        return slowest;
      });
      final begin = _watch.elapsed;
      final opened = LayoutRun(
        fresh,
        from: search.found,
        measurements: freshMeasurements,
      )..step(forever, want: 1);
      final opening = _watch.elapsed - begin;
      for (final page in opened.pages) {
        page.dispose();
      }
      opened.dispose();
      stdout.writeln(
        '${settings.fontSize} px: slowest step of 2,000 lines of verse '
        '${_ms(slowest)} ms, first page from three quarters in '
        '${_ms(fromMiddle)} ms, slowest search step for a late place '
        '${_ms(slowestSearch)} ms, its first page ${_ms(opening)} ms',
      );
      expect(slowest, lessThan(budget + segment));
      expect(fromMiddle, lessThan(segment));
      expect(slowestSearch, lessThan(budget + segment));
      expect(opening, lessThan(segment));
    }
  }, timeout: Timeout.none);

  test('no layout step of a long paragraph without hard breaks takes much '
      'longer than its budget', () {
    // Each section of the index of Gutenberg's Roget's Thesaurus is one
    // justified paragraph of up to 54,000 characters in 6,000 style runs,
    // with no hard break. A step stops between its segments of whole
    // lines. Each measure lays out a text of its own, so that the text
    // engine's cache of shaped paragraphs serves none of it.
    var serial = 0;
    PreparedSection index(PageSettings settings) {
      final run = ++serial;
      return prepared(
        '<p>${[for (var entry = 0; entry < 3000; entry++) '<i>Entry $run.$entry</i> ${100 + entry}, ${400 + entry};'].join(' ')}</p>',
        css: 'p{text-align:justify}',
        settings: settings,
      );
    }

    const budget = Duration(milliseconds: 4);
    const segment = Duration(milliseconds: 4);
    for (final settings in _settings) {
      var characters = 0;
      final slowest = _fastest(() {
        final section = index(settings);
        characters = section.dom.visibleLength;
        var slowest = Duration.zero;
        final run = LayoutRun(section);
        while (!run.done) {
          final begin = _watch.elapsed;
          run.step(budget);
          final took = _watch.elapsed - begin;
          if (took > slowest) slowest = took;
        }
        for (final page in run.pages) {
          page.dispose();
        }
        run.dispose();
        return slowest;
      });
      stdout.writeln(
        '${settings.fontSize} px: slowest step of a paragraph of '
        '$characters characters in 6,000 runs '
        '${_ms(slowest)} ms',
      );
      expect(slowest, lessThan(budget + segment));
    }
  }, timeout: Timeout.none);

  test('no step of a table of tall rows takes much longer than its budget', () {
    // Roget's Thesaurus has table rows of about 9,700 characters in 10 to
    // 16 paragraphs, and Plato's dialogues rows of up to 27 paragraphs. A
    // step stops between the paragraphs of a row's cells.
    final body =
        '<table>${[
          for (var row = 0; row < 30; row++) '<tr><td>Speaker $row</td><td>${[for (var i = 0; i < 16; i++) '<p>${prose(8, 'Speech $row part $i')}</p>'].join()}</td></tr>',
        ].join()}'
        '</table>';
    const budget = Duration(milliseconds: 4);
    const paragraph = Duration(milliseconds: 4);
    for (final settings in _settings) {
      final section = prepared(body, settings: settings);
      final slowest = _fastest(() {
        var slowest = Duration.zero;
        final run = LayoutRun(section);
        while (!run.done) {
          final begin = _watch.elapsed;
          run.step(budget);
          final took = _watch.elapsed - begin;
          if (took > slowest) slowest = took;
        }
        for (final page in run.pages) {
          page.dispose();
        }
        run.dispose();
        return slowest;
      });
      stdout.writeln(
        '${settings.fontSize} px: slowest step of 30 rows of 10,000 '
        'characters in 16 paragraphs '
        '${_ms(slowest)} ms',
      );
      expect(slowest, lessThan(budget + paragraph));
    }
  }, timeout: Timeout.none);

  test('the layout step of a long hyphenated paragraph takes a few times one '
      'layout of it', () {
    // Darcy's letter in Standard Ebooks' Pride and Prejudice is one
    // justified paragraph of 14,920 characters with 841 soft hyphens. Each
    // hyphen that does not fit in its line becomes a word joiner, and its
    // line breaks again. The text engine keeps the paragraphs that it shaped
    // and serves the same text and styles again from that cache, so each
    // measure lays out a text of its own.
    var serial = 0;
    String words() {
      serial++;
      return [
        for (var copy = 0; copy < 70; copy++)
          'The extraordinary typesetter $serial-$copy considered the '
              'unbelievable hyphenation of characteristically '
              'incomprehensible representations, which nevertheless '
              'accommodated the administrative responsibilities of '
              'international communication.',
      ].join(' ');
    }

    for (final settings in _settings) {
      Duration step(String hyphens) => _fastest(
        () => _slowestStep(
          prepared(
            '<div lang="en"><p>${words()}</p></div>',
            css: 'p{hyphens:$hyphens;text-align:justify}',
            settings: settings,
          ),
        ),
      );

      final plain = step('manual');
      final hyphenated = step('auto');
      stdout.writeln(
        '${settings.fontSize} px: without hyphens ${_ms(plain)} ms, '
        'with hyphens ${_ms(hyphenated)} ms',
      );
      // A unit of work is a segment of the paragraph. With hyphens it lays
      // out about 3.3 times its code units, and measures the lines that end
      // near a soft hyphen alone and with the hyphen (tb-o242). When each
      // word joiner laid out the whole paragraph again, it took more than
      // 100 times as long.
      expect(hyphenated, lessThan(plain * 6));
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
      final measurements = LayoutMeasurements();
      late List<LaidPage> pages;
      final slowest = _fastest(() {
        var slowest = Duration.zero;
        final main = LayoutRun(section, measurements: measurements);
        while (!main.done) {
          final begin = _watch.elapsed;
          main.step(budget);
          final took = _watch.elapsed - begin;
          if (took > slowest) slowest = took;
        }
        main.dispose();
        pages = main.pages;
        return slowest;
      });
      final middle = pages[pages.length ~/ 2].start;
      final fromMiddle = _fastest(() {
        final begin = _watch.elapsed;
        final run = LayoutRun(section, measurements: measurements, from: middle)
          ..step(forever, want: 1);
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
        final run = LayoutRun(
          section,
          measurements: measurements,
          from: lineStart(section, place, measurements: measurements),
        )..step(forever, want: 1);
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
