// A section's measures that a run from a page start inside a flow item
// needs first, kept from an earlier layout of the section (t5-s1vy): the
// narrowest and widest content width of each table cell. With them, a run
// from a kept start inside a table cuts its pages without the measure of
// the whole table. A run that finds a kept measure again checks it.
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
}
