// Text selection on the shown page, in Flutter's SelectableRegion.
//
// A selection is two carets on the page's text lines: its lines, and the
// lines of its table cells, in reading order. The region sends selection
// events: a long press selects the word under the finger, a handle or a
// mouse drag moves one edge, and select all takes the whole page. The
// selected text is the book's own text of the range (see [bookUnits]), with
// a line break between paragraphs, so the hyphens, soft hyphens and word
// joiners that layout inserts never reach the clipboard. Its rectangles
// come from the paragraphs' boxes. A selection belongs to one page, and a
// new page clears it.
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../selection.dart';
import 'dom.dart';
import 'layout.dart';
import 'semantics.dart';

/// A place between two code units of a text line of a page.
@immutable
class PageCaret implements Comparable<PageCaret> {
  const PageCaret(this.line, this.unit);

  /// The line's index in the page's [textLines].
  final int line;

  /// A code unit of the line's piece, from the line's first unit to its
  /// end, which is the first unit of the next line.
  final int unit;

  @override
  int compareTo(PageCaret other) =>
      line != other.line ? line - other.line : unit - other.unit;

  @override
  bool operator ==(Object other) =>
      other is PageCaret && other.line == line && other.unit == unit;

  @override
  int get hashCode => Object.hash(line, unit);

  @override
  String toString() => 'PageCaret($line, $unit)';
}

/// The text lines of [page] in reading order: its lines, and the lines of
/// its table rows cell by cell.
List<Slice> textLines(LaidPage page) => [
  for (final slice in page.slices)
    for (final line in slice.cellSlices.isEmpty ? [slice] : slice.cellSlices)
      if (line.piece != null) line,
];

/// The book's text that [page] shows between carets [a] and [b] of its
/// text [lines], in either order. White space reads as one space and a
/// line break element as a line break. Each paragraph or table cell after
/// the first starts on a new line. Images read as nothing.
String selectedText(
  LaidPage page,
  List<Slice> lines,
  PageCaret a,
  PageCaret b,
) {
  final (from, to) = a.compareTo(b) <= 0 ? (a, b) : (b, a);
  final runs = [
    for (var index = from.line; index <= to.line; index++)
      (
        lines[index],
        index == from.line ? from.unit : lines[index].units.$1,
        index == to.line ? to.unit : lines[index].units.$2,
      ),
  ];
  // The index in [runs] of each line, and whether it starts a paragraph
  // or a cell.
  final runOf = {for (final (index, run) in runs.indexed) run.$1: index};
  final opens = [
    for (final (index, run) in runs.indexed)
      index > 0 && !continuesParagraph(runs[index - 1].$1, run.$1),
  ];
  final out = StringBuffer();
  int? last;
  for (final shown in bookUnits(page, runs)) {
    final index = runOf[shown.line]!;
    // A paragraph whose selected lines show nothing still starts a line.
    if (last != null && opens.sublist(last + 1, index + 1).contains(true)) {
      out.write('\n');
    }
    last = index;
    switch (shown) {
      case BookText(:final text):
        out.write(text.length == 1 && isSpace(text.codeUnitAt(0)) ? ' ' : text);
      case BookBreak():
        out.write('\n');
      case BookImage():
        break;
    }
  }
  return out.toString();
}

/// The caret of [lines] nearest to [point], in logical pixels from the top
/// left corner of [page], or null when the page has no text line. A point
/// above or below the text takes the nearest line, and a point beside a
/// line takes its start or its end.
PageCaret? caretAt(LaidPage page, List<Slice> lines, ui.Offset point) {
  final found = _lineAt(page, lines, point);
  if (found == null) return null;
  final line = lines[found];
  final (first, end) = line.units;
  final position = _positionIn(line, point);
  return PageCaret(found, position.offset.clamp(first, end));
}

/// The word of [lines] under [point], in logical pixels from the top left
/// corner of [page], as its start and end carets, or null when the page
/// has no text line. A word that a line break splits ends on the next
/// line of its paragraph, if the page shows it.
(PageCaret, PageCaret)? wordAt(
  LaidPage page,
  List<Slice> lines,
  ui.Offset point,
) {
  final found = _lineAt(page, lines, point);
  if (found == null) return null;
  final line = lines[found];
  final (first, end) = line.units;
  final position = _positionIn(line, point);
  // The code unit under the point, as linkAt finds it.
  final unit =
      (position.affinity == ui.TextAffinity.downstream
              ? position.offset
              : position.offset - 1)
          .clamp(first, end - 1);
  final word = line.piece!.paragraph.getWordBoundary(
    ui.TextPosition(offset: unit),
  );
  return (
    _caretOf(lines, found, word.start, before: false),
    _caretOf(lines, found, word.end, before: true),
  );
}

