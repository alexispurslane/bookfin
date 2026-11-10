// A part of a large section: a worker parses the whole section, styles it
// and builds its boxes up to the part, and makes text runs only in the
// part. The part's flow items keep the numbers that the whole section
// gives them, so its pages have their true starts, and they are the whole
// section's pages.
import 'package:bookfin/reader/epub/dom.dart';
import 'package:bookfin/reader/epub/layout.dart';
import 'package:bookfin/reader/epub/places.dart';
import 'package:bookfin/reader/epub/prepare.dart';
import 'package:flutter_test/flutter_test.dart';

import 'flow_dump.dart';
import 'helpers.dart';

const _day = Duration(days: 1);

/// [count] paragraphs of six sentences each.
String _paragraphs(int count) =>
    [for (var i = 0; i < count; i++) '<p>${prose(6, 'Part $i')}</p>'].join();

/// One paragraph's content of [count] sentences, each in an element of
/// its own, so that each is a text node of its own.
String monologue(int count) => [
  for (var i = 0; i < count; i++) '<span>${prose(1, 'Monologue $i')}</span> ',
].join();

/// The whole section of [body], and its part around the place [fraction]
/// of the way through its visible text, or the place that [find] picks,
/// with that place.
({PreparedSection whole, PreparedSection part, EpubPlace place}) _split(
  String body,
  double fraction, {
  EpubPlace? Function(DomSection dom)? find,
}) {
  final source = section(body);
  final whole = prepareSections([source], readerPage).single;
  final (:place, section: part) = preparePart(
    source,
    readerPage,
    find ?? (dom) => placeAt(dom, 0, fraction),
  );
  return (whole: whole, part: part!, place: place!);
}

/// The first [count] pages that a run of [section] from [start] cuts, as a
/// reader sees them. Fewer when the run ends or needs the whole section
/// first.
List<List<Object?>> _pagesFrom(
  PreparedSection section,
  PageStart start,
  int count,
) {
  final run = LayoutRun(section, from: start);
  while (run.pages.length < count && !run.done && !run.starved) {
    run.step(_day, want: count - run.pages.length);
  }
  final pages = run.pages.take(count).toList();
  final shown = keys(pages);
  for (final page in run.pages) {
    page.dispose();
  }
  run.dispose();
  return shown;
}

