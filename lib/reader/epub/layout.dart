// Lays out one prepared section with Flutter's text engine and cuts it into
// pages. It runs on the UI isolate, because dart:ui paragraphs exist only
// there.
//
// The section flows down one strip as wide as the page, as a scrolled
// document would. Each line, image, rule and table row is a slice of the
// strip. A page is a window [top, bottom) of the strip that holds whole
// slices, so a paragraph splits across pages between its lines, and a table
// between its rows. A row taller than a page is a slice for each of its
// fragments (table.dart), so it splits between the lines of its cells.
// Lines sit at their exact CSS positions, as in Chromium, and not where
// Flutter's whole-pixel line heights put them (see [Piece.tops]). The
// breaks follow CSS fragmentation as Chromium applies it to the WebView
// reader's columns:
// margins at a break are dropped, `break-before: page` is ignored as the
// columns ignore it, and a break picks the latest place with the best
// "appeal" (orphans, widows and avoid rules).
//
// A layout run lays the strip out forward, one flow item at a time, and
// cuts each page as soon as the slices reach one page height below the
// page's top. A cut reads only those slices, and each slice's appeal is
// final when the slice is added. So a run that starts at a page start cuts
// the same pages after it as the run from the section start.
import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'css.dart';
import 'dom.dart';
import 'prepare.dart';
import 'table.dart';

/// The page colors of [PageSettings].
extension PageColors on PageSettings {
  ui.Color get paper =>
      night ? const ui.Color(0xff251e19) : const ui.Color(0xfff6efe2);
  ui.Color get ink =>
      night ? const ui.Color(0xffdcc9a9) : const ui.Color(0xff39291f);
}

/// How good a place to break a page is, from Chromium's block
/// fragmentation: higher is better.
abstract final class Appeal {
  static const lastResort = 0;
  static const violatingAvoid = 1;
  static const violatingOrphansWidows = 2;
  static const perfect = 3;
}

/// Where a page begins: line [line] of flow item [item], from fragment
/// [part] of that line.
///
/// A paragraph's lines count from its first line, a hanging first line
/// included. A table's lines are its rows, and a row taller than a page
/// splits into fragments (table.dart), which count from 0. Every other
/// start is at fragment 0. An image, and a box without content that is a
/// slice of its own (such as a rule), start at line 0 of their item. The
/// section's first page starts at `PageStart(0, 0)`.
class PageStart implements Comparable<PageStart> {
  const PageStart(this.item, this.line, [this.part = 0]);
  final int item;
  final int line;
  final int part;

  @override
  int compareTo(PageStart other) => item != other.item
      ? item.compareTo(other.item)
      : line != other.line
      ? line.compareTo(other.line)
      : part.compareTo(other.part);

  @override
  bool operator ==(Object other) =>
      other is PageStart &&
      other.item == item &&
      other.line == line &&
      other.part == part;

  @override
  int get hashCode => Object.hash(item, line, part);

  @override
  String toString() =>
      part == 0 ? 'PageStart($item, $line)' : 'PageStart($item, $line, $part)';
}

/// A slice of the strip that a page holds whole: a line, an image, a rule,
/// a table row or a fragment of a row taller than a page.
class Slice {
  Slice(
    this.top,
    this.bottom,
    this.appeal,
    this.at, {
    this.piece,
    this.line = -1,
    this.start,
    this.units = (0, 0),
    this.cellSlices = const [],
  });
  final double top;
  final double bottom;

  /// The appeal of a page break right before this slice.
  final int appeal;

  /// The start of a page that begins with this slice.
  final PageStart at;

  /// The paragraph that holds this line, or null for an image, a rule or a
  /// table row.
  final Piece? piece;

  /// The line's index in [piece].
  final int line;

  /// The place of the slice's first character, or null when it shows no
  /// text.
  final EpubPlace? start;

  /// The code units of [piece]'s text that the line shows, [start, end).
  final (int, int) units;

  /// The slices of the cells' content that a table row, or a fragment of
  /// a row taller than a page, shows: cell by cell, in document order. Their
  /// [at] is a place in their cell's flow. Empty for any other slice.
  final List<Slice> cellSlices;
}

/// One laid-out paragraph: a Flutter paragraph at a place on the strip,
/// and where each of its characters comes from in the DOM.
///
/// The run that builds a piece and each page that shows it hold it. Its
/// paragraphs are disposed when the last holder lets it go. A piece moved
/// to another place, as a split table row shows one paragraph on several
/// pages, shares its paragraphs and their holders.
class Piece {
  /// The laid-out [paragraph] at ([x], [y]), with its lines where Flutter
  /// puts them.
  Piece(ui.Paragraph paragraph, this.x, this.y, this.map)
    : _paragraphs = _Paragraphs(paragraph, exact: false);

  Piece._of(this._paragraphs, this.x, this.y, this.map);

  /// A piece of a kept page ([PageDrawing]): [paragraph] at ([x], [y]),
  /// with the [tops], [shifts], [shown] height and [inlines] of the piece
  /// that the page kept. It has no text map, and its holder disposes
  /// [paragraph] and the paragraphs in [inlines].
  Piece.kept(
    ui.Paragraph paragraph,
    this.x,
    this.y, {
    required List<double> tops,
    required List<double> shifts,
    required this.shown,
    required List<(ui.Rect, Object)> inlines,
  }) : map = TextMap(-1),
       _paragraphs = _Paragraphs.kept(paragraph, tops, shifts, inlines);

  /// [piece] moved down by [dy], holding its paragraphs once more.
  Piece._moved(Piece piece, double dy, this.shown)
    : x = piece.x,
      y = piece.y + dy,
      map = piece.map,
      _paragraphs = piece._paragraphs {
    _hold();
  }

  ui.Paragraph get paragraph => _paragraphs.paragraph;
  final double x;
  final double y;
  final TextMap map;

  /// Images ([DrawnImage]) and raised text ([ui.Paragraph]) drawn in the
  /// paragraph's placeholders, at their place from the piece's top left.
  List<(ui.Rect, Object)> get inlines => _paragraphs.inlines;

  /// The top of each line from the piece's top, and the bottom of the last
  /// line. Flutter rounds each line's height to a whole pixel, but Chromium
  /// does not, so an exact line's height is Flutter's height before it
  /// rounds: its ascent and descent. That is the CSS line height, or the
  /// height of the line's tallest inline content.
  List<double> get tops => _paragraphs.tops;

  /// How far each line draws below the place where Flutter draws it, so
  /// that its baseline sits at its exact place.
  List<double> get shifts => _paragraphs.shifts;

  /// The height of the lines that this piece shows, from its top. A hanging
  /// first line is a paragraph of its own that shows only its first line.
  /// A page of a split table row shows a cell's lines down to the first
  /// line that the next page shows.
  double shown = double.infinity;

  final _Paragraphs _paragraphs;

  void _hold() => _paragraphs.holders++;

  void _release() {
    final paragraphs = _paragraphs;
    assert(
      paragraphs.holders > 0,
      'A piece was released more often than held.',
    );
    if (--paragraphs.holders > 0) return;
    paragraphs.paragraph.dispose();
    for (final (_, held) in paragraphs.inlines) {
      if (held is ui.Paragraph) held.dispose();
    }
  }
}

/// The paragraphs that one or more pieces show, and how many holders they
/// have.
class _Paragraphs {
  /// The lines of [paragraph] at their exact CSS positions when [exact],
  /// and where Flutter puts them otherwise (see [Piece.tops]).
  _Paragraphs(this.paragraph, {required bool exact}) {
    final metrics = paragraph.computeLineMetrics();
    var top = 0.0;
    for (final (index, line) in metrics.indexed) {
      tops.add(top);
      shifts.add(exact ? top + line.ascent - line.baseline : 0);
      top = exact
          ? top + line.ascent + line.descent
          : index == metrics.length - 1
          ? paragraph.height
          : line.baseline + line.descent;
    }
    tops.add(top);
  }

  /// The paragraphs of a kept piece ([Piece.kept]).
  _Paragraphs.kept(
    this.paragraph,
    List<double> tops,
    List<double> shifts,
    List<(ui.Rect, Object)> inlines,
  ) {
    this.tops.addAll(tops);
    this.shifts.addAll(shifts);
    this.inlines.addAll(inlines);
  }

  final ui.Paragraph paragraph;
  final List<(ui.Rect, Object)> inlines = [];
  final tops = <double>[];
  final shifts = <double>[];
  int holders = 1;
}

/// A drawn thing on the strip that is not text: a border, a list marker or
/// a block image.
sealed class Decoration {}

class RuleDecoration extends Decoration {
  RuleDecoration(this.rect);
  final ui.Rect rect;
}

class ImageDecoration extends Decoration {
  ImageDecoration(this.rect, this.image);
  final ui.Rect rect;
  final DrawnImage image;
  String get path => image.path;
}

class MarkerDecoration extends Decoration {
  MarkerDecoration(this.piece);

  /// The marker's paragraph at its place on the strip. It has no text map.
  final Piece piece;

  ui.Paragraph get paragraph => piece.paragraph;
  ui.Offset get offset => ui.Offset(piece.x, piece.y);
}

/// What [drawPage] draws of a page: its settings, its place on its strip,
/// its pieces and its decorations. A [LaidPage] is one, and so is a kept
/// page, which a reopen of the book draws before the book loads.
abstract interface class PageDrawing {
  PageSettings get settings;

  /// Where the page begins on its strip, and how high it is.
  double get top;
  double get height;

  /// The paragraphs of the page's lines and table rows.
  Iterable<Piece> get pieces;

  /// The rules, images and markers that the page draws, at their place on
  /// the strip.
  List<Decoration> get decorations;
}

/// One cut page. It never changes once a run publishes it.
///
/// It holds the paragraphs that it shows, until [dispose]. Its geometry is
/// in the strip coordinates of the run that cut it.
class LaidPage implements PageDrawing {
  LaidPage._(
    this._section,
    this.start,
    this.top,
    this.bottom,
    this.slices,
    this.decorations,
    this.last,
    this._visibleBefore,
  ) {
    for (final piece in _pieces) {
      piece._hold();
    }
  }

  final PreparedSection _section;

  /// The section's spine index.
  int get section => _section.index;
  @override
  PageSettings get settings => _section.settings;

  /// The run styles of the page's section, which the recipes of its
  /// paragraphs name by index ([recipeOf]).
  List<RunStyle> get styles => _section.styles;

  /// The DOM of the page's section, where its places point.
  DomSection get dom => _section.dom;
  final PageStart start;

  /// Where the page begins and ends on its run's strip.
  @override
  final double top;
  final double bottom;
  @override
  double get height => bottom - top;

  /// The strip slices on the page, in order.
  final List<Slice> slices;

  @override
  final List<Decoration> decorations;

  /// Whether this is the section's last page.
  final bool last;

  /// The visible characters of the section before the page, when the page
  /// shows no place.
  final int _visibleBefore;

  bool _disposed = false;

  /// The place of the page's first text, or of its first image when it has
  /// no text, or null when it shows neither.
  late final EpubPlace? startPlace = () {
    EpubPlace? found;
    for (final slice in slices) {
      final start = slice.start;
      if (start == null) continue;
      if (_section.dom.textAt(start) != null) return start;
      found ??= start;
    }
    return found;
  }();

  /// The place of the page's last visible character, or null when it shows
  /// no text.
  late final EpubPlace? endPlace = () {
    final dom = _section.dom;
    for (final slice in slices.reversed) {
      final shown = [
        for (final line in [slice, ...slice.cellSlices])
          if (line.piece case final piece?) (piece, line.units),
      ];
      for (final (piece, (start, end)) in shown.reversed) {
        for (var unit = end - 1; unit >= start; unit--) {
          final place = piece.map.textPlaceAt(unit);
          if (place == null) continue;
          final text = dom.textAt(place)!.text;
          if (place.offset < text.length &&
              !isSpace(text.codeUnitAt(place.offset))) {
            return place;
          }
        }
      }
    }
    return null;
  }();

  /// The number of visible characters of the section before the page.
  late final int startVisible = startPlace == null
      ? _visibleBefore
      : _section.dom.visibleBefore(startPlace!);

  /// The number of visible characters of the section through the page's
  /// last one.
  late final int endVisible = endPlace == null
      ? startVisible
      : _section.dom.visibleBefore(endPlace!) + 1;

  /// The start of each line on the page, as a visible character index. A
  /// line without text, such as an image, is left out.
  List<int> get lineStarts => [
    for (final slice in slices)
      if (slice.start case final start? when _section.dom.textAt(start) != null)
        _section.dom.visibleBefore(start),
  ];

  /// The paragraphs of the page's lines and table rows. Throws a
  /// [StateError] once the page is disposed.
  @override
  Iterable<Piece> get pieces {
    if (_disposed) throw StateError('The page is disposed.');
    return _lines;
  }

  Iterable<Piece> get _lines sync* {
    Piece? previous;
    for (final slice in slices) {
      for (final line in [slice, ...slice.cellSlices]) {
        final piece = line.piece;
        if (piece != null && !identical(piece, previous)) {
          yield piece;
          previous = piece;
        }
      }
    }
  }

  /// The pieces that the page holds: its lines and its markers.
  Iterable<Piece> get _pieces sync* {
    yield* _lines;
    for (final decoration in decorations) {
      if (decoration is MarkerDecoration) yield decoration.piece;
    }
  }

  /// Lets go of the page's paragraphs. A paragraph that another page shows
  /// stays until that page is disposed too. A second call does nothing.
  void dispose() {
    if (_disposed) return;
    for (final piece in _pieces) {
      piece._release();
    }
    _disposed = true;
  }
}

/// Lays out a prepared section forward from a page start, one flow item at
/// a time, and cuts pages as it goes.
///
/// A run publishes a page when its slices reach one page height below the
/// page's top, or when it reaches the section end. A run that starts at a
/// page start of the run from the section start cuts the same pages after
/// it.
///
/// A run of a part of a section ([preparePart]) cuts the same pages as a
/// run of the whole section from the same start, until it reaches the end
/// of the part. There it is [starved]: it cuts no page that needs an item
/// after the part, and never the section's last page.
///
/// Invariants, which [checkInvariants] checks:
/// - The run holds every piece that a slice or a marker not yet published
///   shows, or a line that waits for its widows rule, and every piece that
///   it holds is alive.
/// - Published pages follow each other: their starts increase, and each
///   page's top is the previous page's bottom.
/// - The slices not yet published start at the top of the next page.
/// - A table or a long paragraph in progress is the next flow item, and has
///   a row or a segment left.
/// - Once the run is done, it laid out every flow item and holds no slice.
class LayoutRun {
  /// A run of [section] from [from], or from the section start. [clock]
  /// gives the time now for the step budget; it defaults to a monotonic
  /// clock.
  ///
  /// A run measures each row of a table for its column widths, once per
  /// table item, one row in each unit of work, unless an earlier layout's
  /// widths were given to the section ([reuseMeasures]). NOTE: A run that
  /// starts inside a shrink-to-fit box that holds a table not yet measured,
  /// as a table's own box is, measures the whole table here. The page
  /// source starts such runs only at page starts of the main run or of
  /// [lineStart], which measure the table first, in steps, or in sections
  /// whose widths it kept.
  LayoutRun(
    PreparedSection section, {
    PageStart? from,
    Duration Function()? clock,
  }) : _section = section,
       _flow = section.flow,
       _reachesEnd = section.reachesEnd,
       _clock = clock ?? _elapsed,
       _root = (0, section.settings.width),
       _textStyles = [
         for (final style in section.styles)
           _textStyle(style, section.settings.ink),
       ],
       _advances = _Advances() {
    final start = from ?? const PageStart(0, 0);
    if (start.item < 0 || start.item > section.flow.length) {
      throw RangeError.range(start.item, 0, section.flow.length, 'from.item');
    }
    if (start.line < 0) throw RangeError.value(start.line, 'from.line');
    if (start.part < 0) throw RangeError.value(start.part, 'from.part');
    _resume(start);
  }