/// The paragraph or table cell of [lines] under [point], in logical
/// pixels from the top left corner of [page], as its start and end carets
/// on the page, or null when the page has no text line.
(PageCaret, PageCaret)? blockAt(
  LaidPage page,
  List<Slice> lines,
  ui.Offset point,
) {
  final found = _lineAt(page, lines, point);
  if (found == null) return null;
  var first = found;
  while (first > 0 && continuesParagraph(lines[first - 1], lines[first])) {
    first--;
  }
  var last = found;
  while (last + 1 < lines.length &&
      continuesParagraph(lines[last], lines[last + 1])) {
    last++;
  }
  return (
    PageCaret(first, lines[first].units.$1),
    PageCaret(last, lines[last].units.$2),
  );
}

/// The index of the line of [lines] nearest to [point], from the top left
/// corner of [page]: the nearest up or down, then the nearest across, as
/// in a table row. Null when [lines] is empty.
int? _lineAt(LaidPage page, List<Slice> lines, ui.Offset point) {
  int? best;
  var bestDown = double.infinity;
  var bestAcross = double.infinity;
  double outside(double value, double low, double high) =>
      value < low ? low - value : (value > high ? value - high : 0);
  for (final (index, line) in lines.indexed) {
    final piece = line.piece!;
    final down = outside(point.dy, line.top - page.top, line.bottom - page.top);
    final across = outside(point.dx, piece.x, piece.x + piece.paragraph.width);
    if (down < bestDown || (down == bestDown && across < bestAcross)) {
      best = index;
      bestDown = down;
      bestAcross = across;
    }
  }
  return best;
}

/// The text position of [line]'s paragraph across from [point], from the
/// page's left edge, in the middle of the line, where Flutter lays it out.
ui.TextPosition _positionIn(Slice line, ui.Offset point) {
  final piece = line.piece!;
  final metrics = piece.paragraph.getLineMetricsAt(line.line);
  final y = metrics == null
      ? 0.0
      : metrics.baseline - metrics.ascent + metrics.height / 2;
  return piece.paragraph.getPositionForOffset(ui.Offset(point.dx - piece.x, y));
}

/// The caret at code unit [unit] of the piece of line [index] of [lines],
/// on the line of that piece that holds it. A unit at the end of one line
/// and the start of the next is on the first of them [before], else on
/// the second. A unit on a line that the page does not show is the end of
/// the piece's last line on the page, or the start of its first.
PageCaret _caretOf(
  List<Slice> lines,
  int index,
  int unit, {
  required bool before,
}) {
  final piece = lines[index].piece;
  var at = index;
  while (at > 0 &&
      identical(lines[at - 1].piece, piece) &&
      (before ? unit <= lines[at].units.$1 : unit < lines[at].units.$1)) {
    at--;
  }
  while (at + 1 < lines.length &&
      identical(lines[at + 1].piece, piece) &&
      (before ? unit > lines[at].units.$2 : unit >= lines[at].units.$2)) {
    at++;
  }
  final (first, end) = lines[at].units;
  return PageCaret(at, unit.clamp(first, end));
}

