// A section's measures that a run from a page start inside a flow item
// needs first, kept from an earlier layout of the section: the narrowest
// and widest content width of each table cell (t5-s1vy), and the segments
// of each long paragraph and the lines before each one (t5-lfsm). With
// them, a run from a kept start inside a table cuts its pages without the
// measure of the whole table, and a run from a kept start inside a long
// paragraph without the layout of the paragraph's earlier segments. A run
// that finds a kept measure again checks it.
import 'dart:typed_data';

import 'package:bookfin/reader/epub/layout.dart';
import 'package:bookfin/reader/epub/prepare.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// A section of a few paragraphs, then a table of [rows] rows whose second
/// cells hold one to three sentences, then a paragraph.
String _tableSection(int rows) => [
  '<p>${prose(2, 'Before')}</p>',
  '<table>',
  for (var i = 0; i < rows; i++)
    '<tr><td>Row $i</td><td>${prose(i % 3 + 1, 'Cell $i')}</td></tr>',
  '</table>',
  '<p>${prose(2, 'After')}</p>',
].join('\n');

int _tableIndex(PreparedSection section) =>
    section.flow.indexWhere((item) => item is TableItem);

/// A section of a paragraph, then a paragraph of 200 sentences, of about
/// 19,000 code units, then a paragraph.
String _paragraphSection() => [
  '<p>${prose(2, 'Before')}</p>',
  '<p>${prose(200, 'Long')}</p>',
  '<p>${prose(2, 'After')}</p>',
].join('\n');

/// The code units of [paragraph]'s text.
int _length(ParagraphItem paragraph) => paragraph.text.runs
    .whereType<TextRun>()
    .fold(0, (sum, run) => sum + run.text.length);

/// The index of the longest paragraph of [section].
int _longest(PreparedSection section) {
  var best = -1;
  for (final (index, item) in section.flow.indexed) {
    if (item is ParagraphItem &&
        (best < 0 ||
            _length(item) > _length(section.flow[best] as ParagraphItem))) {
      best = index;
    }
  }
  return best;
}

int _cellCount(TableItem table) =>
    table.rows.fold(0, (count, row) => count + row.length);