  /// A run that lays out the flow of a table cell, [flow], in a column
  /// that starts at [left] and is [width] pixels wide, from strip position
  /// 0. It never cuts a page: [_layOutCell] takes its slices.
  LayoutRun._cell(
    LayoutRun outer,
    List<FlowItem> flow,
    double left,
    double width,
  ) : _section = outer._section,
      _flow = flow,
      _reachesEnd = true,
      _clock = outer._clock,
      _root = (left, width),
      _textStyles = outer._textStyles,
      _advances = outer._advances;

  static final _watch = Stopwatch()..start();
  static Duration _elapsed() => _watch.elapsed;

  /// The code units of paragraphs that runs gave the text engine to lay out
  /// at a width, in this process. Tests read it to count the passes over a
  /// paragraph.
  @visibleForTesting
  static int laidOutUnits = 0;

  /// The table cells that runs and searches measured for their narrowest
  /// and widest content, in this process.
  @visibleForTesting
  static int measuredCells = 0;

  /// Whether a measure that the run found again disagreed with a kept one
  /// ([reuseMeasures]). The run checks the kept widths of each table row
  /// that it lays out, and where each segment of a long paragraph that it
  /// lays out ends.
  bool get contradicted => _contradicted;
  bool _contradicted = false;

  final PreparedSection _section;

  /// The flow items that the run lays out: the section's, or a cell's.
  final List<FlowItem> _flow;

  /// Whether the end of [_flow] is the end of its content: false for a
  /// part of a section that ends before the section's end.
  final bool _reachesEnd;
  final Duration Function() _clock;

  /// The left edge and the width of the block that holds the flow's
  /// outermost boxes: the page, or a cell's column.
  final (double, double) _root;
  final List<ui.TextStyle> _textStyles;
  final _Advances _advances;

  final _pages = <LaidPage>[];
  bool _done = false;
  bool _disposed = false;

  /// The run's start, which is the section start when no slice comes
  /// before it.
  PageStart _from = const PageStart(0, 0);

  /// The next flow item, and the line and fragment of it to start at.
  int _item = 0;
  int _firstLine = 0;
  int _firstPart = 0;

  /// The table that the run lays out a row at a time, while it is not done.
  /// [_item] is its flow item until then.
  _Rows? _rows;

  /// The long paragraph that the run lays out a segment at a time, while it
  /// is not done. [_item] is its flow item until then.
  _Segments? _segments;

  /// The table that the next item needs measured, and its rows measured so
  /// far.
  TableItem? _measuringTable;
  final _measuring = <List<GridCell>>[];

  /// The slices of the page being filled and after it, its start and its
  /// top.
  final _pending = <Slice>[];
  PageStart _pageStart = const PageStart(0, 0);
  double _pageTop = 0;

  /// The number of slices the run added.
  int _added = 0;

  /// The decorations that a page not yet cut can show.
  final _decorations = <Decoration>[];

  /// The pieces that the run holds.
  final _held = <Piece>[];

  final _open = <_OpenBlock>[];
  double _y = 0;
  double _positive = 0;
  double _negative = 0;
  bool _avoidNext = false;
  (ui.Paragraph, double)? _pendingMarker;

  /// Whether margins are dropped: in a run that starts after the section
  /// start, until its first slice, as at a page break.
  bool _dropMargins = false;

  /// The pages that the run published, in order. A published page never
  /// changes. The caller owns them and disposes each.
  late final List<LaidPage> pages = UnmodifiableListView(_pages);

  /// Whether the run published the section's last page.
  bool get done => _done;

  /// Whether the run laid out every flow item of a part of a section that
  /// ends before the section's end, so that its next page needs the whole
  /// section. A step does nothing then.
  bool get starved => !_done && _item == _flow.length && !_reachesEnd;

  /// The index of the flow item that the run lays out next. It is the
  /// flow's length once every item is laid out.
  int get reached => _item;

  /// The start of the next page that the run publishes, while it is not
  /// [done].
  PageStart get next => _pageStart;

  /// Lays out flow items until [budget] is spent or [want] pages are cut in
  /// this step (null: no page limit). A step ends after the item, usually a
  /// paragraph, that crosses the budget, so it lays out at least one item.
  void step(Duration budget, {int? want}) {
    if (_disposed) throw StateError('The layout run is disposed.');
    if (want != null && want < 1) {
      throw RangeError.value(want, 'want', 'must be at least 1');
    }
    final begin = _clock();
    final target = _pages.length + (want ?? 0);
    while (!_done && !starved) {
      _layOutItem();
      _cut();
      if (want != null && _pages.length >= target) return;
      if (_clock() - begin >= budget) return;
    }
  }

  /// Throws a [StateError] when an invariant of the class comment does not
  /// hold. It runs on demand, in every build.
  void checkInvariants() {
    void check(bool holds, String message) {
      if (!holds) throw StateError('LayoutRun: $message');
    }

    if (!_disposed) {
      final held = _held.toSet();
      for (final slice in _pending) {
        if (slice.piece case final piece?) {
          check(held.contains(piece), 'a pending line is not held');
        }
        for (final line in slice.cellSlices) {
          if (line.piece case final piece?) {
            check(held.contains(piece), 'a pending table row is not held');
          }
        }
      }
      for (final decoration in _decorations) {
        if (decoration is MarkerDecoration) {
          check(
            held.contains(decoration.piece),
            'a pending marker is not held',
          );
        }
      }
      for (final line in _segments?.waiting ?? const <_Line>[]) {
        check(held.contains(line.piece), 'a waiting line is not held');
      }
      for (final piece in _held) {
        check(piece._paragraphs.holders > 0, 'a held piece is disposed');
      }
    }
    for (var index = 1; index < _pages.length; index++) {
      final page = _pages[index];
      final previous = _pages[index - 1];
      check(page.start.compareTo(previous.start) > 0, 'page starts repeat');
      check(page.top == previous.bottom, 'pages leave a gap');
    }
    if (_pages.isNotEmpty && _pending.isNotEmpty) {
      check(_pending.first.top == _pageTop, 'the next page has no top');
      check(_pending.first.at == _pageStart, 'the next page has no start');
    }
    if (_rows case final rows?) {
      check(rows.item == _item, 'a table in progress is not the next item');
      check(rows.row < rows.table.rows.length, 'a table has no row left');
      check(
        rows.cells.length < rows.table.rows[rows.row].length ||
            rows.table.rows[rows.row].isEmpty,
        'a row in progress has all its cells',
      );
      rows.cell?.checkInvariants();
    }
    if (_segments case final segments?) {
      check(
        segments.index == _item,
        'a paragraph in progress is not the next item',
      );
      check(
        segments.next < (_found[segments.item]?.starts.length ?? 0),
        'a paragraph in progress has no next segment found',
      );
      check(_rows == null, 'a table and a paragraph are both in progress');
    }
    if (_done) {
      check(_rows == null, 'a done run has a table in progress');
      check(_segments == null, 'a done run has a paragraph in progress');
      check(_item == _flow.length, 'a done run has items left');
      check(_pending.isEmpty, 'a done run has slices left');
    }
  }