void main() {
  setUpAll(loadReaderFont);

  test('a part numbers its flow items as the whole section does, and makes '
      'text runs only around its place', () {
    final (:whole, :part, place: _) = _split(_paragraphs(400), .5);

    expect(part.whole, isFalse);
    expect(part.firstPrepared, greaterThan(0));
    expect(part.reachesEnd, isFalse);
    expect(part.flow.length, lessThan(whole.flow.length));
    for (var index = 0; index < part.flow.length; index++) {
      final item = part.flow[index];
      if (item is SkippedItem) {
        expect(index, lessThan(part.firstPrepared));
        continue;
      }
      expect(
        dumpItem(item, part.styles),
        dumpItem(whole.flow[index], whole.styles),
        reason: 'flow item $index',
      );
    }
    final paragraphs = part.flow.whereType<ParagraphItem>().length;
    expect(
      paragraphs,
      lessThan(whole.flow.whereType<ParagraphItem>().length ~/ 4),
    );
  });

  for (final (name, fraction) in [('the middle', .5), ('near the end', .97)]) {
    test('a page from a part at a place in $name has the same start and '
        'content as the page from the whole section', () {
      final (:whole, :part, :place) = _split(_paragraphs(400), fraction);

      final line = lineStart(part, place);

      expect(line, lineStart(whole, place));
      final fromPart = _pagesFrom(part, line, 2);
      expect(fromPart, hasLength(2));
      expect(fromPart, _pagesFrom(whole, line, 2));
    });
  }

  test('a run of a part stops where the part ends and needs the whole '
      'section, and never cuts the section\'s last page', () {
    final (:whole, :part, :place) = _split(_paragraphs(400), .5);
    final line = lineStart(part, place);
    final run = LayoutRun(part, from: line);

    while (!run.done && !run.starved) {
      run.step(_day);
    }

    expect(run.starved, isTrue);
    expect(run.done, isFalse);
    expect(run.pages, isNotEmpty);
    expect(run.pages.any((page) => page.last), isFalse);
    expect(keys(run.pages), _pagesFrom(whole, line, run.pages.length));
    for (final page in run.pages) {
      page.dispose();
    }
    run.dispose();
  });

  test('a part near the section end goes on to it, and cuts the same last '
      'page as the whole section', () {
    final (:whole, :part, :place) = _split(_paragraphs(400), .995);
    final line = lineStart(part, place);

    expect(part.reachesEnd, isTrue);
    final fromPart = _pagesFrom(part, line, 100);
    expect(fromPart.last[6], isTrue, reason: 'the last page is the last');
    expect(fromPart, _pagesFrom(whole, line, 100));
  });

  test('a line search in a part for a place before or after the part finds '
      'nothing, and needs the whole section', () {
    final (:whole, :part, place: _) = _split(_paragraphs(400), .5);
    for (final fraction in [.05, .95]) {
      final far = placeAt(whole.dom, 0, fraction);
      final search = LineSearch(part, far)..step(_day);

      expect(search.found, isNull, reason: 'at $fraction');
      expect(search.starved, isTrue, reason: 'at $fraction');
    }
  });

  test('a table that starts before the part and ends in it comes whole, '
      'and its page is the whole section\'s page', () {
    // About 12,000 visible characters, with the place 10,000 in.
    final rows = [
      for (var i = 0; i < 60; i++)
        '<tr><td>Speaker $i</td><td>${prose(2, 'Speech $i')}</td></tr>',
    ].join();
    final (:whole, :part, :place) = _split(
      '${_paragraphs(100)}<table>$rows</table>${_paragraphs(100)}',
      0,
      find: (dom) => EpubPlace(
        0,
        dom.texts.firstWhere((text) => text.text.startsWith('Speech 50')).order,
        0,
      ),
    );
    final line = lineStart(part, place);

    final table = part.flow.indexWhere((item) => item is TableItem);
    expect(table, greaterThan(0));
    expect(part.firstPrepared, lessThan(table));
    expect(
      dumpItem(part.flow[table], part.styles),
      dumpItem(whole.flow[table], whole.styles),
    );
    expect(line, lineStart(whole, place));
    expect(_pagesFrom(part, line, 2), _pagesFrom(whole, line, 2));
  });

  for (final (name, block) in [
    ('paragraph', '<p>${monologue(600)}</p>'),
    (
      'table',
      '<table>${[for (var i = 0; i < 300; i++) '<tr><td>${prose(2, 'Row $i')}</td></tr>'].join()}</table>',
    ),
  ]) {
    test('a part holds the whole of a $name longer than the part that holds '
        'its place, and its pages are the whole section\'s pages', () {
      final (:whole, :part, :place) = _split(
        '${_paragraphs(20)}$block${_paragraphs(200)}',
        .2,
      );
      final line = lineStart(part, place);

      expect(part.whole, isFalse);
      expect(line, lineStart(whole, place));
      expect(_pagesFrom(part, line, 2), _pagesFrom(whole, line, 2));
    });
  }

  test('a place inside a long block of another kind, longer than the part, '
      'gets the whole section, prepared from the same parse', () {
    final (:whole, :part, place: _) = _split(
      '${_paragraphs(20)}<div>${monologue(600)}</div>${_paragraphs(20)}',
      .5,
    );

    expect(part.whole, isTrue);
    expect(dumpPrepared(part), dumpPrepared(whole));
  });

  test('a place in a section that a part would hold whole gets the whole '
      'section', () {
    final (:whole, :part, place: _) = _split(_paragraphs(20), .5);

    expect(part.whole, isTrue);
    expect(dumpPrepared(part), dumpPrepared(whole));
  });

  test('a paragraph of one text node longer than the part comes whole, '
      'because a part ends after the text node that holds its last '
      'character', () {
    final (:whole, :part, :place) = _split(
      '${_paragraphs(20)}<p>${prose(600, 'Monologue')}</p>${_paragraphs(20)}',
      .5,
    );
    final line = lineStart(part, place);

    expect(line, lineStart(whole, place));
    expect(_pagesFrom(part, line, 2), _pagesFrom(whole, line, 2));
  });

  test('a find that picks no place gives no place and no part', () {
    final result = preparePart(
      section(_paragraphs(10)),
      readerPage,
      (_) => null,
    );

    expect(result.place, isNull);
    expect(result.section, isNull);
  });
}