/// The selection on the shown page, as a [Selectable] in the nearest
/// [SelectionContainer], which [registrar] names.
///
/// It reports where the page draws: [box], the page's render object, which
/// gives its size and transform, and which paints the [rects] and the
/// handle layers of [pushHandleLayers] (see [paint]). Its [page] is the
/// shown page. A page that is not the same page clears the selection.
///
/// Invariants, which [checkInvariants] checks:
/// - The text lines are the shown page's [textLines].
/// - The start and the end carets are both null, or both on those lines,
///   each within its line's code units.
class PageSelection
    with ChangeNotifier, ReaderSelection<PageCaret>, SelectionRegistrant {
  PageSelection(this.box);

  @override
  final RenderBox box;
  LaidPage? _page;
  List<Slice> _lines = const [];

  LaidPage? get page => _page;
  set page(LaidPage? value) {
    if (identical(value, _page)) return;
    _page = value;
    _lines = value == null ? const [] : textLines(value);
    updateSelection(clear: true);
  }

  @override
  (PageCaret, PageCaret)? get extent => _lines.isEmpty
      ? null
      : (
          PageCaret(0, _lines.first.units.$1),
          PageCaret(_lines.length - 1, _lines.last.units.$2),
        );

  @override
  PageCaret? caretFor(ui.Offset point) => caretAt(_page!, _lines, point);

  @override
  int compareCarets(PageCaret first, PageCaret second) =>
      first.compareTo(second);

  @override
  (PageCaret, PageCaret)? rangeFor(
    ui.Offset point,
    TextGranularity granularity,
  ) => granularity == TextGranularity.paragraph
      ? blockAt(_page!, _lines, point)
      : wordAt(_page!, _lines, point);

  @override
  String textFor(PageCaret start, PageCaret end) =>
      selectedText(_page!, _lines, start, end);

  @override
  int offsetOf(PageCaret caret) {
    var offset = 0;
    for (var index = 0; index < caret.line; index++) {
      final (first, end) = _lines[index].units;
      offset += end - first;
    }
    return offset + caret.unit - _lines[caret.line].units.$1;
  }

  @override
  void checkInvariants() {
    super.checkInvariants();
    final lines = _page == null ? const <Slice>[] : textLines(_page!);
    if (!listEquals(lines, _lines)) {
      throw StateError('The text lines are not the shown page\'s.');
    }
    for (final caret in selectionCarets) {
      if (caret.line < 0 || caret.line >= lines.length) {
        throw StateError('$caret is on no text line of the page.');
      }
      final (first, end) = lines[caret.line].units;
      if (caret.unit < first || caret.unit > end) {
        throw StateError('$caret is outside its line, [$first, $end].');
      }
    }
  }

  @override
  SelectionGeometry geometryFor(PageCaret start, PageCaret end) {
    final page = _page!;
    final forward = start.compareTo(end) <= 0;
    final (from, to) = forward ? (start, end) : (end, start);
    final rects = <ui.Rect>[
      for (var index = from.line; index <= to.line; index++)
        ..._boxes(
          page,
          _lines[index],
          index == from.line ? from.unit : _lines[index].units.$1,
          index == to.line ? to.unit : _lines[index].units.$2,
        ),
    ];
    SelectionPoint point(PageCaret caret, bool left) {
      final line = _lines[caret.line];
      final (first, end) = line.units;
      final piece = line.piece!;
      // The edge of the character after the caret, or at a line's end, of
      // the one before it.
      final after = caret.unit < end;
      final unit = after ? caret.unit : caret.unit - 1;
      final boxes = unit < first
          ? const <ui.TextBox>[]
          : piece.paragraph.getBoxesForRange(unit, unit + 1);
      final x =
          piece.x +
          (boxes.isEmpty
              ? 0
              : after
              ? boxes.first.left
              : boxes.last.right);
      return SelectionPoint(
        localPosition: ui.Offset(x, line.bottom - page.top),
        lineHeight: line.bottom - line.top,
        handleType: left
            ? TextSelectionHandleType.left
            : TextSelectionHandleType.right,
      );
    }

    return SelectionGeometry(
      startSelectionPoint: point(start, forward),
      endSelectionPoint: point(end, !forward),
      selectionRects: rects,
      status: start == end
          ? SelectionStatus.collapsed
          : SelectionStatus.uncollapsed,
      hasContent: true,
    );
  }

  /// The boxes of code units [from] to [to] of [line], where the page draws
  /// them: each line draws at its exact place (see [Piece.shifts]).
  static Iterable<ui.Rect> _boxes(
    LaidPage page,
    Slice line,
    int from,
    int to,
  ) sync* {
    if (from >= to) return;
    final piece = line.piece!;
    final shift = line.line < piece.shifts.length ? piece.shifts[line.line] : 0;
    for (final box in piece.paragraph.getBoxesForRange(from, to)) {
      yield box.toRect().shift(ui.Offset(piece.x, piece.y + shift - page.top));
    }
  }
}