  /// Lets go of the paragraphs that no published page shows. Published
  /// pages stay until their own [LaidPage.dispose].
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final piece in _held) {
      piece._release();
    }
    _held.clear();
    _pendingMarker?.$1.dispose();
    _pendingMarker = null;
    _rows?.release();
  }

  // Starting.

  /// Sets the run up to start at [start]: rebuilds the blocks open there
  /// and the list marker that waits for its line.
  void _resume(PageStart start) {
    final flow = _flow;
    final open = <int>[];
    int? marker;
    // The blocks that held the marker's block when it opened.
    var markerParents = const <int>[];
    var sliceBefore = false;
    for (var index = 0; index < start.item; index++) {
      switch (flow[index]) {
        case final BlockStart block:
          if (block.marker != null) {
            marker = index;
            markerParents = List.of(open);
          }
          open.add(index);
          if (index + 1 < flow.length &&
              flow[index + 1] is BlockEnd &&
              block.padding[0] +
                      block.border[0] +
                      block.padding[2] +
                      block.border[2] >
                  0) {
            sliceBefore = true;
          }
        case BlockEnd():
          open.removeLast();
        case ParagraphItem() || ImageItem() || TableItem() || SkippedItem():
          sliceBefore = true;
          marker = null;
      }
    }
    final atItemStart = start.line == 0 && start.part == 0;
    if (!sliceBefore && atItemStart) return;
    _from = start;
    _pageStart = start;
    _item = start.item;
    _firstLine = start.line;
    _firstPart = start.part;
    _dropMargins = true;
    // Each block is placed in the content box of the block that holds it.
    final placed = <int, (double, double)>{};
    (double, double) contentBox(List<int> chain) {
      var box = _root;
      for (final index in chain) {
        final block = flow[index] as BlockStart;
        final (left, width) = placed[index] ??= _placeBlock(block, index, box);
        box = (left + block.border[3] + block.padding[3], width);
      }
      return box;
    }

    contentBox(open);
    for (final index in open) {
      final block = flow[index] as BlockStart;
      final (left, contentWidth) = placed[index]!;
      final top = block.padding[0] + block.border[0];
      // The box's top edge is above the page. Its borders are clipped
      // there, so its exact place does not matter.
      _open.add(
        _OpenBlock(block, index, left, contentWidth, top > 0 ? -top : null, 0),
      );
    }
    // A marker waits for the first line of its item. Past that line, the
    // run from the section start already drew it.
    if (marker != null && atItemStart) {
      final block = flow[marker] as BlockStart;
      final (left, _) = contentBox([...markerParents, marker]);
      _marker(block.marker!.text, block.marker!.style, left);
    }
  }

  /// The left edge and the width of the block that holds the next box.
  (double, double) get _containing =>
      _open.isEmpty ? _root : (_open.last.contentLeft, _open.last.contentWidth);

  /// The left edge of the border box and the content width of [start],
  /// flow item [item], in the content box [containing].
  (double, double) _placeBlock(
    BlockStart start,
    int item,
    (double, double) containing,
  ) {
    final placement = start.placement;
    final (x, width) = containing;
    return placement.place(
      x,
      width,
      start.shrinkToFit
          ? _maxContent(item + 1, placement.available(width))
          : null,
    );
  }

  // Cutting pages.

  /// Lays out the next unit of work: a flow item, one row of a table, one
  /// segment of a long paragraph, or the measure of one row of a table
  /// whose column widths the next item needs.
  void _layOutItem() {
    final flow = _flow;
    if (_item == flow.length) return;
    if (_rows case final rows?) {
      _tableRow(rows);
      return;
    }
    if (_segments case final segments?) {
      _segment(segments);
      return;
    }
    // An item that needs the column widths of a table waits until each row
    // of the table is measured, one row in each unit of work.
    if (_unmeasuredTable() case final table?) {
      // Another run or a search can measure the table first.
      if (!identical(table, _measuringTable)) {
        _measuringTable = table;
        _measuring.clear();
      }
      _measureRow(table, _measuring);
      return;
    }
    final index = _item++;
    final line = _firstLine;
    final part = _firstPart;
    _firstLine = 0;
    _firstPart = 0;
    switch (flow[index]) {
      case final BlockStart start:
        _openBlock(start, index);
      case BlockEnd():
        _closeBlock(index);
      case final ParagraphItem paragraph:
        final (x, width) = _containing;
        _inline(paragraph, index, x, width, line);
      case final ImageItem image:
        _blockImage(image, index);
      case final TableItem table:
        if (_startTable(table, index, line, part) case final rows?) {
          _item = index;
          _tableRow(_rows = rows);
        }
      case SkippedItem():
        throw StateError('A run reached a flow item that its part skipped.');
    }
  }

  /// Publishes every page that the slices laid out so far decide, and lets
  /// go of the pieces that no later page can show.
  void _cut() {
    final published = _pages.length;
    _publishDecided();
    // NOTE: Once per flow item, not once per page, because the release reads
    // every pending slice: one long paragraph can leave thousands (t1-qtde).
    if (_pages.length > published) _releaseUnreachable();
  }

  void _publishDecided() {
    final atEnd = _item == _flow.length && _reachesEnd;
    while (!_done) {
      final count = _pending.length;
      final limit = _pageTop + _section.settings.height + fitTolerance;
      var end = 0;
      while (end < count && _pending[end].bottom <= limit) {
        end++;
      }
      if (end == count) {
        if (!atEnd) return;
        if (count == 0 && _pages.isNotEmpty) {
          _done = true;
          return;
        }
        _publish(
          count,
          count == 0 ? _pageTop : math.max(_pending.last.bottom, _pageTop),
          last: true,
        );
        return;
      }
      int next;
      double nextTop;
      if (end == 0) {
        // A slice taller than the page gets a page of its own.
        if (count == 1 && !atEnd) return;
        next = 1;
        nextTop = next < count ? _pending[next].top : _pending[0].bottom;
      } else {
        next = end;
        for (var candidate = end - 1; candidate > 0; candidate--) {
          if (_pending[candidate].appeal > _pending[next].appeal) {
            next = candidate;
          }
        }
        nextTop = _pending[next].top;
      }
      _publish(next, nextTop, last: atEnd && next == count);
    }
  }

  /// Publishes the page of the first [count] pending slices, which ends at
  /// [end], and starts the next page after it. The section's [last] page
  /// also holds the bottom padding and borders of the boxes that close
  /// after its last slice, so it ends at the run's strip position if that
  /// is lower.
  void _publish(int count, double end, {required bool last}) {
    final bottom = last ? math.max(end, _y) : end;
    assert(count <= _pending.length && bottom >= _pageTop);
    final width = _section.settings.width;
    final window = ui.Rect.fromLTRB(0, _pageTop, width, bottom);
    final decorations = [
      for (final decoration in _decorations)
        if (_shows(decoration, window)) decoration,
      // A box still open runs past the page's end, so the page shows its
      // top and side borders.
      for (final block in _open)
        if (block.boxTop case final boxTop?)
          for (final rule in _borders(block, boxTop, bottom, closed: false))
            if (rule.rect.overlaps(window)) rule,
    ];
    final page = LaidPage._(
      _section,
      _pageStart,
      _pageTop,
      bottom,
      List.unmodifiable(_pending.take(count)),
      List.unmodifiable(decorations),
      last,
      _pages.isEmpty ? _visibleAtStart() : _pages.last.endVisible,
    );
    _pages.add(page);
    _pending.removeRange(0, count);
    _pageTop = bottom;
    if (_pending.isNotEmpty) _pageStart = _pending.first.at;
    _decorations.removeWhere(
      (decoration) => switch (decoration) {
        RuleDecoration(:final rect) ||
        ImageDecoration(:final rect) => rect.bottom <= bottom,
        MarkerDecoration(:final offset) => offset.dy < bottom,
      },
    );
    if (last) _done = true;
  }

  static bool _shows(Decoration decoration, ui.Rect window) =>
      switch (decoration) {
        RuleDecoration(:final rect) ||
        ImageDecoration(:final rect) => rect.overlaps(window),
        MarkerDecoration(:final offset) =>
          offset.dy >= window.top && offset.dy < window.bottom,
      };

  /// Lets go of the pieces that no page after the published ones can show.
  void _releaseUnreachable() {
    final reachable = <Piece>{
      for (final slice in _pending)
        for (final line in [slice, ...slice.cellSlices]) ?line.piece,
      for (final line in _segments?.waiting ?? const <_Line>[]) line.piece,
      for (final decoration in _decorations)
        if (decoration is MarkerDecoration) decoration.piece,
    };
    _held.removeWhere((piece) {
      if (reachable.contains(piece)) return false;
      piece._release();
      return true;
    });
  }

  /// The visible characters before the run's first page, for a first page
  /// that shows no place: those before the first place at or after the
  /// run's start.
  int _visibleAtStart() {
    final flow = _flow;
    for (var index = _from.item; index < flow.length; index++) {
      final place = switch (flow[index]) {
        // A run that starts at a row of a table shows no row above it.
        TableItem(:final rows) when index == _from.item =>
          rows
              .skip(_from.line)
              .map((row) => _firstPlaceOfRow(_section.index, row))
              .nonNulls
              .firstOrNull,
        final item => _firstPlace(_section.index, item),
      };
      if (place != null) return _section.dom.visibleBefore(place);
    }
    return _section.dom.visibleLength;
  }

  // Block layout.

  void _margin(double value) {
    if (value > 0) _positive = math.max(_positive, value);
    if (value < 0) _negative = math.min(_negative, value);
  }

  void _resolveMargin() {
    if (!_dropMargins) _y += _positive + _negative;
    _positive = 0;
    _negative = 0;
  }

  Slice _add(
    double top,
    double bottom,
    int appeal,
    PageStart at, {
    Piece? piece,
    int line = -1,
    EpubPlace? start,
    (int, int) units = (0, 0),
    List<Slice> cellSlices = const [],
  }) {
    var finalAppeal = appeal;
    if (_avoidNext) {
      finalAppeal = math.min(finalAppeal, Appeal.violatingAvoid);
      _avoidNext = false;
    }
    // A break inside a box that avoids one, after the box's first slice.
    for (final block in _open) {
      if (block.start.avoidBreakInside && _added > block.firstSlice) {
        finalAppeal = math.min(finalAppeal, Appeal.violatingAvoid);
        break;
      }
    }
    if (_dropMargins) {
      _dropMargins = false;
      _pageTop = top;
    }
    final slice = Slice(
      top,
      bottom,
      finalAppeal,
      at,
      piece: piece,
      line: line,
      start: start,
      units: units,
      cellSlices: cellSlices,
    );
    _pending.add(slice);
    _added++;
    return slice;
  }

  void _openBlock(BlockStart start, int item) {
    final (left, contentWidth) = _placeBlock(start, item, _containing);
    _margin(start.marginTop);
    final top = start.padding[0] + start.border[0];
    double? boxTop;
    if (top > 0) {
      _resolveMargin();
      boxTop = _y;
      _y += top;
    }
    final block = _OpenBlock(start, item, left, contentWidth, boxTop, _added);
    _open.add(block);
    if (start.marker case final marker?) {
      _marker(marker.text, marker.style, block.contentLeft);
    }
    if (start.avoidBreakBefore) _avoidNext = true;
  }

  void _closeBlock(int item) {
    final block = _open.removeLast();
    final start = block.start;
    final bottom = start.padding[2] + start.border[2];
    var boxTop = block.boxTop;
    if (bottom > 0 || boxTop != null) {
      _resolveMargin();
      boxTop ??= _y;
      _y += bottom;
    }
    // A box without content ends right after it starts. With a height,
    // such as a rule, it is one slice.
    if (item == block.item + 1 && boxTop != null && _y > boxTop) {
      _add(boxTop, _y, Appeal.perfect, PageStart(block.item, 0));
    }
    if (boxTop != null) {
      _decorations.addAll(_borders(block, boxTop, _y, closed: true));
    }
    _margin(start.marginBottom);
    if (start.avoidBreakAfter) _avoidNext = true;
  }

  /// The border rules of [block], whose border box runs from [top] to
  /// [bottom] on the strip. A box that is not [closed] yet has no bottom
  /// border there.
  List<RuleDecoration> _borders(
    _OpenBlock block,
    double top,
    double bottom, {
    required bool closed,
  }) => _rules(
    ui.Rect.fromLTRB(
      block.left,
      top,
      block.left + block.contentWidth + block.start.placement.horizontal,
      bottom,
    ),
    block.start.border,
    bottom: closed,
  );

  /// The rules of a border box [rect] whose borders are [border] pixels
  /// wide, from top to left. Without [top] or [bottom], the box has no top
  /// or bottom border there, as at a page break.
  static List<RuleDecoration> _rules(
    ui.Rect rect,
    List<double> border, {
    bool top = true,
    bool bottom = true,
  }) {
    return [
      if (top && border[0] > 0)
        RuleDecoration(
          ui.Rect.fromLTWH(rect.left, rect.top, rect.width, border[0]),
        ),
      if (bottom && border[2] > 0)
        RuleDecoration(
          ui.Rect.fromLTWH(
            rect.left,
            rect.bottom - border[2],
            rect.width,
            border[2],
          ),
        ),
      if (border[3] > 0)
        RuleDecoration(
          ui.Rect.fromLTWH(rect.left, rect.top, border[3], rect.height),
        ),
      if (border[1] > 0)
        RuleDecoration(
          ui.Rect.fromLTWH(
            rect.right - border[1],
            rect.top,
            border[1],
            rect.height,
          ),
        ),
    ];
  }

  void _marker(String text, int style, double contentLeft) {
    final builder = _Recorder(_textStyles, ui.ParagraphStyle())
      ..addRun(style, text);
    final paragraph = builder.build()
      ..layout(const ui.ParagraphConstraints(width: double.infinity));
    // The marker sits left of the first line, on its baseline: the first
    // line's top is not known yet, so the offset is fixed on the next
    // slice.
    _pendingMarker?.$1.dispose();
    _pendingMarker = (paragraph, contentLeft - paragraph.maxIntrinsicWidth);
  }

  /// The width of the widest line of the paragraphs from flow item [from]
  /// on, laid out [available] pixels wide, rounded up. For a table, the
  /// table's widest content width.
  double _maxContent(int from, double available) {
    final flow = _flow;
    if (flow[from] case final TableItem table) {
      return gridMaxContent(_extentsOf(table), table.spacing.$1).ceilToDouble();
    }
    var widest = 0.0;
    for (var index = from; flow[index] is ParagraphItem; index++) {
      final built = _build((flow[index] as ParagraphItem).text, 0, available);
      built.paragraph.layout(
        const ui.ParagraphConstraints(width: double.infinity),
      );
      widest = math.max(widest, built.paragraph.maxIntrinsicWidth);
      built.dispose();
    }
    return widest.ceilToDouble();
  }

  void _blockImage(ImageItem image, int item) {
    final (x, width) = _containing;
    final (imageWidth, imageHeight) = image.sizing.sizeIn(width);
    final left = image.centered
        ? x + (width - imageWidth) / 2
        : x + image.marginLeft;
    _margin(image.marginTop);
    _resolveMargin();
    final rect = ui.Rect.fromLTWH(left, _y, imageWidth, imageHeight);
    _decorations.add(ImageDecoration(rect, image.image));
    final slice = _add(
      _y,
      _y + imageHeight,
      Appeal.perfect,
      PageStart(item, 0),
      start: EpubPlace(_section.index, image.node, 0),
    );
    _takeMarker(slice);
    _y += imageHeight;
    _margin(image.marginBottom);
  }

  // Tables.

  /// The narrowest and the widest content width of each cell of a table
  /// item, once measured. A table item belongs to one prepared section,
  /// whose fonts load before it lays out, so its cells measure the same in
  /// every run of the section.
  static final _measured = Expando<List<List<GridCell>>>('table extents');

  /// The rows of each table item whose widths came from kept measures
  /// ([reuseMeasures]) and that no run measured again yet.
  static final _unchecked = Expando<Set<int>>('kept table rows');

  /// Measures row [row] of [table] again when its widths came from kept
  /// measures that no run checked yet, and notes when they disagree. A row
  /// costs about what its layout costs, once per prepared section.
  void _check(TableItem table, int row) {
    if (_unchecked[table]?.remove(row) != true) return;
    final kept = _measured[table]![row];
    for (final (column, cell) in table.rows[row].indexed) {
      if (_extent(cell, table.width) != kept[column]) _contradicted = true;
    }
  }

  /// Starts [table], flow item [index], at its row [row], from fragment
  /// [part] of that row, or returns null when the table has no such row. A
  /// run that starts inside the table lays out no row above it: row [row]
  /// starts at the current strip position.
  _Rows? _startTable(TableItem table, int index, int row, int part) {
    _resolveMargin();
    // From the table's start, the grid's top spacing comes first.
    if (row == 0 && part == 0) _y += table.spacing.$2;
    if (row >= table.rows.length) return null;
    final (left, width) = _containing;
    return _Rows(
      table,
      index,
      left,
      columnWidths(_extentsOf(table), width, table.spacing.$1),
      row,
      part,
    );
  }

  /// The table that the next flow item needs measured, or null when it
  /// needs none or the table is measured: the next item when it is a
  /// table, or the table that starts the shrink-to-fit box that it opens.
  TableItem? _unmeasuredTable() {
    final flow = _flow;
    final table = switch (flow[_item]) {
      final TableItem table => table,
      BlockStart(shrinkToFit: true) when _item + 1 < flow.length =>
        switch (flow[_item + 1]) {
          final TableItem table => table,
          _ => null,
        },
      _ => null,
    };
    return table != null && _measured[table] == null ? table : null;
  }

  /// Measures the next row of [table] that [measured] lacks. Returns the
  /// extents of every cell of the table once every row is measured, and
  /// keeps them for the other runs of the section; null until then.
  List<List<GridCell>>? _measureRow(
    TableItem table,
    List<List<GridCell>> measured,
  ) {
    if (measured.length < table.rows.length) {
      measured.add([
        for (final cell in table.rows[measured.length])
          _extent(cell, table.width),
      ]);
    }
    if (measured.length < table.rows.length) return null;
    return _measured[table] = List.unmodifiable(measured);
  }

  /// Lays out the next flow item of a cell of the next row of [rows], or
  /// one segment of a long paragraph. Once each cell is laid out, adds the
  /// row's slices at the current strip position, from the row's fragment
  /// [_Rows.part] on: one slice, or one for each fragment of a row taller
  /// than a page. A row's fragments need the content of all its cells, so
  /// [rows] keeps the cells laid out until the row is done (tb-i6wg).
  void _tableRow(_Rows rows) {
    final table = rows.table;
    final number = rows.row;
    final row = table.rows[number];
    final (across, down) = table.spacing;
    final x = rows.left;
    if (rows.cells.isEmpty && rows.cell == null) _check(table, number);
    final boxes = cellBoxes(
      [for (final cell in row) cell.colspan],
      rows.widths,
      across,
    );
    // The content of each cell laid out at strip position 0, one flow item
    // in each unit of work, or one segment of a long paragraph.
    var laid = false;
    while (rows.cells.length < row.length) {
      final column = rows.cells.length;
      final run = rows.cell ??= () {
        final cell = row[column];
        final (left, cellWidth) = boxes[column];
        final start = cell.padding[3] + cell.border[3];
        final right = cell.padding[1] + cell.border[1];
        return LayoutRun._cell(
          this,
          cell.flow,
          x + left + start,
          math.max(0, cellWidth - start - right),
        );
      }();
      if (run._item < run._flow.length) {
        if (laid) return;
        run._layOutItem();
        laid = true;
        continue;
      }
      rows.cells.add(_cellContent(run));
      rows.cell = null;
    }
    // Each cell's box, its left edge and width, and its content.
    final cells = [
      for (final (column, cell) in row.indexed)
        (x + boxes[column].$1, boxes[column].$2, cell, rows.cells[column]),
    ];
    rows.cells.clear();
    final fragments = rowFragments([
      for (final (_, _, cell, content) in cells)
        () {
          final top = cell.padding[0] + cell.border[0];
          return (
            slices: [
              for (final slice in content.slices)
                (top + slice.top, top + slice.bottom),
            ],
            height: top + content.height + cell.padding[2] + cell.border[2],
            align: cell.align,
          );
        }(),
    ], _section.settings.height);
    var top = _y;
    for (var part = rows.part; part < fragments.length; part++) {
      final fragment = fragments[part];
      final shown = <Slice>[];
      for (final (column, (left, cellWidth, cell, content)) in cells.indexed) {
        final (from: first, :to, :offset, top: band, bottom: end) =
            fragment.cells[column];
        final inset = cell.padding[0] + cell.border[0];
        final moved = content.show(
          first,
          to,
          top + offset + inset,
          band - inset,
          end - inset,
        );
        shown.addAll(moved.slices);
        _held.addAll(moved.held);
        // A cell's box is as tall as its row. A row split between pages has
        // no top border after its first page and no bottom border before
        // its last.
        _decorations
          ..addAll(
            _rules(
              ui.Rect.fromLTWH(left, top, cellWidth, fragment.height),
              cell.border,
              top: part == 0,
              bottom: part == fragments.length - 1,
            ),
          )
          ..addAll(moved.decorations);
      }
      final added = _add(
        top,
        top + fragment.height,
        Appeal.perfect,
        PageStart(rows.item, number, part),
        start: shown.map((line) => line.start).nonNulls.firstOrNull,
        cellSlices: shown,
      );
      if (number == 0 && part == 0) _takeMarker(added);
      top += fragment.height;
    }
    for (final (_, _, _, content) in cells) {
      content.release();
    }
    _y = top + down;
    rows.row++;
    rows.part = 0;
    if (rows.row >= table.rows.length) {
      _rows = null;
      _item = rows.item + 1;
    }
  }

  /// The narrowest and the widest content width of each cell of [table],
  /// measured once per table item.
  List<List<GridCell>> _extentsOf(TableItem table) =>
      _measured[table] ??= List.unmodifiable([
        for (final row in table.rows)
          [for (final cell in row) _extent(cell, table.width)],
      ]);

  /// The narrowest and the widest content width of [cell], whose lengths
  /// resolve against [width]: those of its widest paragraph or image, with
  /// the margins, padding and borders of the boxes around it.
  GridCell _extent(TableCell cell, double width) {
    measuredCells++;
    var min = 0.0;
    var max = 0.0;
    var around =
        cell.padding[1] + cell.padding[3] + cell.border[1] + cell.border[3];
    final outer = <double>[];
    for (final item in cell.flow) {
      switch (item) {
        case BlockStart(:final placement):
          outer.add(around);
          around +=
              placement.marginLeft +
              placement.marginRight +
              placement.horizontal;
        case BlockEnd():
          around = outer.removeLast();
        case ParagraphItem(:final text, :final indent):
          final built = _build(text, math.max(0, indent.resolve(width)), width);
          built.paragraph.layout(
            const ui.ParagraphConstraints(width: double.infinity),
          );
          min = math.max(min, around + built.paragraph.minIntrinsicWidth);
          max = math.max(max, around + built.paragraph.maxIntrinsicWidth);
          built.dispose();
        case ImageItem(:final sizing, :final marginLeft):
          final (imageWidth, _) = sizing.sizeIn(width);
          min = math.max(min, around + marginLeft + imageWidth);
          max = math.max(max, around + marginLeft + imageWidth);
        case TableItem() || SkippedItem():
          // A table inside a cell is plain blocks, and a cell skips nothing.
          break;
      }
    }
    // Rounded up, so that a paragraph laid out at its widest width keeps
    // its lines.
    return (
      span: cell.colspan,
      min: min.ceilToDouble(),
      max: max.ceilToDouble(),
    );
  }

  /// The content of a table cell that [run], a run of the cell's flow,
  /// laid out to its end. The content takes over the paragraphs that it
  /// shows, and the paragraphs that show nothing are let go.
  static _Cell _cellContent(LayoutRun run) {
    // A cell holds the margins of its content.
    run._resolveMargin();
    run._pendingMarker?.$1.dispose();
    final lines = <Piece>[];
    for (final slice in run._pending) {
      final piece = slice.piece;
      if (piece != null && (lines.isEmpty || !identical(lines.last, piece))) {
        lines.add(piece);
      }
    }
    final markers = [
      for (final decoration in run._decorations)
        if (decoration is MarkerDecoration) decoration.piece,
    ];
    // A paragraph without lines shows nothing.
    for (final piece in run._held) {
      if (!lines.contains(piece) && !markers.contains(piece)) piece._release();
    }
    return _Cell(run._pending, lines, markers, run._decorations, run._y);
  }

  void _takeMarker(Slice slice) {
    final marker = _pendingMarker;
    if (marker == null) return;
    _pendingMarker = null;
    final (paragraph, x) = marker;
    final metrics = paragraph.computeLineMetrics();
    var baseline = slice.top;
    final piece = slice.piece;
    if (piece != null) {
      final lines = piece.paragraph.computeLineMetrics();
      if (slice.line < lines.length) {
        baseline =
            piece.y + lines[slice.line].baseline + piece.shifts[slice.line];
      }
    }
    final held = Piece(
      paragraph,
      x,
      baseline - (metrics.isEmpty ? 0 : metrics.first.baseline),
      TextMap(_section.index),
    );
    _held.add(held);
    _decorations.add(MarkerDecoration(held));
  }

  // Paragraphs.

  static ui.TextStyle _textStyle(RunStyle style, ui.Color ink) =>
      runTextStyle(style, ink);

  ui.ParagraphStyle _paragraphStyle(StyledText text) =>
      blockParagraphStyle(_section.styles[text.style], text.align);

  /// A builder of the paragraph of [text], which records its calls.
  _Recorder _builder(StyledText text) => _Recorder(
    _textStyles,
    _paragraphStyle(text),
    block: (text.style, text.align),
  );

  /// Builds the paragraph of [text], [width] pixels wide, or only that
  /// paragraph's code units [start, end). Returns the paragraph, its map,
  /// what each of its placeholders holds (null for the indent, an image's
  /// path, or a raised paragraph) and its soft hyphens. [marks] replaces
  /// the soft hyphen at a code unit of the whole paragraph with another
  /// code unit.
  ///
  /// A part that starts at a line start and ends at a cut ([_cutAfter])
  /// has the whole paragraph's lines, but its last line.
  _Built _build(
    StyledText text,
    double indent,
    double width, {
    int start = 0,
    int? end,
    Map<int, int> marks = const {},
  }) {
    final builder = _builder(text);
    final map = TextMap(_section.index);
    final inlines = <Object?>[];
    final softHyphens = <int>[];
    final texts = <_Text>[];
    final stop = end ?? _unbounded;
    // The code units of the whole paragraph read so far.
    var whole = 0;
    if (indent > 0) {
      if (start == 0) {
        builder.addPlaceholder(indent, 0, 0);
        map.addPlaceholder(-1);
        inlines.add(null);
      }
      whole = 1;
    }

    /// Whether the code unit [at] of the whole paragraph is in the part.
    bool shown(int at) => at >= start && at < stop;
    for (final run in text.runs) {
      switch (run) {
        case TextRun(text: final written, :final style, :final node):
          // The run's code units are the whole paragraph's [at, whole).
          final at = whole;
          whole += written.length;
          if (whole <= start || at >= stop) continue;
          final low = math.max(0, start - at);
          final high = math.min(written.length, stop - at);
          final added = written.substring(low, high);
          final local = map.length;
          final offset = start + local;
          var marked = false;
          for (
            var at = added.indexOf(_softHyphen);
            at >= 0;
            at = added.indexOf(_softHyphen, at + 1)
          ) {
            softHyphens.add(local + at);
            marked |= marks.containsKey(offset + at);
          }
          final drawn = marked
              ? String.fromCharCodes([
                  for (var at = 0; at < added.length; at++)
                    marks[offset + at] ?? added.codeUnitAt(at),
                ])
              : added;
          texts.add((start: local, text: drawn, style: style));
          builder.addRun(style, drawn);
          map.addText(node, Int32List.sublistView(run.offsets, low, high));
        case BreakRun(:final node):
          if (!shown(whole++)) continue;
          builder.addText('\n');
          map.addPlaceholder(node);
        case ImageRun(:final node, :final image, :final sizing):
          if (!shown(whole++)) continue;
          final (imageWidth, imageHeight) = sizing.sizeIn(width);
          builder.addPlaceholder(imageWidth, imageHeight, imageHeight);
          map.addPlaceholder(node);
          inlines.add(image);
        case RaisedRun(:final node, text: final inner, :final shift):
          if (!shown(whole++)) continue;
          final raised = _build(inner, 0, width).paragraph
            ..layout(const ui.ParagraphConstraints(width: double.infinity));
          final lines = raised.computeLineMetrics();
          final baseline = lines.isEmpty ? 0.0 : lines.first.baseline;
          builder.addPlaceholder(
            raised.maxIntrinsicWidth,
            raised.height,
            baseline + shift,
          );
          map.addPlaceholder(node);
          inlines.add(raised);
      }
    }
    return _Built(
      builder.build(),
      map,
      inlines,
      softHyphens,
      texts,
      start: start,
      length: whole,
    );
  }

  /// An end past every paragraph's last code unit.
  static const _unbounded = 1 << 52;

  static final _softHyphen = String.fromCharCode(softHyphen);

  /// The hyphen that ends a line inside a word, which Chromium draws when
  /// the font has it.
  static const _hyphen = 0x2010;

  /// A word joiner: no line break, and nothing drawn.
  static const _joiner = 0x2060;

  /// The paragraph of [text], or its part of code units [start, end) that
  /// starts at a line start and ends at a cut, laid out [width] pixels
  /// wide, with a hyphen at the end of each line that ends inside a word.
  ///
  /// Flutter breaks a line at a soft hyphen, but draws no hyphen there. So
  /// each soft hyphen that ends a line becomes a hyphen, and the paragraph
  /// is laid out again. The line then holds its hyphen, as in Chromium: a
  /// justified line ends at it. As in Chromium, the hyphen must fit in the
  /// line. A soft hyphen whose hyphen would not fit becomes a word joiner,
  /// so its line breaks earlier, and the lines after it are hyphenated
  /// again.
  ///
  /// A line breaks at the last place where its text fits, so its break
  /// depends only on where it starts. So the line ends are marked from the
  /// top a part at a time: a part of a few lines, built from a line's start
  /// ([_markLines]). A word joiner then lays out a few lines again, not the
  /// whole paragraph (tb-a6zd). Then the whole paragraph is laid out with
  /// the marks, and again until no mark changes. A part measures its lines
  /// with less float error than the whole paragraph, because its glyphs sit
  /// nearer its start, so a line at the very limit of the width can break
  /// differently in the two.
  _Built _layOut(
    StyledText text,
    double indent,
    double width, {
    int start = 0,
    int? end,
  }) {
    final constraints = ui.ParagraphConstraints(width: width);
    final marks = <int, int>{};
    _Built layOut(int first, int? stop) {
      final built = _build(
        text,
        indent,
        width,
        start: first,
        end: stop,
        marks: marks,
      );
      built.paragraph.layout(constraints);
      laidOutUnits += built.map.length;
      return built;
    }

    if (!_hyphenated(text)) return layOut(start, end);
    // Marks the line ends a part at a time from the line that starts at
    // code unit [next] on, and returns the whole paragraph laid out with
    // the marks: a part that starts at the paragraph's start and reaches
    // its end is the whole paragraph. With no [next], it lays out the whole
    // paragraph.
    _Built byParts(int? next) {
      if (next == null) return layOut(start, end);
      var span = _part;
      while (true) {
        // A part ends at a cut, so that its lines but the last are the
        // paragraph's.
        final cut = _cutAfter(text, indent, next! + span);
        final part = layOut(
          next,
          end != null && (cut == null || cut > end) ? end : cut,
        );
        final last = part.reaches(end);
        if (next == start && last) return part;
        final count = marks.length;
        final after = _markLines(part, marks, width, text: text, last: last);
        part.dispose();
        if (after == null) return layOut(start, end);
        // A part of one line leaves that line for a longer part.
        span = after == next && marks.length == count ? span * 2 : _part;
        next = after;
      }
    }

    // The whole paragraph is laid out with the marks until no mark changes.
    // Its lines can differ from a part's by float noise in their widths, as
    // can the judged widths: each hyphen must end its line, and each line
    // that ends at a soft hyphen gets its mark. A line that breaks again is
    // marked a part at a time from there. Each change makes the marks later
    // in one order (none, hyphen, joiner at the first code unit that
    // changes), so the loop ends.
    int? next = start;
    while (true) {
      final whole = byParts(next);
      next = _misjudged(whole, marks);
      if (next == null) {
        final count = marks.length;
        next = _markLines(whole, marks, width, text: text, last: true);
        if (marks.length == count) return whole;
      }
      whole.dispose();
    }
  }

  /// How many code units of a paragraph [_layOut] lays out at a time while
  /// it marks its line ends, at least: a few lines.
  static const _part = 256;

  /// The first cut of [text] at or after its code unit [at], or null when
  /// none comes before its end. Code units count as in [_build]: a
  /// paragraph whose first line is indented by [indent] has the indent as
  /// its first code unit.
  ///
  /// A cut is a place where a part of the paragraph that ends there and
  /// the whole paragraph can both break a line: after a hard break, before
  /// a word that follows a space, or between two ideographs. A line breaks
  /// at the last break that fits, and the line before the last line of a
  /// part that ends at a cut ends at a break before the cut. So that line
  /// breaks where it breaks in the whole paragraph, and the part's lines
  /// but its last are the paragraph's.
  ///
  /// A word after a space is no cut when an opening bracket or quote comes
  /// before the space: Unicode's line breaking rules (UAX 14, LB14 and
  /// LB15a) keep them on one line.
  static int? _cutAfter(StyledText text, double indent, int at) {
    final shift = indent > 0 ? 1 : 0;
    final starts = _runStarts(text);
    final length = starts.last;
    final runs = text.runs;
    // The run that holds code unit [unit] of the text, by its start.
    var run = 0;
    int codeUnit(int unit) {
      if (unit < starts[run] || unit >= starts[run + 1]) {
        var low = 0;
        var high = runs.length - 1;
        while (low < high) {
          final middle = (low + high + 1) >> 1;
          if (starts[middle] <= unit) {
            low = middle;
          } else {
            high = middle - 1;
          }
        }
        run = low;
      }
      return switch (runs[run]) {
        TextRun(text: final written) => written.codeUnitAt(unit - starts[run]),
        BreakRun() => 0x0a,
        ImageRun() || RaisedRun() => 0xfffc,
      };
    }

    // The last code unit before the spaces that end before [unit].
    int beforeSpaces(int unit) {
      var last = unit - 1;
      while (last > 0 && codeUnit(last) == 0x20) {
        last--;
      }
      return codeUnit(last);
    }

    for (var unit = math.max(1, at - shift); unit < length; unit++) {
      final before = codeUnit(unit - 1);
      final after = codeUnit(unit);
      final cut = switch (before) {
        0x0a => true,
        0x20 => _startsWord(after) && !_opens(beforeSpaces(unit)),
        _ => _ideograph(before) && _ideograph(after),
      };
      if (cut) return unit + shift;
    }
    return null;
  }

  /// Whether [unit] can start a word after a space: a Latin letter or a
  /// digit.
  static bool _startsWord(int unit) =>
      (unit >= 0x30 && unit <= 0x39) ||
      (unit >= 0x41 && unit <= 0x5a) ||
      (unit >= 0x61 && unit <= 0x7a) ||
      (unit >= 0xc0 && unit <= 0x24f && unit != 0xd7 && unit != 0xf7);

  /// Whether [unit] is a CJK ideograph.
  static bool _ideograph(int unit) =>
      (unit >= 0x3400 && unit <= 0x4dbf) ||
      (unit >= 0x4e00 && unit <= 0x9fff) ||
      (unit >= 0xf900 && unit <= 0xfaff);

  /// Whether [unit] is an opening bracket or quote, after which a line
  /// does not break, even after a space.
  static bool _opens(int unit) => _openers.contains(unit);

  static const _openers = {
    0x22, 0x27, 0x28, 0x5b, 0x7b, 0xa1, 0xab, 0xbf, // " ' ( [ { ¡ « ¿
    0x2018, 0x201a, 0x201b, 0x201c, 0x201e, 0x201f, 0x2039, // ‘ ‚ ‛ “ „ ‟ ‹
    0x3008, 0x300a, 0x300c, 0x300e, 0x3010, 0x3014, 0x3016, 0x3018, 0x301a,
    0x301d, 0xff08, 0xff3b, 0xff5b, // CJK brackets and quotes
  };

  /// The code unit of the text of [text] that each of its runs starts at,
  /// and the text's length, kept per text.
  static Int32List _runStarts(StyledText text) => _runStartsOf[text] ??= () {
    final starts = Int32List(text.runs.length + 1);
    var unit = 0;
    for (final (index, run) in text.runs.indexed) {
      starts[index] = unit;
      unit += run is TextRun ? run.text.length : 1;
    }
    starts[text.runs.length] = unit;
    return starts;
  }();

  static final _runStartsOf = Expando<Int32List>('run starts');

  /// Whether [text] holds a soft hyphen. Kept per text, because a long
  /// paragraph asks once for each segment.
  static bool _hyphenated(StyledText text) => _softHyphens[text] ??= text.runs
      .any((run) => run is TextRun && run.text.contains(_softHyphen));

  static final _softHyphens = Expando<bool>('soft hyphens');

  /// Marks the soft hyphens that end the lines of [part], a part of a
  /// paragraph laid out [width] pixels wide that starts at a line start, in
  /// [marks]. Returns where the first line whose end is not marked starts,
  /// or null when every line's end is marked.
  ///
  /// Each soft hyphen that ends a line becomes a hyphen when the hyphen
  /// fits in the line, and else a word joiner. The line of a word joiner
  /// breaks again, so marking stops there. A part that stops before the
  /// paragraph's end can break its last line early, so that line is left
  /// for the next part.
  int? _markLines(
    _Built part,
    Map<int, int> marks,
    double width, {
    required StyledText text,
    required bool last,
  }) {
    final justified = text.align == Align.justify;
    final paragraph = part.paragraph;
    final length = part.map.length;
    final metrics = paragraph.computeLineMetrics();
    final starts = _lineStarts(paragraph, length, metrics.length);
    // The end of each line before its hard break's newline.
    int end(int line) => line + 1 < starts.length
        ? starts[line + 1] - (metrics[line].hardBreak ? 1 : 0)
        : length;
    final marked = last ? starts.length : starts.length - 1;
    for (var line = 0; line < marked; line++) {
      final unit = end(line) - 1;
      final at = part.start + unit;
      if (last && unit + 1 >= length ||
          marks.containsKey(at) ||
          part.unitAt(unit) != softHyphen) {
        continue;
      }
      final natural = justified
          ? _naturalWidth(part, metrics[line], starts[line], unit)
          : metrics[line].width;
      final hyphen = _advances.hyphen(part.styleAt(unit), _textStyles);
      // A part's line counts the kerning of its last letter with the letter
      // after the soft hyphen, and the hyphen's width counts none of its
      // own. Each moved a hyphen across the line's end by up to a fifth of
      // its width in the corpus. Near the line's end, the line is measured
      // alone, as Chromium measures it, and with its hyphen, as the
      // paragraph with its marks draws it (tb-o242).
      var fits = natural + hyphen <= width + _fitTolerance;
      if ((natural + hyphen - width).abs() <= hyphen / 2) {
        // A line whose measure alone differs from its width in the
        // paragraph by more than kerning can, for example by a fallback
        // font that the paragraph picked otherwise for another script,
        // keeps the sum.
        if (_hyphenatedLine(text, part, starts[line], unit)
            case (:final alone, :final drawn)
            when (alone - natural).abs() <= hyphen / 2) {
          fits =
              alone + hyphen <= width + _fitTolerance &&
              drawn <= width + _fitTolerance;
        }
      }
      if (!fits) {
        marks[at] = _joiner;
        // The line breaks earlier, maybe at another soft hyphen.
        return part.start + starts[line];
      }
      marks[at] = _hyphen;
    }
    return last ? null : part.start + starts[marked];
  }

  /// The widths of the line of [part] from code unit [start] to its soft
  /// hyphen [end], from measures of the line alone: [alone] without the
  /// soft hyphen, and [drawn] to the right edge of a hyphen in its place,
  /// as the paragraph with its marks draws it. Null when the line holds a
  /// placeholder.
  ///
  /// Chromium shapes the line up to the soft hyphen without the letters
  /// after it, and the hyphen apart, so the line's width with its hyphen is
  /// [alone] plus the hyphen's width. The drawn hyphen kerns with the
  /// letters on both sides of it.
  ({double alone, double drawn})? _hyphenatedLine(
    StyledText text,
    _Built part,
    int start,
    int end,
  ) {
    // The paragraph's own style, whose font family picks the fallback
    // fonts of the line's other scripts.
    final line = ui.ParagraphBuilder(_paragraphStyle(text));
    final hyphenated = ui.ParagraphBuilder(_paragraphStyle(text));
    var unit = start;
    while (unit < end) {
      final piece = part._textAt(unit);
      if (piece == null) return null;
      final stop = math.min(end, piece.start + piece.text.length);
      final added = piece.text.substring(
        unit - piece.start,
        stop - piece.start,
      );
      for (final builder in [line, hyphenated]) {
        builder
          ..pushStyle(_textStyles[piece.style])
          ..addText(added)
          ..pop();
      }
      unit = stop;
    }
    hyphenated
      ..pushStyle(_textStyles[part.styleAt(end)])
      ..addText(String.fromCharCode(_hyphen))
      ..pop();
    if (part._textAt(end + 1) case final next?) {
      hyphenated
        ..pushStyle(_textStyles[next.style])
        ..addText(next.text[end + 1 - next.start])
        ..pop();
    }
    const unbounded = ui.ParagraphConstraints(width: double.infinity);
    final alone = line.build()..layout(unbounded);
    final drawn = hyphenated.build()..layout(unbounded);
    final boxes = drawn.getBoxesForRange(end - start, end - start + 1);
    final widths = boxes.isEmpty
        ? null
        : (alone: alone.maxIntrinsicWidth, drawn: boxes.last.right);
    alone.dispose();
    drawn.dispose();
    return widths;
  }

  /// Checks that each hyphen of [built], the whole paragraph laid out with
  /// [marks], ends its line. Returns null when each does.
  ///
  /// When one does not, its line's width with the hyphen was misjudged far
  /// from the line's end, or float noise broke its line otherwise in a
  /// part: it becomes a word
  /// joiner, and the marks after it are dropped, as they were decided for
  /// lines that are gone. Returns where the line before it starts: that
  /// line broke early, and breaks again.
  int? _misjudged(_Built built, Map<int, int> marks) {
    final paragraph = built.paragraph;
    final length = built.map.length;
    final metrics = paragraph.computeLineMetrics();
    int? lineOf(int unit) =>
        unit < length ? paragraph.getLineNumberAt(unit) : null;
    for (final unit in built.softHyphens) {
      final at = built.start + unit;
      if (marks[at] != _hyphen) continue;
      final line = paragraph.getLineNumberAt(unit)!;
      // A hard break's newline belongs to the line that it ends.
      final ends = line + 1 >= metrics.length
          ? unit + 1 == length
          : metrics[line].hardBreak
          ? lineOf(unit + 1) == line && lineOf(unit + 2) != line
          : lineOf(unit + 1) != line;
      if (ends) continue;
      marks[at] = _joiner;
      marks.removeWhere((other, mark) => other > at);
      return built.start +
          (line > 0 ? _lineStarts(paragraph, length, line).last : 0);
    }
    return null;
  }

  /// How far past the line width a hyphen may reach and still fit: float
  /// noise. A hyphen judged to fit that does not makes its line break
  /// earlier, and [_misjudged] then refuses it.
  static const _fitTolerance = 0.01;

  /// The width of [line], a justified line of [built] from code unit
  /// [start] to its soft hyphen [end], before Flutter justified it.
  ///
  /// Flutter widens each run of spaces between words by the same amount.
  /// One gap, measured against the space's own width, gives that amount.
  double _naturalWidth(_Built built, ui.LineMetrics line, int start, int end) {
    // The runs of spaces between words: their count, and the first one.
    var runs = 0;
    int? first;
    int? last;
    var inRun = false;
    for (var unit = start; unit < end; unit++) {
      if (built.unitAt(unit) == 0x20) {
        if (!inRun && unit > start) {
          runs++;
          first ??= unit;
        }
        inRun = true;
        if (runs == 1 && first != null) last = unit;
      } else {
        inRun = false;
      }
    }
    if (runs == 0 || first == null) return line.width;
    final paragraph = built.paragraph;
    final before = paragraph.getBoxesForRange(first - 1, first);
    final after = paragraph.getBoxesForRange(last! + 1, last + 2);
    if (before.isEmpty || after.isEmpty) return line.width;
    final gap = after.first.left - before.last.right;
    var natural = 0.0;
    for (var unit = first; unit <= last; unit++) {
      natural += _advances.space(built.styleAt(unit), _textStyles);
    }
    return line.width - runs * (gap - natural);
  }

  /// Lays out paragraph [item], flow item [index], at [x] and [width]
  /// pixels wide. A run that starts inside the paragraph lays out all of it
  /// and adds its lines from line [from] on, so that the orphans and widows
  /// rules see the whole paragraph.
  void _inline(
    ParagraphItem item,
    int index,
    double x,
    double width,
    int from,
  ) {
    final indent = item.indent.resolve(width);
    _resolveMargin();
    if (indent >= 0) {
      if (_long(item.text)) {
        _item = index;
        _segment(_segments = _Segments(item, index, x, width, indent, from));
        return;
      }
      final built = _layOut(item.text, indent, width);
      _place(built, x, item, index, from: from);
      return;
    }
    // A negative indent hangs the first line out to the left: lay it out
    // wider, then lay out the rest at the block's width.
    final first = _layOut(item.text, 0, width - indent);
    final count = first.paragraph.computeLineMetrics().length;
    if (count <= 1) {
      _place(first, x + indent, item, index, from: from);
      return;
    }
    final end = _lineStarts(first.paragraph, first.map.length, 2)[1];
    final rest = _layOut(item.text, 0, width, start: end);
    final total = 1 + rest.paragraph.computeLineMetrics().length;
    if (from == 0) {
      _place(first, x + indent, item, index, lines: 1, total: total);
    } else {
      first.dispose();
    }
    _place(
      rest,
      x,
      item,
      index,
      before: 1,
      total: total,
      from: math.max(0, from - 1),
    );
  }

  /// How many code units long a segment of a long paragraph is, at least:
  /// a few dozen lines of verse, or a dozen lines of prose.
  static const _segmentLength = 1024;

  /// Whether [text] is a long paragraph, which lays out in segments: a cut
  /// ([_cutAfter]) comes after its first [_segmentLength] code units.
  ///
  /// A segment is a part of the paragraph that starts at a line start and
  /// ends at the first cut at least [_segmentLength] code units after it,
  /// or at the paragraph's end. Its lines but its last are the paragraph's
  /// lines, so the next segment starts where its last line starts. A line
  /// breaks where it breaks in the whole paragraph but for float noise,
  /// which is smaller in a segment, because its glyphs sit nearer its
  /// start (tb-2l69, tb-3xvr).
  static bool _long(StyledText text) =>
      _cutAfter(text, 0, _segmentLength) != null;

  /// The segments of each long paragraph item that runs found so far. A
  /// paragraph item belongs to one prepared section and sits in one
  /// column, so its segments break the same lines in every run of the
  /// section.
  static final _found = Expando<_Segmentation>('segments');

  /// Lays out the next segment of [segments] and adds its lines from line
  /// [_Segments.from] on. A line waits until the lines after it decide its
  /// widows rule. A run that starts at a later line skips the segments
  /// that another run found, and finds the others.
  void _segment(_Segments segments) {
    final item = segments.item;
    final found = _found[item] ??= _Segmentation();
    if (segments.next == 0 && segments.from > 0) {
      var known = 0;
      while (known + 1 < found.lines.length &&
          found.lines[known + 1] <= segments.from) {
        known++;
      }
      segments
        ..next = known
        ..lines = found.lines[known];
    }
    final next = segments.next;
    final indent = segments.indent;
    // The indent is the paragraph's first code unit.
    final shift = indent > 0 ? 1 : 0;
    final start = next == 0 ? 0 : found.starts[next] + shift;
    int? end;
    _Built built;
    int lines;
    var span = _segmentLength;
    while (true) {
      end = _cutAfter(item.text, indent, start + span);
      built = _layOut(
        item.text,
        indent,
        segments.width,
        start: start,
        end: end,
      );
      lines = built.paragraph.computeLineMetrics().length;
      if (end == null || lines > 1) break;
      // A segment of one line leaves that line for a longer segment.
      built.dispose();
      span *= 2;
    }
    final last = end == null;
    // The last line of a segment that ends at a cut is the next segment's
    // first line. After a hard break it is empty.
    final count = last ? lines : lines - 1;
    final following = last
        ? built.map.length
        : _lineStart(built.paragraph, built.map.length, count);
    final before = segments.lines;
    // A segment that another run or a kept page map found already must end
    // where it ended then. When it does not, what this run found replaces
    // it and the segments after it.
    if (found.starts.length > next + 1 || found.complete) {
      final agrees = last
          ? found.starts.length == next + 1
          : found.starts.length > next + 1 &&
                found.starts[next + 1] == start + following - shift &&
                found.lines[next + 1] == before + count;
      if (!agrees) {
        _contradicted = true;
        found
          ..starts.length = next + 1
          ..lines.length = next + 1
          ..complete = false;
      }
    }
    if (last) {
      found.complete = true;
    } else if (found.starts.length == next + 1) {
      found.starts.add(start + following - shift);
      found.lines.add(before + count);
    }
    if (before + count <= segments.from) {
      built.dispose();
    } else {
      final (placed, _) = _lines(
        built,
        segments.x,
        item,
        lines: count,
        shows: following < built.map.length,
        before: before,
        from: math.max(0, segments.from - before),
      );
      segments.waiting.addAll(placed);
    }
    segments
      ..lines = before + count
      ..next = next + 1;
    // A line with enough lines after it is no widow.
    final waiting = segments.waiting;
    var ready = 0;
    while (ready < waiting.length &&
        (last || segments.lines - waiting[ready].above >= item.widows)) {
      ready++;
    }
    for (final line in waiting.take(ready)) {
      _addLine(line, item, segments.index, segments.lines);
    }
    waiting.removeRange(0, ready);
    if (last) {
      _segments = null;
      _item = segments.index + 1;
    }
  }

  /// Adds the lines of [built], drawn at [x], to the strip: all of them,
  /// or the first [lines], from its line [from] on, which sits at the
  /// current strip position. They are lines [before] on of a paragraph of
  /// [total] lines, for the orphans and widows rules of [item], flow item
  /// [index].
  void _place(
    _Built built,
    double x,
    ParagraphItem item,
    int index, {
    int? lines,
    int before = 0,
    int? total,
    int from = 0,
  }) {
    final (placed, count) = _lines(
      built,
      x,
      item,
      lines: lines,
      shows: lines != null,
      before: before,
      from: from,
    );
    for (final line in placed) {
      _addLine(line, item, index, total ?? before + count);
    }
  }

  /// Lays out the piece of [built], a part of paragraph [item] drawn at
  /// [x], with its line [from] at the current strip position, and moves the
  /// strip position past its first [lines] lines (all by default). Returns
  /// those lines from line [from] on, which are lines [before] on of the
  /// paragraph, and how many lines [built] has. The run holds the piece.
  /// When the piece [shows] only those lines, it is clipped below them.
  (List<_Line>, int) _lines(
    _Built built,
    double x,
    ParagraphItem item, {
    int? lines,
    bool shows = false,
    int before = 0,
    int from = 0,
  }) {
    final paragraph = built.paragraph;
    final metrics = paragraph.computeLineMetrics();
    final count = lines ?? metrics.length;
    // Chromium rounds the font's metrics for `line-height: normal`, so only
    // a CSS line height is fractional there.
    final exact = _section.styles[item.text.style].lineHeight != null;
    final paragraphs = _Paragraphs(paragraph, exact: exact);
    final tops = paragraphs.tops;
    final piece = Piece._of(paragraphs, x, _y - tops[from], built.map);
    _held.add(piece);
    final boxes = paragraph.getBoxesForPlaceholders();
    for (var slot = 0; slot < built.inlines.length; slot++) {
      final held = built.inlines[slot];
      if (held == null) continue;
      if (slot < boxes.length) {
        // A placeholder draws with the line that holds it.
        final rect = boxes[slot].toRect();
        var line = 0;
        while (line + 1 < metrics.length &&
            metrics[line].baseline + metrics[line].descent <= rect.center.dy) {
          line++;
        }
        final shift = line < metrics.length ? piece.shifts[line] : 0.0;
        piece.inlines.add((rect.shift(ui.Offset(0, shift)), held));
      } else if (held is ui.Paragraph) {
        held.dispose();
      }
    }
    final starts = _lineStarts(
      paragraph,
      built.map.length,
      math.min(count + 1, metrics.length),
    );
    final placed = [
      for (var line = from; line < count; line++)
        (
          piece: piece,
          line: line,
          top: piece.y + tops[line],
          bottom: piece.y + tops[line + 1],
          start: built.map.placeAtUnit(starts[line]),
          units: (
            starts[line],
            line + 1 < starts.length ? starts[line + 1] : built.map.length,
          ),
          above: before + line,
        ),
    ];
    if (shows) piece.shown = tops[count];
    _y = piece.y + tops[count];
    return (placed, metrics.length);
  }

  /// Adds [line] of paragraph [item], flow item [index], which has [all]
  /// lines, to the strip. With fewer lines after it than the widows rule
  /// asks for, [all] must be the paragraph's true count.
  void _addLine(_Line line, ParagraphItem item, int index, int all) {
    final above = line.above;
    // Chromium keeps the orphans rule first. It keeps the widows rule only
    // when the paragraph is long enough to keep both.
    final widows =
        all >= item.orphans + item.widows && all - above < item.widows;
    final appeal = above == 0
        ? Appeal.perfect
        : above < item.orphans || widows
        ? Appeal.violatingOrphansWidows
        : Appeal.perfect;
    final slice = _add(
      line.top,
      line.bottom,
      appeal,
      PageStart(index, above),
      piece: line.piece,
      line: line.line,
      start: line.start,
      units: line.units,
    );
    if (above == 0) _takeMarker(slice);
  }

  /// The first code unit of each of the first [count] lines of [paragraph],
  /// whose text is [length] code units long. A hard break's newline belongs
  /// to the line that it ends.
  ///
  /// It asks the engine only for the line of a code unit, which is a binary
  /// search over the lines. NOTE: Paragraph.getLineBoundary builds the
  /// metrics of every line on each call, so one call per line costs on the
  /// order of n squared for a paragraph of n lines (t1-qtde).
  static List<int> _lineStarts(ui.Paragraph paragraph, int length, int count) {
    final starts = <int>[];
    var start = 0;
    for (var line = 0; line < count; line++) {
      starts.add(start);
      // The next line starts at the first code unit after [start] that is
      // not on this line, or at the end. Gallop forward, then halve.
      bool onLine(int unit) =>
          unit < length && paragraph.getLineNumberAt(unit) == line;
      var low = start;
      var step = 1;
      while (onLine(low + step)) {
        low += step;
        step *= 2;
      }
      var high = math.min(low + step, length);
      while (high - low > 1) {
        final middle = (low + high) >> 1;
        if (onLine(middle)) {
          low = middle;
        } else {
          high = middle;
        }
      }
      start = high;
    }
    return starts;
  }

  /// The first code unit of line [line] of [paragraph], whose text is
  /// [length] code units long, or [length] when the line is the empty line
  /// after a hard break at the end.
  static int _lineStart(ui.Paragraph paragraph, int length, int line) {
    var low = 0;
    var high = length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (paragraph.getLineNumberAt(middle)! >= line) {
        high = middle;
      } else {
        low = middle + 1;
      }
    }
    return low;
  }
}