void main() {
  setUpAll(loadReaderFont);

  group('kept table widths', () {
    late ChapterLayout chapter;
    late int table;

    setUp(() async {
      chapter = await lay(_tableSection(80));
      table = _tableIndex(chapter.section);
    });
    tearDown(() => chapter.dispose());

    /// The index of a true page that starts inside the table, past its
    /// middle.
    int pageInTable() => chapter.pages.lastIndexWhere(
      (page) =>
          page.start.item == table &&
          page.start.line >
              (chapter.section.flow[table] as TableItem).rows.length ~/ 2,
    );

    test('a run from a kept start inside a table cuts the same pages with '
        'kept widths as with measured ones', () {
      final measures = measuresOf(chapter.section);
      final fresh = prepared(_tableSection(80));
      expect(reuseMeasures(fresh, measures), isTrue);
      final at = pageInTable();

      final run = LayoutRun(fresh, from: chapter.pages[at].start)
        ..step(const Duration(days: 1), want: 3);
      addTearDown(() {
        for (final page in run.pages) {
          page.dispose();
        }
        run.dispose();
      });

      expect(keys(run.pages), keys(chapter.pages.skip(at).take(3)));
      expect(run.contradicted, isFalse);
    });

    test('a jump into the middle of a kept table does not measure the whole '
        'table', () {
      final fresh = prepared(_tableSection(80));
      reuseMeasures(fresh, measuresOf(chapter.section));
      final start = chapter.pages[pageInTable()].start;
      final before = LayoutRun.measuredCells;

      final run = LayoutRun(fresh, from: start)
        ..step(const Duration(days: 1), want: 1);
      addTearDown(() {
        for (final page in run.pages) {
          page.dispose();
        }
        run.dispose();
      });

      // The run checks the kept widths of the rows that it lays out, and
      // measures no other row.
      final rows = run.next.item == table
          ? run.next.line - start.line + 1
          : (fresh.flow[table] as TableItem).rows.length - start.line;
      expect(LayoutRun.measuredCells - before, lessThanOrEqualTo(rows * 2));
      expect(
        LayoutRun.measuredCells - before,
        lessThan(_cellCount(fresh.flow[table] as TableItem)),
      );
    });

    test('a run that lays out a row whose kept width disagrees with a fresh '
        'one contradicts the kept measures', () {
      final kept = measuresOf(chapter.section).tables[table]!;
      final start = chapter.pages[pageInTable()].start;
      // The narrowest width of the first cell of the page's first row, one
      // pixel wider. Each row has two cells of two widths each.
      final wrong = Float64List.fromList(kept)..[start.line * 4] += 1;
      final fresh = prepared(_tableSection(80));
      reuseMeasures(fresh, SectionMeasures(tables: {table: wrong}));

      final run = LayoutRun(fresh, from: start)
        ..step(const Duration(days: 1), want: 1);
      addTearDown(() {
        for (final page in run.pages) {
          page.dispose();
        }
        run.dispose();
      });

      expect(run.contradicted, isTrue);
    });

    test('kept widths that do not fit the section are refused', () {
      final kept = measuresOf(chapter.section).tables[table]!;

      expect(
        reuseMeasures(
          prepared(_tableSection(80)),
          SectionMeasures(tables: {table: Float64List.sublistView(kept, 4)}),
        ),
        isFalse,
      );
      expect(
        reuseMeasures(
          prepared(_tableSection(80)),
          SectionMeasures(tables: {table - 1: kept}),
        ),
        isFalse,
      );
    });

    test('the measures of a laid out section hold the widths of each table '
        'cell', () {
      final widths = measuresOf(chapter.section).tables[table];

      expect(
        widths?.length,
        _cellCount(chapter.section.flow[table] as TableItem) * 2,
      );
    });
  });

  group('kept segments of a long paragraph', () {
    late ChapterLayout chapter;
    late int long;

    setUp(() async {
      chapter = await lay(_paragraphSection());
      long = _longest(chapter.section);
    });
    tearDown(() => chapter.dispose());

    /// The index of a true page that starts inside the long paragraph, in
    /// its last quarter but not on its last page.
    int pageInParagraph() {
      final inside = [
        for (final (index, page) in chapter.pages.indexed)
          if (page.start.item == long && page.start.line > 0) index,
      ];
      return inside[inside.length * 3 ~/ 4];
    }

    List<LaidPage> runFrom(PreparedSection section, PageStart start, int want) {
      final run = LayoutRun(section, from: start)
        ..step(const Duration(days: 1), want: want);
      addTearDown(() {
        for (final page in run.pages) {
          page.dispose();
        }
        run.dispose();
      });
      expect(run.contradicted, isFalse);
      return run.pages;
    }

    test('a run from a kept start inside a long paragraph cuts the same '
        'pages with kept line counts as with counted ones', () {
      final fresh = prepared(_paragraphSection());
      expect(reuseMeasures(fresh, measuresOf(chapter.section)), isTrue);
      final at = pageInParagraph();

      final pages = runFrom(fresh, chapter.pages[at].start, 3);

      expect(keys(pages), keys(chapter.pages.skip(at).take(3)));
    });

    test("a jump into the middle of a kept long paragraph does not count "
        "its earlier segments' lines", () {
      final fresh = prepared(_paragraphSection());
      reuseMeasures(fresh, measuresOf(chapter.section));
      final length = _length(fresh.flow[long] as ParagraphItem);
      final before = LayoutRun.laidOutUnits;

      runFrom(fresh, chapter.pages[pageInParagraph()].start, 1);

      expect(LayoutRun.laidOutUnits - before, lessThan(length ~/ 4));
    });

    test('a run that lays out a segment whose kept line count disagrees '
        'with a fresh one contradicts the kept measures', () {
      final kept = measuresOf(chapter.section).paragraphs[long]!;
      final start = chapter.pages[pageInParagraph()].start;
      // The segment of the page's first line, and the lines before the
      // segment after it, one more than they are.
      final segment = kept.lines.lastIndexWhere((lines) => lines <= start.line);
      expect(segment + 1, lessThan(kept.lines.length));
      final fresh = prepared(_paragraphSection());
      reuseMeasures(
        fresh,
        SectionMeasures(
          paragraphs: {
            long: (
              starts: kept.starts,
              lines: [...kept.lines]..[segment + 1] += 1,
            ),
          },
        ),
      );

      final run = LayoutRun(fresh, from: start)
        ..step(const Duration(days: 1), want: 1);
      addTearDown(() {
        for (final page in run.pages) {
          page.dispose();
        }
        run.dispose();
      });

      expect(run.contradicted, isTrue);
    });

    test('a run that finds a kept segment end wrong goes on with the '
        'segments that it finds, and cuts the same pages', () {
      final kept = measuresOf(chapter.section).paragraphs[long]!;
      final first = chapter.pages.indexWhere(
        (page) => page.start.item == long && page.start.line > 0,
      );
      final start = chapter.pages[first].start;
      // Kept segments whose segment after the page's first line starts
      // seven code units early.
      final segment = kept.lines.lastIndexWhere((lines) => lines <= start.line);
      final fresh = prepared(_paragraphSection());
      reuseMeasures(
        fresh,
        SectionMeasures(
          paragraphs: {
            long: (
              starts: [...kept.starts]..[segment + 1] -= 7,
              lines: kept.lines,
            ),
          },
        ),
      );

      final run = LayoutRun(fresh, from: start)..step(const Duration(days: 1));
      addTearDown(() {
        for (final page in run.pages) {
          page.dispose();
        }
        run.dispose();
      });

      expect(run.contradicted, isTrue);
      expect(keys(run.pages), keys(chapter.pages.skip(first)));
      expect(measuresOf(fresh).paragraphs[long]?.starts, kept.starts);
      expect(measuresOf(fresh).paragraphs[long]?.lines, kept.lines);
    });

    test('kept segments that do not fit the section are refused', () {
      final kept = measuresOf(chapter.section).paragraphs[long]!;
      Segments moved(int by) => (
        starts: [for (final start in kept.starts) start + by],
        lines: kept.lines,
      );

      for (final paragraphs in [
        {long - 1: kept},
        {long: moved(1)},
        {long: (starts: kept.starts.reversed.toList(), lines: kept.lines)},
        {long: (starts: kept.starts, lines: kept.lines.skip(1).toList())},
        {long: moved(1 << 20)},
      ]) {
        expect(
          reuseMeasures(
            prepared(_paragraphSection()),
            SectionMeasures(paragraphs: paragraphs),
          ),
          isFalse,
          reason: '$paragraphs',
        );
      }
    });

    test('the measures of a laid out section hold the segments of each '
        'long paragraph', () {
      final segments = measuresOf(chapter.section).paragraphs[long];

      expect(segments?.starts.length, greaterThan(10));
      expect(segments?.lines.length, segments?.starts.length);
      expect(measuresOf(chapter.section).paragraphs.keys, [long]);
    });
  });
}
