// The grid of a table item, in a simple form of CSS automatic table
// layout: column widths from each cell's narrowest and widest content.
// Layout (layout.dart) measures the cells, lays each one out in the box
// that this file gives it, and makes each row a strip slice.
//
// A cell spans the columns of its colspan. A rowspan counts as 1, so each
// row starts again at the first column.
//
// A row taller than a page splits into fragments between the slices of its
// cells, as Chromium fragments a table row: each fragment but the last is
// one page tall, and each cell goes on in the next fragment from its first
// slice that did not fit.
import 'dart:math' as math;

/// How far, in pixels, a slice can pass a page's bottom and still fit on
/// the page. Layout cuts pages with it too.
const fitTolerance = 0.01;

/// The space between the cells of a table and around them: Chromium's
/// default `border-spacing`.
const cellSpacing = 2.0;

/// One cell of a grid: the number of columns that it spans, and its
/// narrowest and widest content width in pixels, its padding and borders
/// included. The narrowest width holds its longest word; the widest holds
/// each of its paragraphs on one line.
typedef GridCell = ({int span, double min, double max});

/// The width of each column of a grid of [rows] that fills a table
/// [width] pixels wide (its content box, the spacing included).
///
/// Each column wants the narrowest and the widest content of its cells. A
/// cell that spans columns widens them evenly by what they lack. If the
/// widest widths fit, each column takes its widest width and a share of
/// any width left in proportion to it. Else each column takes its
/// narrowest width and a share of the rest in proportion to the width that
/// it wants beyond that. If even the narrowest widths do not fit, the
/// columns shrink in proportion to them.
List<double> columnWidths(List<List<GridCell>> rows, double width) {
  final (:min, :max) = _columns(rows);
  final count = min.length;
  final space = math.max(0.0, width - cellSpacing * (count + 1));
  final wantMin = _sum(min);
  final wantMax = _sum(max);
  if (wantMax <= space) {
    final extra = space - wantMax;
    return [
      for (var column = 0; column < count; column++)
        max[column] +
            (wantMax == 0 ? extra / count : extra * max[column] / wantMax),
    ];
  }
  if (wantMin < space) {
    final rest = space - wantMin;
    final beyond = wantMax - wantMin;
    return [
      for (var column = 0; column < count; column++)
        min[column] + rest * (max[column] - min[column]) / beyond,
    ];
  }
  return [
    for (var column = 0; column < count; column++)
      wantMin == 0 ? 0 : min[column] * space / wantMin,
  ];
}

/// The width of a grid of [rows] whose columns take their widest content,
/// the spacing included: the table's widest content width.
double gridMaxContent(List<List<GridCell>> rows) {
  final (:min, :max) = _columns(rows);
  return _sum(max) + cellSpacing * (max.length + 1);
}

/// The box of each cell of a row whose cells span [spans] columns, in
/// columns of [widths]: its left edge from the table's content left, and
/// its width. A cell that spans past the last column stops there.
List<(double, double)> cellBoxes(List<int> spans, List<double> widths) {
  final boxes = <(double, double)>[];
  var column = 0;
  var left = cellSpacing;
  for (final span in spans) {
    final end = math.min(column + span, widths.length);
    var width = 0.0;
    for (var index = column; index < end; index++) {
      width += widths[index];
    }
    width += cellSpacing * math.max(0, end - column - 1);
    boxes.add((left, width));
    left += width + cellSpacing;
    column = end;
  }
  return boxes;
}

/// A cell of a row, for cutting the row into fragments: the extent
/// [top, bottom) of each slice of its content, from the top of its box,
/// the height of its box, and its vertical-align (0 at the top, 0.5 in the
/// middle, 1 at the bottom).
typedef FragmentCell = ({
  List<(double, double)> slices,
  double height,
  double align,
});

/// What a fragment of a row shows of one cell: its slices [from, to), the
/// place of the cell box's top below the fragment's top ([offset]), and the
/// band [top, bottom) of the box, in the box's own coordinates, that the
/// fragment shows. A cell that the fragment does not show has an empty
/// band.
typedef CellFragment = ({
  int from,
  int to,
  double offset,
  double top,
  double bottom,
});

/// A fragment of a row: its height on the strip and what it shows of each
/// cell, in the order of the cells.
typedef RowFragment = ({double height, List<CellFragment> cells});