/// The measures of a section's flow items that a run from a page start
/// inside an item needs before it cuts its first page: the narrowest and
/// the widest content width of each cell of each table item, and the
/// segments of each long paragraph item.
class SectionMeasures {
  const SectionMeasures({this.tables = const {}, this.paragraphs = const {}});

  /// The cells of each table item, by its index in the flow: the narrowest
  /// and the widest content width of each cell in turn, cell by cell and
  /// row by row ([GridCell.min] and [GridCell.max]).
  final Map<int, Float64List> tables;

  /// The segments of each long paragraph item of more than one segment, by
  /// its index in the flow (see [LayoutRun._long]).
  final Map<int, Segments> paragraphs;

  @override
  bool operator ==(Object other) =>
      other is SectionMeasures &&
      other.tables.length == tables.length &&
      tables.entries.every(
        (entry) => _same(other.tables[entry.key], entry.value),
      ) &&
      other.paragraphs.length == paragraphs.length &&
      paragraphs.entries.every(
        (entry) =>
            _same(other.paragraphs[entry.key]?.starts, entry.value.starts) &&
            _same(other.paragraphs[entry.key]?.lines, entry.value.lines),
      );

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered([
      for (final MapEntry(:key, :value) in tables.entries)
        Object.hash(key, Object.hashAll(value)),
    ]),
    Object.hashAllUnordered([
      for (final MapEntry(:key, :value) in paragraphs.entries)
        Object.hash(key, Object.hashAll(value.starts)),
    ]),
  );

  @override
  String toString() =>
      'SectionMeasures(tables: $tables, paragraphs: $paragraphs)';
}

