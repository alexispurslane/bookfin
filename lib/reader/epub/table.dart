// The grid of a table item, in a simple form of CSS automatic table
// layout: column widths from each cell's narrowest and widest content.
// Layout (layout.dart) measures the cells, lays each one out in the box
// that this file gives it, and makes each row a strip slice.
//
// A cell spans the columns of its colspan. A rowspan counts as 1, so each
// row starts again at the first column.
import 'dart:math' as math;

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