/// The fragments of a row of [cells] on pages [pageHeight] pixels tall.
///
/// A row that fits a page is one fragment as tall as its tallest cell, and
/// each cell sits where its vertical-align puts it. A taller row splits.
/// Each cell then starts at the row's top, because no page shows the whole
/// row that vertical-align centers in. A fragment takes each cell's
/// slices while they fit in one page height from its first slice; a slice
/// taller than a page goes alone when no cell has a slice that fits. Each
/// fragment but the last is a page tall, so each starts a page. The next
/// fragment goes on with each cell from its first slice that did not fit,
/// at the fragment's top: the space above that slice is dropped, as
/// margins at a page break are. The space below a cell's last slice, its
/// bottom padding and border, goes last, and on the next fragment when it
/// does not fit.
List<RowFragment> rowFragments(List<FragmentCell> cells, double pageHeight) {
  final height = cells.fold(
    0.0,
    (tallest, cell) => math.max(tallest, cell.height),
  );
  if (height <= pageHeight + fitTolerance) {
    return [
      (
        height: height,
        cells: [
          for (final cell in cells)
            (
              from: 0,
              to: cell.slices.length,
              offset: (height - cell.height) * cell.align,
              top: double.negativeInfinity,
              bottom: double.infinity,
            ),
        ],
      ),
    ];
  }
  // Each cell's slices, then the space below its last one.
  final units = [
    for (final cell in cells)
      [
        ...cell.slices,
        if (cell.height > (cell.slices.lastOrNull?.$2 ?? 0))
          (cell.slices.lastOrNull?.$2 ?? 0, cell.height),
      ],
  ];
  final next = List.filled(cells.length, 0);
  final fragments = <RowFragment>[];
  bool done(int cell) => next[cell] == units[cell].length;
  bool allDone() => next.indexed.every((entry) => done(entry.$1));
  while (fragments.isEmpty || !allDone()) {
    // The box position at the fragment's top, for each cell.
    final tops = [
      for (var cell = 0; cell < cells.length; cell++)
        fragments.isEmpty || done(cell) ? 0.0 : units[cell][next[cell]].$1,
    ];
    final ends = [
      for (var cell = 0; cell < cells.length; cell++)
        () {
          var end = next[cell];
          while (end < units[cell].length &&
              units[cell][end].$2 - tops[cell] <= pageHeight + fitTolerance) {
            end++;
          }
          return end;
        }(),
    ];
    // A slice taller than a page goes alone when no cell has one that fits.
    if (ends.indexed.every((entry) => entry.$2 == next[entry.$1])) {
      for (var cell = 0; cell < cells.length; cell++) {
        if (!done(cell)) ends[cell]++;
      }
    }
    var reach = 0.0;
    final shown = <CellFragment>[];
    for (var cell = 0; cell < cells.length; cell++) {
      final count = cells[cell].slices.length;
      final shows = ends[cell] > next[cell];
      if (shows) {
        reach = math.max(reach, units[cell][ends[cell] - 1].$2 - tops[cell]);
      }
      shown.add((
        from: math.min(next[cell], count),
        to: math.min(ends[cell], count),
        offset: -tops[cell],
        top: !shows
            ? double.infinity
            : fragments.isEmpty
            ? double.negativeInfinity
            : tops[cell],
        bottom: !shows
            ? double.infinity
            : ends[cell] < units[cell].length
            ? units[cell][ends[cell]].$1
            : double.infinity,
      ));
      next[cell] = ends[cell];
    }
    final last = allDone();
    fragments.add((
      height: last ? reach : math.max(pageHeight, reach),
      cells: shown,
    ));
  }
  return fragments;
}

/// The narrowest and the widest width that each column of [rows] wants.
({List<double> min, List<double> max}) _columns(List<List<GridCell>> rows) {
  var count = 0;
  for (final row in rows) {
    count = math.max(count, row.fold(0, (sum, cell) => sum + cell.span));
  }
  final min = List.filled(count, 0.0);
  final max = List.filled(count, 0.0);
  for (final row in rows) {
    var column = 0;
    for (final cell in row) {
      if (cell.span == 1) {
        min[column] = math.max(min[column], cell.min);
        max[column] = math.max(max[column], cell.max);
      }
      column += cell.span;
    }
  }
  // Spanning cells go after the single ones, which they widen.
  for (final row in rows) {
    var column = 0;
    for (final cell in row) {
      if (cell.span > 1) {
        _widen(min, column, cell.span, cell.min);
        _widen(max, column, cell.span, cell.max);
      }
      column += cell.span;
    }
  }
  for (var column = 0; column < count; column++) {
    max[column] = math.max(max[column], min[column]);
  }
  return (min: min, max: max);
}

/// Widens the [span] columns of [widths] from [column] evenly, so that
/// with the spacing between them they are at least [want] pixels wide.
void _widen(List<double> widths, int column, int span, double want) {
  var have = cellSpacing * (span - 1);
  for (var index = column; index < column + span; index++) {
    have += widths[index];
  }
  if (want <= have) return;
  final share = (want - have) / span;
  for (var index = column; index < column + span; index++) {
    widths[index] += share;
  }
}

double _sum(List<double> values) => values.fold(0, (sum, value) => sum + value);