/// The segments of a long paragraph, in order: where each one starts, in
/// code units of the paragraph's text without its indent, and the
/// paragraph's lines before it. The first segment starts at 0 with 0
/// lines before it.
typedef Segments = ({List<int> starts, List<int> lines});

bool _same<T>(List<T>? a, List<T> b) {
  if (a == null || a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) return false;
  }
  return true;
}

/// The measures that runs of [section] found for its flow items so far: a
/// main run to the section end finds them all.
SectionMeasures measuresOf(PreparedSection section) => SectionMeasures(
  tables: {
    for (final (index, item) in section.flow.indexed)
      if (item is TableItem)
        if (LayoutRun._measured[item] case final rows?)
          index: Float64List.fromList([
            for (final row in rows)
              for (final cell in row) ...[cell.min, cell.max],
          ]),
  },
  paragraphs: {
    for (final (index, item) in section.flow.indexed)
      if (item is ParagraphItem)
        if (LayoutRun._found[item] case final found?
            when found.complete && found.starts.length > 1)
          index: (
            starts: List.unmodifiable(found.starts),
            lines: List.unmodifiable(found.lines),
          ),
  },
);

/// Gives the flow items of [section] the kept [measures], which an earlier
/// layout of the same section found ([measuresOf]), so that no run finds
/// them again. An item that a run measured already keeps its own. A part of
/// the section ([preparePart]) takes the measures of its own items only.
/// Returns false, and gives nothing, when [measures] do not fit the
/// section's items.
///
/// A run checks each kept table row and each kept segment that it lays
/// out ([LayoutRun.contradicted]). [forgetMeasures] takes the kept
/// measures back.
bool reuseMeasures(PreparedSection section, SectionMeasures measures) {
  final flow = section.flow;
  // A part of the section passes by the items that it skipped or left out
  // after its end.
  bool passedBy(int index) =>
      (index >= flow.length && !section.reachesEnd) ||
      (index >= 0 && index < flow.length && flow[index] is SkippedItem);
  for (final MapEntry(key: index, value: widths) in measures.tables.entries) {
    if (passedBy(index)) continue;
    if (index < 0 || index >= flow.length) return false;
    if (flow[index] case final TableItem table
        when widths.length ==
            2 * table.rows.fold(0, (count, row) => count + row.length)) {
      continue;
    }
    return false;
  }
  for (final MapEntry(key: index, value: (:starts, :lines))
      in measures.paragraphs.entries) {
    if (passedBy(index)) continue;
    if (index < 0 || index >= flow.length) return false;
    if (flow[index] case final ParagraphItem paragraph
        when LayoutRun._long(paragraph.text) &&
            starts.length == lines.length &&
            starts.length > 1 &&
            starts.first == 0 &&
            lines.first == 0) {
      // A segment starts after the one before it and holds at least one
      // line. The last one starts inside the text.
      final length = paragraph.text.runs.fold(
        0,
        (sum, run) => sum + (run is TextRun ? run.text.length : 1),
      );
      for (var at = 1; at < starts.length; at++) {
        if (starts[at] <= starts[at - 1] || lines[at] <= lines[at - 1]) {
          return false;
        }
      }
      if (starts.last >= length) return false;
      continue;
    }
    return false;
  }
  for (final MapEntry(key: index, value: widths) in measures.tables.entries) {
    if (passedBy(index)) continue;
    final table = flow[index] as TableItem;
    if (LayoutRun._measured[table] != null) continue;
    var at = 0;
    LayoutRun._measured[table] = List.unmodifiable([
      for (final row in table.rows)
        [
          for (final cell in row)
            (span: cell.colspan, min: widths[at++], max: widths[at++]),
        ],
    ]);
    LayoutRun._unchecked[table] = {
      for (var row = 0; row < table.rows.length; row++) row,
    };
  }
  for (final MapEntry(key: index, value: (:starts, :lines))
      in measures.paragraphs.entries) {
    if (passedBy(index)) continue;
    final paragraph = flow[index] as ParagraphItem;
    if (LayoutRun._found[paragraph] != null) continue;
    LayoutRun._found[paragraph] = _Segmentation()
      ..starts.addAll(starts.skip(1))
      ..lines.addAll(lines.skip(1))
      ..complete = true
      ..kept = true;
  }
  return true;
}

/// Takes back the kept measures that [reuseMeasures] gave [section], so
/// that runs find them again. Runs in progress must stop first.
void forgetMeasures(PreparedSection section) {
  for (final item in section.flow) {
    if (item is TableItem && LayoutRun._unchecked[item] != null) {
      LayoutRun._measured[item] = null;
      LayoutRun._unchecked[item] = null;
    } else if (item is ParagraphItem && LayoutRun._found[item]?.kept == true) {
      LayoutRun._found[item] = null;
    }
  }
}

/// The page start of the line that holds [place], a place in [section]
/// (see [_holder]). It lays out the paragraph or the table row of the
/// place, and the next one when the place is in white space after it. A
/// table needs each row measured for its column widths first, once per
/// table item: [LineSearch] does that in steps.
PageStart lineStart(PreparedSection section, EpubPlace place) =>
    (LineSearch(section, place)..step(const Duration(days: 1))).found!;

/// The page start of the line that holds [place], by the rule of
/// [lineStart], found among the true pages of its section with no line
/// search: [starts] are the section's true page starts, and [firsts] the
/// first place of each page ([LaidPage.startPlace]). [pageAt] gives the
/// true page of an index of [starts], or null to stop the search, and then
/// the search gives null.
///
/// A binary search over [firsts] finds the first page to look at. When
/// [place] lies after everything that it shows, a later page holds it. The
/// pages that show the fragments of one table row taller than a page are
/// looked at together, because their lines interleave: a later cell of the
/// row shows on the row's first page, while its first cell goes on over the
/// next pages.
Future<PageStart?> keptLineStart(
  DomSection dom,
  List<PageStart> starts,
  List<EpubPlace?> firsts,
  EpubPlace place,
  Future<LaidPage?> Function(int index) pageAt,
) async {
  // The line that shows the last thing before [place], when [place] lies
  // after everything that every page from the first one shows.
  PageStart? last;
  var at = _firstPageFor(dom, firsts, place);
  while (at < starts.length) {
    var first = at;
    while (first > 0 && starts[first].part > 0) {
      first--;
    }
    var end = at + 1;
    while (end < starts.length && starts[end].part > 0) {
      end++;
    }
    final lines = <(Slice, Slice)>[];
    for (var index = first; index < end; index++) {
      final page = await pageAt(index);
      if (page == null) return null;
      for (final slice in page.slices) {
        for (final line in _lines(slice)) {
          lines.add((line, slice));
        }
      }
    }
    final (:holder, :past) = _holder(dom, place, lines);
    if (holder != null) {
      if (!past) return holder.at;
      last = holder.at;
    }
    at = end;
  }
  return last ?? starts.first;
}

/// The index of the page to look at first for the page that holds [place],
/// a place of the section of [dom], among the pages whose first places are
/// [firsts], in order: the last page whose first place is at or before
/// [place] in document order, or 0. A page with no first place counts as
/// starting at the next first place, so that a search passes it by.
int _firstPageFor(DomSection dom, List<EpubPlace?> firsts, EpubPlace place) {
  final key = _order(dom, place);
  bool atOrBefore(int index) {
    for (var at = index; at < firsts.length; at++) {
      if (firsts[at] case final first?) {
        return _compare(_order(dom, first), key) <= 0;
      }
    }
    return false;
  }

  var low = 0;
  var high = firsts.length - 1;
  while (low < high) {
    final middle = (low + high + 1) >> 1;
    if (atOrBefore(middle)) {
      low = middle;
    } else {
      high = middle - 1;
    }
  }
  return low;
}

/// The search of [lineStart] in steps, so that frames go on while it
/// measures the column widths of a long table, or counts the lines of the
/// segments of a long paragraph before the place.
///
/// It holds no paragraph between steps, so a search that stops before it
/// finds its start needs no disposal.
class LineSearch {
  /// A search for the page start of the line that holds [place], a place in
  /// [section].
  LineSearch(PreparedSection section, EpubPlace place)
    : _section = section,
      _place = place {
    if (place.section != section.index) {
      throw ArgumentError.value(place, 'place', 'is not in this section');
    }
  }

  final PreparedSection _section;
  final EpubPlace _place;

  /// The rows of the place's table measured so far.
  final _rows = <List<GridCell>>[];

  /// The page start, once a step found it.
  PageStart? get found => _found;
  PageStart? _found;

  /// Whether the section is a part of a section that cannot tell the line:
  /// no item of the part shows a place at or before the place, or the
  /// search reached the part's end. The whole section can. A step does
  /// nothing then.
  bool get starved => _starved;
  bool _starved = false;

  /// Works toward [found] until [budget] is spent. A step ends after the
  /// unit of work that crosses the budget: the measure of one row of the
  /// place's table, the count of the lines of one segment of the place's
  /// paragraph, or the search itself once those are known.
  ///
  /// NOTE: Only the place's own table is measured in steps. A place in white
  /// space after its item's last line opens on the next item, which the
  /// search measures in its last step if it is a table not yet measured.
  void step(Duration budget) {
    if (_found != null || _starved) return;
    final begin = LayoutRun._elapsed();
    final item = _itemOf(_section, _place);
    // In a part, no item before the place can mean that an item that the
    // part skipped or left out after its end holds it.
    if (item < 0 && (_section.firstPrepared > 0 || !_section.reachesEnd)) {
      _starved = true;
      return;
    }
    var line = 0;
    if (item >= 0) {
      if (_section.flow[item] case final TableItem table
          when LayoutRun._measured[table] == null) {
        final measure = LayoutRun(_section);
        while (measure._measureRow(table, _rows) == null) {
          if (LayoutRun._elapsed() - begin >= budget) return;
        }
      }
      if (_section.flow[item] case final ParagraphItem paragraph) {
        final counted = _segmentLines(paragraph, item, begin, budget);
        if (counted == null) return;
        line = counted;
      }
    }
    _found = _search(item, line);
    _starved = _found == null;
  }

  /// The paragraph's lines before the segment of [paragraph], flow item
  /// [item], that holds the place: 0 for a paragraph of one segment. Finds
  /// the segments before it, one in each unit of work, and returns null
  /// when [budget], which began at [begin], is spent first.
  int? _segmentLines(
    ParagraphItem paragraph,
    int item,
    Duration begin,
    Duration budget,
  ) {
    if (!LayoutRun._long(paragraph.text)) return 0;
    final dom = _section.dom;
    final key = _order(dom, _place);
    final found = LayoutRun._found[paragraph] ??= _Segmentation();
    while (true) {
      // The place's segment among those found: the last one whose first
      // place is at or before it.
      var segment = 0;
      for (var index = 1; index < found.starts.length; index++) {
        final first = _placeAt(
          _section.index,
          paragraph.text,
          found.starts[index],
        );
        if (first != null && _compare(_order(dom, first), key) <= 0) {
          segment = index;
        }
      }
      if (segment + 1 < found.starts.length || found.complete) {
        return found.lines[segment];
      }
      // A run from the first line of the last segment found lays it out,
      // which finds where the next one starts. A paragraph with a hanging
      // first line lays out in one unit, and is one segment.
      final run = LayoutRun(_section, from: PageStart(item, found.lines.last));
      final known = found.starts.length;
      while (run._item <= item &&
          found.starts.length == known &&
          !found.complete) {
        run._layOutItem();
      }
      final whole = found.starts.length == known && !found.complete;
      run.dispose();
      if (whole) return 0;
      if (LayoutRun._elapsed() - begin >= budget) return null;
    }
  }

  /// The page start of the line that holds the place, from flow item
  /// [item], its line [line]; null when the search reached the end of a
  /// part of the section, which cannot tell it.
  PageStart? _search(int item, int line) {
    final section = _section;
    final place = _place;
    if (item < 0) return const PageStart(0, 0);
    final dom = section.dom;
    final flow = section.flow;
    // In a table, the row of the place: the last row whose first place is
    // at or before it.
    var row = 0;
    if (flow[item] case TableItem(:final rows)) {
      final key = _order(dom, place);
      for (var index = 1; index < rows.length; index++) {
        final first = _firstPlaceOfRow(section.index, rows[index]);
        if (first != null && _compare(_order(dom, first), key) <= 0) {
          row = index;
        }
      }
    }
    final run = LayoutRun(section, from: PageStart(item, math.max(row, line)));
    try {
      /// Lays out units of work until one adds a line that shows a place,
      /// or to the section end. Returns the page start of the line that
      /// holds the place among the lines laid out: those added, and those
      /// of a long paragraph that wait for its widows rule. A waiting line
      /// can hold the place when the line before it shows only white space,
      /// because both start at the same place in document order.
      ({PageStart? holder, bool past}) layOutShown() {
        final before = run._pending.length;
        while (run._item < flow.length) {
          run._layOutItem();
          if (run._pending
              .skip(before)
              .any(
                (slice) => _lines(slice).any((line) => line.start != null),
              )) {
            break;
          }
        }
        return _holder(dom, place, [
          for (final slice in run._pending)
            for (final line in _lines(slice)) (line, slice.at),
          if (run._segments case final segments?)
            for (final line in segments.waiting)
              (
                Slice(
                  line.top,
                  line.bottom,
                  Appeal.perfect,
                  PageStart(segments.index, line.above),
                  piece: line.piece,
                  line: line.line,
                  start: line.start,
                  units: line.units,
                ),
                PageStart(segments.index, line.above),
              ),
        ]);
      }

      var (:holder, :past) = layOutShown();
      // A long paragraph's later segments can hold the place.
      while (past && run._segments != null) {
        (:holder, :past) = layOutShown();
      }
      // A place in white space after the lines is on the first line of the
      // next item or row that shows something.
      if (past) (:holder, :past) = layOutShown();
      if (run.starved) return null;
      // The item's first line starts where the run starts: at the section
      // start when nothing comes before it.
      if (holder == null || holder == PageStart(item, 0)) return run._from;
      return holder;
    } finally {
      run.dispose();
    }
  }
}

/// The index of the last flow item of [section] whose first place is at or
/// before [place], or -1 when none is.
int _itemOf(PreparedSection section, EpubPlace place) {
  final dom = section.dom;
  final key = _order(dom, place);
  final flow = section.flow;
  var item = -1;
  for (var index = 0; index < flow.length; index++) {
    final first = _firstPlace(section.index, flow[index]);
    if (first != null && _compare(_order(dom, first), key) <= 0) item = index;
  }
  return item;
}

/// The owner of the line of [lines] that holds [place], and whether the
/// place lies after everything that the lines show. [lines] pairs each
/// line with its owner, in any order.
///
/// The line that holds a place is the last line that starts at or before
/// it in document order. But a place after the last thing that this line
/// shows, such as a place in white space between two paragraphs, belongs
/// to the next line: the line of its next visible character or image.
/// Null when no line starts at or after the place either.
({T? holder, bool past}) _holder<T>(
  DomSection dom,
  EpubPlace place,
  Iterable<(Slice, T)> lines,
) {
  final key = _order(dom, place);
  (Slice, T)? before;
  (int, int)? beforeOrder;
  T? after;
  (int, int)? afterOrder;
  for (final entry in lines) {
    final start = entry.$1.start;
    if (start == null) continue;
    final order = _order(dom, start);
    if (_compare(order, key) <= 0) {
      if (beforeOrder == null || _compare(order, beforeOrder) >= 0) {
        before = entry;
        beforeOrder = order;
      }
    } else if (afterOrder == null || _compare(order, afterOrder) < 0) {
      after = entry.$2;
      afterOrder = order;
    }
  }
  if (before == null) return (holder: after, past: false);
  final (line, owner) = before;
  final last = _lastShown(dom, line);
  if (last == null || _compare(key, last) <= 0) {
    return (holder: owner, past: false);
  }
  return after == null
      ? (holder: owner, past: true)
      : (holder: after, past: false);
}

/// The order of the last thing that [line] shows: its last visible
/// character or placeholder, or its start when it shows only white space.
/// Null when it ends with raised text, whose places the line does not map:
/// it then shows everything up to the next line.
(int, int)? _lastShown(DomSection dom, Slice line) {
  final start = _order(dom, line.start!);
  final piece = line.piece;
  if (piece == null) return start;
  final (first, end) = line.units;
  for (var unit = end - 1; unit >= first; unit--) {
    final text = piece.map.textPlaceAt(unit);
    if (text == null) {
      // A placeholder: an image or a line break at its element, raised
      // text at its first text node, or an indent at no node.
      final node = piece.map.nodes[piece.map._segment(unit)];
      if (node < 0) continue;
      return dom.nodeAt(node) is DomText ? null : (node, 0);
    }
    final data = dom.textAt(text)!.text;
    if (text.offset < data.length && !isSpace(data.codeUnitAt(text.offset))) {
      return (text.node, text.offset);
    }
  }
  return start;
}

/// The first place that flow [item] of section [section] shows, or null
/// when it shows none.
EpubPlace? _firstPlace(int section, FlowItem item) {
  switch (item) {
    case ImageItem(:final node):
      return EpubPlace(section, node, 0);
    case ParagraphItem(:final text):
      for (final run in text.runs) {
        switch (run) {
          case TextRun(:final node, :final offsets) when offsets.isNotEmpty:
            return EpubPlace(section, node, offsets[0]);
          case BreakRun(:final node) when node >= 0:
            return EpubPlace(section, node, 0);
          case ImageRun(:final node) || RaisedRun(:final node) when node >= 0:
            return EpubPlace(section, node, 0);
          default:
            continue;
        }
      }
      return null;
    case TableItem(:final rows):
      for (final row in rows) {
        if (_firstPlaceOfRow(section, row) case final place?) return place;
      }
      return null;
    case BlockStart() || BlockEnd() || SkippedItem():
      return null;
  }
}

/// The first place that table row [row] of section [section] shows, or
/// null when it shows none.
EpubPlace? _firstPlaceOfRow(int section, List<TableCell> row) {
  for (final cell in row) {
    for (final inner in cell.flow) {
      if (_firstPlace(section, inner) case final place?) return place;
    }
  }
  return null;
}

/// The place of code unit [unit] of [text], a paragraph's text without its
/// indent, or of the next code unit that has one; null when none has.
EpubPlace? _placeAt(int section, StyledText text, int unit) {
  var at = 0;
  for (final run in text.runs) {
    switch (run) {
      case TextRun(:final node, :final offsets):
        if (unit < at + offsets.length) {
          return EpubPlace(section, node, offsets[math.max(0, unit - at)]);
        }
        at += offsets.length;
      case BreakRun(:final node) ||
          ImageRun(:final node) ||
          RaisedRun(:final node):
        if (unit <= at && node >= 0) return EpubPlace(section, node, 0);
        at += 1;
    }
  }
  return null;
}

/// The order of [place] in the document. A place in white space counts as
/// the next visible character of its node, where a page or a line starts.
(int, int) _order(DomSection dom, EpubPlace place) {
  final text = dom.textAt(place);
  if (text == null) return (place.node, 0);
  var offset = place.offset;
  while (offset < text.text.length && isSpace(text.text.codeUnitAt(offset))) {
    offset++;
  }
  return (place.node, offset);
}

/// The lines of [slice]: the slice, or the slices of the cells of a table
/// row.
Iterable<Slice> _lines(Slice slice) =>
    slice.cellSlices.isEmpty ? [slice] : slice.cellSlices;

int _compare((int, int) a, (int, int) b) =>
    a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2);

/// A section laid out by its main run to the end, with lookups over its
/// pages. Tests and the trial tools use it; the reader lays out in steps.
class ChapterLayout {
  ChapterLayout._(this.section, this.pages);
  final PreparedSection section;
  final List<LaidPage> pages;

  PageSettings get settings => section.settings;

  /// Every slice of the section, in order.
  List<Slice> get slices => [for (final page in pages) ...page.slices];

  /// Every decoration that a page draws, once.
  List<Decoration> get decorations =>
      {for (final page in pages) ...page.decorations}.toList();

  /// The index of the page that holds [place]: the page of the line that
  /// holds it (see [_holder]).
  int pageAt(EpubPlace place) =>
      _holder(section.dom, place, [
        for (final (index, page) in pages.indexed)
          for (final slice in page.slices)
            for (final line in _lines(slice)) (line, index),
      ]).holder ??
      0;

  /// The index of the page that holds [visible], a visible character
  /// index.
  int pageOf(int visible) {
    var low = 0;
    var high = pages.length - 1;
    while (low < high) {
      final middle = (low + high + 1) >> 1;
      if (pages[middle].startVisible <= visible) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    return low;
  }

  void dispose() {
    for (final page in pages) {
      page.dispose();
    }
  }
}

/// Lays out [section] in its main run, stepped to the end.
ChapterLayout layoutSection(PreparedSection section) {
  final run = LayoutRun(section);
  while (!run.done) {
    run.step(const Duration(days: 1));
  }
  run.dispose();
  return ChapterLayout._(section, run.pages);
}

/// Where each code unit of a paragraph's text comes from: a text node and
/// an offset in it, or a node for a placeholder.
class TextMap {
  TextMap(this.section);

  /// The spine index of the section.
  final int section;
  final starts = <int>[];

  /// The [DomNode.order] of each segment's node, or -1 for a placeholder
  /// that no node owns.
  final nodes = <int>[];
  final offsets = <Int32List?>[];
  int length = 0;

  void addText(int node, Int32List domOffsets) {
    starts.add(length);
    nodes.add(node);
    offsets.add(domOffsets);
    length += domOffsets.length;
  }

  /// Adds a placeholder of one code unit, which starts at [node], or at no
  /// place when [node] is -1.
  void addPlaceholder(int node) {
    starts.add(length);
    nodes.add(node);
    offsets.add(null);
    length += 1;
  }

  /// The place of code unit [index], or of the next one that has a place,
  /// or null when none follows.
  EpubPlace? placeAtUnit(int index) {
    for (var segment = _segment(index); segment < starts.length; segment++) {
      final node = nodes[segment];
      final local = math.max(0, index - starts[segment]);
      final units = offsets[segment];
      if (units != null) {
        if (local < units.length) return EpubPlace(section, node, units[local]);
      } else if (node >= 0 && local == 0) {
        // A placeholder starts at its node: an element, or the first text
        // node of raised text.
        return EpubPlace(section, node, 0);
      }
    }
    return null;
  }

  /// The [DomNode.order] of the node that code unit [index] comes from:
  /// its text node, or the node that a placeholder starts at. -1 for a
  /// placeholder that no node owns, such as an indent.
  int nodeAt(int index) => nodes[_segment(index)];

  /// The text place of code unit [index], or null when it is a
  /// placeholder.
  EpubPlace? textPlaceAt(int index) {
    if (starts.isEmpty) return null;
    final segment = _segment(index);
    final units = offsets[segment];
    final local = index - starts[segment];
    if (units == null || local < 0 || local >= units.length) return null;
    return EpubPlace(section, nodes[segment], units[local]);
  }

  int _segment(int index) {
    var low = 0;
    var high = starts.length - 1;
    while (low < high) {
      final middle = (low + high + 1) >> 1;
      if (starts[middle] <= index) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    return low;
  }
}

/// A block box whose [BlockStart] layout passed and whose [BlockEnd] it has
/// not reached yet.
class _OpenBlock {
  _OpenBlock(
    this.start,
    this.item,
    this.left,
    this.contentWidth,
    this.boxTop,
    this.firstSlice,
  );
  final BlockStart start;

  /// The index of [start] in the flow.
  final int item;

  /// The left edge of the border box.
  final double left;
  final double contentWidth;

  /// Where the border box starts on the strip, once its top padding or
  /// border placed it.
  final double? boxTop;

  /// The number of slices that the run added before the box opened.
  final int firstSlice;

  double get contentLeft => left + start.border[3] + start.padding[3];
}

/// A line of a paragraph laid out on the strip but not added yet: line
/// [line] of [piece], from [top] to [bottom] on the strip, whose first
/// place is [start] and whose code units of the piece are [units]. It is
/// line [above] of its paragraph.
typedef _Line = ({
  Piece piece,
  int line,
  double top,
  double bottom,
  EpubPlace? start,
  (int, int) units,
  int above,
});

/// A long paragraph that a run lays out a segment at a time (see
/// [LayoutRun._segmentsOf]).
class _Segments {
  _Segments(this.item, this.index, this.x, this.width, this.indent, this.from);
  final ParagraphItem item;

  /// The index of [item] in the flow.
  final int index;

  /// Where the paragraph sits, and its first line's indent.
  final double x;
  final double width;
  final double indent;

  /// The first line that the run adds.
  final int from;

  /// The next segment to lay out, and the paragraph's lines before it.
  int next = 0;
  int lines = 0;

  /// The lines laid out whose widows rule waits for the lines after them.
  final waiting = <_Line>[];
}

/// The segments of a long paragraph item that runs found so far (see
/// [LayoutRun._long]). A segment starts where the last line of the segment
/// before it starts, so runs find the starts as they lay the segments out.
class _Segmentation {
  /// Where each segment found starts, in code units of the paragraph's
  /// text, and the paragraph's lines before it.
  final starts = <int>[0];
  final lines = <int>[0];

  /// Whether a run laid out the last segment, so that [starts] holds the
  /// start of every segment.
  bool complete = false;

  /// Whether the segments came from kept measures ([reuseMeasures]). A run
  /// that lays out a segment checks where the next one starts.
  bool kept = false;
}

/// A table that a run lays out a row at a time.
class _Rows {
  _Rows(this.table, this.item, this.left, this.widths, this.row, this.part);
  final TableItem table;

  /// The index of [table] in the flow.
  final int item;

  /// The left edge of the box that holds the table.
  final double left;

  /// The width of each column.
  final List<double> widths;

  /// The next row to lay out, and its first fragment to add.
  int row;
  int part;

  /// The next row's cells whose content is laid out, and the run of the
  /// next cell's content while it lays it out.
  final cells = <_Cell>[];
  LayoutRun? cell;

  /// Lets go of what the next row laid out.
  void release() {
    for (final cell in cells) {
      cell.release();
    }
    cells.clear();
    cell?.dispose();
    cell = null;
  }
}

/// The content of a table cell laid out at strip position 0: its slices,
/// the paragraphs that they show, its list markers and other decorations,
/// and its height. It holds its paragraphs and markers until [release].
class _Cell {
  _Cell(this.slices, this.pieces, this.markers, this.decorations, this.height);

  final List<Slice> slices;
  final List<Piece> pieces;
  final List<Piece> markers;
  final List<Decoration> decorations;
  final double height;

  /// What a row, or a fragment of a row, shows of the content: its slices
  /// [from, to) and what it draws in the band [top, bottom) of the content,
  /// moved down by [dy]. Lines below the band are hidden. The moved pieces
  /// hold their paragraphs; [held] lists them.
  ({List<Slice> slices, List<Decoration> decorations, List<Piece> held}) show(
    int from,
    int to,
    double dy,
    double top,
    double bottom,
  ) {
    final moved = <Piece, Piece>{};
    Piece move(Piece piece) => moved[piece] ??= Piece._moved(
      piece,
      dy,
      math.min(piece.shown, bottom - piece.y),
    );
    final offset = ui.Offset(0, dy);
    return (
      slices: [
        for (final slice in slices.sublist(from, to))
          Slice(
            slice.top + dy,
            slice.bottom + dy,
            slice.appeal,
            slice.at,
            piece: slice.piece == null ? null : move(slice.piece!),
            line: slice.line,
            start: slice.start,
            units: slice.units,
          ),
      ],
      decorations: [
        for (final decoration in decorations)
          switch (decoration) {
            RuleDecoration(:final rect)
                when math.min(rect.bottom, bottom) > math.max(rect.top, top) =>
              RuleDecoration(
                ui.Rect.fromLTRB(
                  rect.left,
                  math.max(rect.top, top),
                  rect.right,
                  math.min(rect.bottom, bottom),
                ).shift(offset),
              ),
            ImageDecoration(:final rect, :final image)
                when rect.top >= top && rect.top < bottom =>
              ImageDecoration(rect.shift(offset), image),
            MarkerDecoration(:final piece)
                when piece.y >= top && piece.y < bottom =>
              MarkerDecoration(
                moved[piece] ??= Piece._moved(piece, dy, piece.shown),
              ),
            _ => null,
          },
      ].nonNulls.toList(),
      held: moved.values.toList(),
    );
  }

  /// Lets go of the content's paragraphs.
  void release() {
    for (final piece in [...pieces, ...markers]) {
      piece._release();
    }
  }
}

/// Text that a paragraph shows from code unit [start] on, in run style
/// [style].
typedef _Text = ({int start, String text, int style});

/// The widths that a run style draws a hyphen and a space with, measured
/// once per layout run and the runs of its table cells.
class _Advances {
  final _hyphens = <int, double>{};
  final _spaces = <int, double>{};

  /// The width of a hyphen in run style [style] of [styles].
  double hyphen(int style, List<ui.TextStyle> styles) =>
      _hyphens[style] ??= _measure(styles[style], '\u2010', 0);

  /// The width of a space between two words in run style [style].
  double space(int style, List<ui.TextStyle> styles) =>
      _spaces[style] ??= _measure(styles[style], 'x x', 1);

  /// The width that code unit [unit] of [text] takes in [style].
  static double _measure(ui.TextStyle style, String text, int unit) {
    final paragraph =
        (ui.ParagraphBuilder(ui.ParagraphStyle())
              ..pushStyle(style)
              ..addText(text))
            .build()
          ..layout(const ui.ParagraphConstraints(width: double.infinity));
    final boxes = paragraph.getBoxesForRange(unit, unit + 1);
    paragraph.dispose();
    return boxes.fold(0.0, (width, box) => width + box.right - box.left);
  }
}

class _Built {
  _Built(
    this.paragraph,
    this.map,
    this.inlines,
    this.softHyphens,
    this.texts, {
    required this.start,
    required this.length,
  });
  final ui.Paragraph paragraph;

  /// The code unit of the whole paragraph that [paragraph] starts at, when
  /// it is a part of it (see [LayoutRun._build]), and the whole
  /// paragraph's length in code units.
  final int start;
  final int length;

  /// Whether [paragraph] runs to code unit [end] of the whole paragraph,
  /// or to its end.
  bool reaches(int? end) => start + map.length >= (end ?? length);
  final TextMap map;
  final List<Object?> inlines;

  /// The code units of [paragraph] that hold a soft hyphen of the text, in
  /// increasing order, whatever marks replaced them with.
  final List<int> softHyphens;

  /// The text of [paragraph], in order. Placeholders are not in it.
  final List<_Text> texts;

  /// The text piece that holds code unit [unit], or null for a
  /// placeholder.
  _Text? _textAt(int unit) {
    var low = 0;
    var high = texts.length - 1;
    while (low <= high) {
      final middle = (low + high) >> 1;
      final text = texts[middle];
      if (unit < text.start) {
        high = middle - 1;
      } else if (unit >= text.start + text.text.length) {
        low = middle + 1;
      } else {
        return text;
      }
    }
    return null;
  }

  /// Code unit [unit] of the paragraph, or -1 for a placeholder.
  int unitAt(int unit) {
    final text = _textAt(unit);
    return text == null ? -1 : text.text.codeUnitAt(unit - text.start);
  }

  /// The run style of code unit [unit], which is text.
  int styleAt(int unit) => _textAt(unit)!.style;

  /// Disposes the paragraph and the raised paragraphs in its placeholders.
  void dispose() {
    paragraph.dispose();
    for (final held in inlines) {
      if (held is ui.Paragraph) held.dispose();
    }
  }
}

ui.FontWeight _weight(int weight) =>
    ui.FontWeight.values[((weight / 100).round() - 1).clamp(0, 8)];

/// The text style that draws a run in [style] with [ink].
ui.TextStyle runTextStyle(RunStyle style, ui.Color ink) {
  return ui.TextStyle(
    color: ink,
    fontFamily: style.family,
    // A character that the family lacks draws in the needed book face that
    // styles the run (boo-3huo), else in the reader font, not in the
    // platform's default font, and an arrow that all of them lack draws in
    // the arrow font, not in the platform's emoji font.
    fontFamilyFallback: [?style.face, readerFontFamily, arrowFontFamily],
    fontSize: style.size,
    fontWeight: _weight(style.weight),
    fontStyle: style.italic ? ui.FontStyle.italic : ui.FontStyle.normal,
    letterSpacing: style.letterSpacing == 0 ? null : style.letterSpacing,
    wordSpacing: style.wordSpacing == 0 ? null : style.wordSpacing,
    height: style.lineHeight == null ? null : style.lineHeight! / style.size,
    leadingDistribution: ui.TextLeadingDistribution.even,
    decoration: ui.TextDecoration.combine([
      if (style.underline) ui.TextDecoration.underline,
      if (style.lineThrough) ui.TextDecoration.lineThrough,
    ]),
    fontFeatures: [
      if (style.smallCaps) const ui.FontFeature.enable('smcp'),
      if (style.oldstyleFigures) const ui.FontFeature.oldstyleFigures(),
    ],
    fontVariations: [
      // Chromium sets a variable font's optical size to the text size.
      ui.FontVariation('opsz', style.size.clamp(8, 60).toDouble()),
      // Chromium sets a variable font's weight axis to the CSS weight. But
      // the reader's @font-face rule names no weights, so Chromium draws
      // bold reader text as a thickened regular face with regular widths.
      // Flutter would pick the font's true bold, which is wider.
      ui.FontVariation(
        'wght',
        style.family == readerFontFamily ? 400 : style.weight.toDouble(),
      ),
    ],
  );
}

/// The paragraph style of a block in the run style [container], aligned by
/// [align]. The block's font and line height form its strut.
ui.ParagraphStyle blockParagraphStyle(RunStyle container, Align align) {
  final height = container.lineHeight;
  return ui.ParagraphStyle(
    textAlign: switch (align) {
      Align.left => ui.TextAlign.left,
      Align.right => ui.TextAlign.right,
      Align.center => ui.TextAlign.center,
      Align.justify => ui.TextAlign.justify,
      Align.end => ui.TextAlign.end,
      Align.start => ui.TextAlign.start,
    },
    textDirection: ui.TextDirection.ltr,
    // The block's own font and line height form a strut, as CSS's root
    // inline box does.
    strutStyle: ui.StrutStyle(
      fontFamily: container.family,
      fontSize: container.size,
      height: height == null ? null : height / container.size,
      leadingDistribution: ui.TextLeadingDistribution.even,
      fontWeight: _weight(container.weight),
    ),
    textHeightBehavior: const ui.TextHeightBehavior(
      leadingDistribution: ui.TextLeadingDistribution.even,
    ),
  );
}

/// The calls that built a paragraph that a page can show: what a kept page
/// ([PageDrawing]) needs to build the paragraph again.
final class ParagraphRecipe {
  ParagraphRecipe._(this.block);

  /// The run style and the alignment of the paragraph's block, whose
  /// [blockParagraphStyle] built it, or null for the default paragraph
  /// style.
  final (int, Align)? block;

  /// The builder calls in order: an [int] pushes that run style of the
  /// section ([runTextStyle]), a [String] adds that text, null pops a style,
  /// and a record adds a placeholder on the alphabetic baseline.
  final calls = <Object?>[];
}

/// The recipe of [paragraph], when a layout run built it to show it on a
/// page, or null.
ParagraphRecipe? recipeOf(ui.Paragraph paragraph) => _recipes[paragraph];

final _recipes = Expando<ParagraphRecipe>('paragraph recipes');

/// A builder of a paragraph that a page can show. It records its calls in
/// the paragraph's recipe ([recipeOf]).
final class _Recorder {
  _Recorder(this._styles, ui.ParagraphStyle style, {(int, Align)? block})
    : _builder = ui.ParagraphBuilder(style),
      _recipe = ParagraphRecipe._(block);

  final List<ui.TextStyle> _styles;
  final ui.ParagraphBuilder _builder;
  final ParagraphRecipe _recipe;

  /// Adds [text] in run style [style].
  void addRun(int style, String text) {
    _builder
      ..pushStyle(_styles[style])
      ..addText(text)
      ..pop();
    _recipe.calls.addAll([style, text, null]);
  }

  /// Adds [text] in the paragraph's style.
  void addText(String text) {
    _builder.addText(text);
    _recipe.calls.add(text);
  }

  /// Adds a placeholder [width] by [height] pixels whose bottom sits
  /// [baselineOffset] pixels below the top of the line's baseline.
  void addPlaceholder(double width, double height, double baselineOffset) {
    _builder.addPlaceholder(
      width,
      height,
      ui.PlaceholderAlignment.baseline,
      baseline: ui.TextBaseline.alphabetic,
      baselineOffset: baselineOffset,
    );
    _recipe.calls.add((
      width: width,
      height: height,
      baselineOffset: baselineOffset,
    ));
  }

  ui.Paragraph build() {
    final paragraph = _builder.build();
    _recipes[paragraph] = _recipe;
    return paragraph;
  }
}

/// The family of the bundled arrow font, a subset of Noto Sans Math with
/// the Unicode arrow blocks. Text draws an arrow that its face lacks, such
/// as the leftwards arrow with hook (U+21A9) of a back link, in this font.
/// Without it, the platform draws such an arrow with its color emoji font.
const arrowFontFamily = 'Noto Sans Math Arrows';
