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

import 'css.dart';
import 'dom.dart';
import 'fonts.dart';
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

/// One cut page. It never changes once a run publishes it.
///
/// It holds the paragraphs that it shows, until [dispose]. Its geometry is
/// in the strip coordinates of the run that cut it.
class LaidPage {
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
  PageSettings get settings => _section.settings;

  /// The DOM of the page's section, where its places point.
  DomSection get dom => _section.dom;
  final PageStart start;

  /// Where the page begins and ends on its run's strip.
  final double top;
  final double bottom;
  double get height => bottom - top;

  /// The strip slices on the page, in order.
  final List<Slice> slices;

  /// The rules, images and markers that the page draws, at their place on
  /// the strip.
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
/// Invariants, which [checkInvariants] checks:
/// - The run holds every piece that a slice or a marker not yet published
///   shows, and every piece that it holds is alive.
/// - Published pages follow each other: their starts increase, and each
///   page's top is the previous page's bottom.
/// - The slices not yet published start at the top of the next page.
/// - Once the run is done, it laid out every flow item and holds no slice.
class LayoutRun {
  /// A run of [section] from [from], or from the section start. [clock]
  /// gives the time now for the step budget; it defaults to a monotonic
  /// clock.
  ///
  /// A run measures each row of a table for its column widths, once per
  /// table item, one row in each unit of work. NOTE: A run that starts
  /// inside a shrink-to-fit box that holds a table not yet measured, as a
  /// table's own box is, measures the whole table here. The page source
  /// starts such runs only at page starts of the main run or of
  /// [lineStart], which measure the table first, in steps.
  LayoutRun(
    PreparedSection section, {
    PageStart? from,
    Duration Function()? clock,
  }) : _section = section,
       _flow = section.flow,
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
      _clock = outer._clock,
      _root = (left, width),
      _textStyles = outer._textStyles,
      _advances = outer._advances;

  static final _watch = Stopwatch()..start();
  static Duration _elapsed() => _watch.elapsed;

  final PreparedSection _section;

  /// The flow items that the run lays out: the section's, or a cell's.
  final List<FlowItem> _flow;
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
    while (!_done) {
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
    }
    if (_done) {
      check(_rows == null, 'a done run has a table in progress');
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
        case ParagraphItem() || ImageItem() || TableItem():
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

  /// Lays out the next unit of work: a flow item, one row of a table, or
  /// the measure of one row of a table whose column widths the next item
  /// needs.
  void _layOutItem() {
    final flow = _flow;
    if (_item == flow.length) return;
    if (_rows case final rows?) {
      _tableRow(rows);
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
    final atEnd = _item == _flow.length;
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
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle())
      ..pushStyle(_textStyles[style])
      ..addText(text);
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

  /// Lays out the next row of [rows] and adds its slices at the current
  /// strip position, from the row's fragment [_Rows.part] on: one slice, or
  /// one for each fragment of a row taller than a page.
  void _tableRow(_Rows rows) {
    final table = rows.table;
    final number = rows.row;
    final row = table.rows[number];
    final (across, down) = table.spacing;
    final x = rows.left;
    final boxes = cellBoxes(
      [for (final cell in row) cell.colspan],
      rows.widths,
      across,
    );
    // Each cell's box, its left edge and width, and its content laid out at
    // strip position 0.
    final cells = [
      for (final (column, cell) in row.indexed)
        () {
          final (left, cellWidth) = boxes[column];
          final [top, right, bottom, start] = [
            for (var side = 0; side < 4; side++)
              cell.padding[side] + cell.border[side],
          ];
          return (
            x + left,
            cellWidth,
            cell,
            _layOutCell(
              cell.flow,
              x + left + start,
              math.max(0, cellWidth - start - right),
            ),
          );
        }(),
    ];
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
        case TableItem():
          // A table inside a cell is plain blocks.
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

  /// Lays out [flow], the content of a table cell, in a content box that
  /// starts at [left] and is [width] pixels wide, with its top at strip
  /// position 0.
  _Cell _layOutCell(List<FlowItem> flow, double left, double width) {
    final run = LayoutRun._cell(this, flow, left, width);
    while (run._item < flow.length) {
      run._layOutItem();
    }
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

  /// The family that draws [family]: the reader font for an embedded face
  /// that did not load, as for a face that prepare cannot read, and else
  /// [family].
  static String _drawn(String family) =>
      BookFonts.missing(family) ? readerFontFamily : family;

  static ui.TextStyle _textStyle(RunStyle style, ui.Color ink) {
    final family = _drawn(style.family);
    return ui.TextStyle(
      color: ink,
      fontFamily: family,
      // A character that a face lacks draws in the reader font, not in the
      // platform's default font.
      fontFamilyFallback: const [readerFontFamily],
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
          family == readerFontFamily ? 400 : style.weight.toDouble(),
        ),
      ],
    );
  }

  static ui.FontWeight _weight(int weight) =>
      ui.FontWeight.values[((weight / 100).round() - 1).clamp(0, 8)];

  ui.ParagraphStyle _paragraphStyle(StyledText text) {
    final container = _section.styles[text.style];
    final height = container.lineHeight;
    return ui.ParagraphStyle(
      textAlign: switch (text.align) {
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
        fontFamily: _drawn(container.family),
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

  /// Builds the paragraph of [text], [width] pixels wide, from its code
  /// unit [from] on. Returns the paragraph, its map, what each of its
  /// placeholders holds (null for the indent, an image's path, or a raised
  /// paragraph) and its soft hyphens. [marks] replaces the soft hyphen at
  /// a code unit of the paragraph with another code unit.
  _Built _build(
    StyledText text,
    double indent,
    double width, {
    int from = 0,
    Map<int, int> marks = const {},
  }) {
    final builder = ui.ParagraphBuilder(_paragraphStyle(text));
    final map = TextMap(_section.index);
    final inlines = <Object?>[];
    final softHyphens = <int>[];
    final texts = <_Text>[];
    var unit = 0;
    if (indent > 0 && from == 0) {
      builder.addPlaceholder(
        indent,
        0,
        ui.PlaceholderAlignment.baseline,
        baseline: ui.TextBaseline.alphabetic,
        baselineOffset: 0,
      );
      map.addPlaceholder(-1);
      inlines.add(null);
      unit = 1;
    }
    // A continued paragraph starts after the line that it continues, whose
    // last space ends that line.
    var trim = from > 0;
    for (final run in text.runs) {
      switch (run) {
        case TextRun(text: final written, :final style, :final node):
          final start = unit;
          unit += written.length;
          if (unit <= from) continue;
          var skip = math.max(0, from - start);
          if (trim) {
            while (skip < written.length && written.codeUnitAt(skip) == 0x20) {
              skip++;
            }
            if (skip == written.length) continue;
            trim = false;
          }
          final added = written.substring(skip);
          final first = map.length;
          var marked = false;
          for (
            var at = added.indexOf(_softHyphen);
            at >= 0;
            at = added.indexOf(_softHyphen, at + 1)
          ) {
            softHyphens.add(first + at);
            marked |= marks.containsKey(first + at);
          }
          final shown = marked
              ? String.fromCharCodes([
                  for (var at = 0; at < added.length; at++)
                    marks[first + at] ?? added.codeUnitAt(at),
                ])
              : added;
          texts.add((start: first, text: shown, style: style));
          builder
            ..pushStyle(_textStyles[style])
            ..addText(shown)
            ..pop();
          map.addText(node, Int32List.sublistView(run.offsets, skip));
        case BreakRun(:final node):
          final start = unit;
          unit += 1;
          if (start < from) continue;
          trim = false;
          builder.addText('\n');
          map.addPlaceholder(node);
        case ImageRun(:final node, :final image, :final sizing):
          final start = unit;
          unit += 1;
          if (start < from) continue;
          trim = false;
          final (imageWidth, imageHeight) = sizing.sizeIn(width);
          builder.addPlaceholder(
            imageWidth,
            imageHeight,
            ui.PlaceholderAlignment.baseline,
            baseline: ui.TextBaseline.alphabetic,
            baselineOffset: imageHeight,
          );
          map.addPlaceholder(node);
          inlines.add(image);
        case RaisedRun(:final node, text: final inner, :final shift):
          final start = unit;
          unit += 1;
          if (start < from) continue;
          trim = false;
          final raised = _build(inner, 0, width).paragraph
            ..layout(const ui.ParagraphConstraints(width: double.infinity));
          final lines = raised.computeLineMetrics();
          final baseline = lines.isEmpty ? 0.0 : lines.first.baseline;
          builder.addPlaceholder(
            raised.maxIntrinsicWidth,
            raised.height,
            ui.PlaceholderAlignment.baseline,
            baseline: ui.TextBaseline.alphabetic,
            baselineOffset: baseline + shift,
          );
          map.addPlaceholder(node);
          inlines.add(raised);
      }
    }
    return _Built(builder.build(), map, inlines, softHyphens, texts);
  }

  static final _softHyphen = String.fromCharCode(softHyphen);

  /// The hyphen that ends a line inside a word, which Chromium draws when
  /// the font has it.
  static const _hyphen = 0x2010;

  /// A word joiner: no line break, and nothing drawn.
  static const _joiner = 0x2060;

  /// The paragraph of [text] built from its code unit [from] on and laid
  /// out [width] pixels wide, with a hyphen at the end of each line that
  /// ends inside a word.
  ///
  /// Flutter breaks a line at a soft hyphen, but draws no hyphen there. So
  /// each soft hyphen that ends a line becomes a hyphen, and the paragraph
  /// is laid out again. The line then holds its hyphen, as in Chromium: a
  /// justified line ends at it. As in Chromium, the hyphen must fit in the
  /// line. A soft hyphen whose hyphen would not fit becomes a word joiner,
  /// so its line breaks earlier, and the lines after it are hyphenated
  /// again.
  _Built _layOut(StyledText text, double indent, double width, {int from = 0}) {
    final marks = <int, int>{};
    final justified = text.align == Align.justify;
    // The code units from which the hyphens are checked and the line ends
    // are marked, or null when no line end is left to mark.
    var check = 0;
    int? scan = 0;
    while (true) {
      final built = _build(text, indent, width, from: from, marks: marks);
      built.paragraph.layout(ui.ParagraphConstraints(width: width));
      if (built.softHyphens.isEmpty) return built;
      final next = _markHyphens(
        built,
        marks,
        width,
        check: check,
        scan: scan,
        justified: justified,
      );
      if (next == null) return built;
      (check, scan) = next;
      built.dispose();
    }
  }

  /// Marks the soft hyphens of [built], a paragraph laid out [width] pixels
  /// wide, in [marks]. Returns null when no mark changed, so the paragraph
  /// is final; else from which code units the next layout's hyphens are
  /// checked and its line ends are marked (null when none is left).
  ///
  /// A hyphen marked from code unit [check] on must end its line. If one
  /// does not, the width of its justified line was misjudged: it becomes a
  /// word joiner, and the hyphens after it are unmarked.
  ///
  /// Each soft hyphen that ends a line from the line that holds code unit
  /// [scan] on becomes a hyphen when the hyphen fits in the line, and else
  /// a word joiner. The line of a word joiner and the lines after it break
  /// again, so marking stops there.
  ///
  /// Each call adds a word joiner or marks every line end, and word joiners
  /// stay. So a paragraph with n soft hyphens is laid out at most 2n + 2
  /// times, and once more than it has word joiners when no width is
  /// misjudged.
  (int, int?)? _markHyphens(
    _Built built,
    Map<int, int> marks,
    double width, {
    required int check,
    required int? scan,
    required bool justified,
  }) {
    final paragraph = built.paragraph;
    final length = built.map.length;
    final metrics = paragraph.computeLineMetrics();
    final starts = _lineStarts(paragraph, length, metrics.length);
    // The end of each line before its hard break's newline.
    int end(int line) => line + 1 < starts.length
        ? starts[line + 1] - (metrics[line].hardBreak ? 1 : 0)
        : length;
    for (final unit in built.softHyphens) {
      if (unit < check || marks[unit] != _hyphen) continue;
      final line = paragraph.getLineNumberAt(unit)!;
      if (end(line) != unit + 1) {
        marks[unit] = _joiner;
        marks.removeWhere((other, mark) => other > unit && mark == _hyphen);
        // The line before it broke early, and breaks again.
        return (unit, line > 0 ? starts[line - 1] : 0);
      }
    }
    if (scan == null) return null;
    var changed = false;
    for (
      var line = paragraph.getLineNumberAt(math.min(scan, length - 1))!;
      line < starts.length;
      line++
    ) {
      final unit = end(line) - 1;
      if (unit + 1 >= length ||
          marks.containsKey(unit) ||
          built.unitAt(unit) != softHyphen) {
        continue;
      }
      final natural = justified
          ? _naturalWidth(built, metrics[line], starts[line], unit)
          : metrics[line].width;
      final hyphen = _advances.hyphen(built.styleAt(unit), _textStyles);
      if (natural + hyphen > width + _fitTolerance) {
        marks[unit] = _joiner;
        // The line breaks earlier, maybe at another soft hyphen.
        return (scan, starts[line]);
      }
      marks[unit] = _hyphen;
      changed = true;
    }
    return changed ? (scan, null) : null;
  }

  /// How far past the line width a hyphen may reach and still fit: float
  /// noise. A hyphen judged to fit that does not makes its line break
  /// earlier, and [_markHyphens] then refuses it.
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
    final rest = _layOut(item.text, 0, width, from: end);
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
    final paragraph = built.paragraph;
    final metrics = paragraph.computeLineMetrics();
    final count = lines ?? metrics.length;
    final all = total ?? metrics.length;
    // Chromium rounds the font's metrics for `line-height: normal`, so only
    // a CSS line height is fractional there.
    final exact = _section.styles[item.text.style].lineHeight != null;
    final paragraphs = _Paragraphs(paragraph, exact: exact);
    final tops = paragraphs.tops;
    var top = tops[from];
    final piece = Piece._of(paragraphs, x, _y - top, built.map);
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
    for (var line = from; line < count; line++) {
      final bottom = tops[line + 1];
      final above = before + line;
      // Chromium keeps the orphans rule first. It keeps the widows rule
      // only when the paragraph is long enough to keep both.
      final widows =
          all >= item.orphans + item.widows && all - above < item.widows;
      final appeal = above == 0
          ? Appeal.perfect
          : above < item.orphans || widows
          ? Appeal.violatingOrphansWidows
          : Appeal.perfect;
      final slice = _add(
        piece.y + top,
        piece.y + bottom,
        appeal,
        PageStart(index, above),
        piece: piece,
        line: line,
        start: built.map.placeAtUnit(starts[line]),
        units: (
          starts[line],
          line + 1 < starts.length ? starts[line + 1] : built.map.length,
        ),
      );
      if (above == 0) _takeMarker(slice);
      top = bottom;
    }
    if (lines != null) piece.shown = top;
    _y = piece.y + (lines == null ? tops.last : top);
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
}

/// The page start of the line that holds [place], a place in [section]
/// (see [_holder]). It lays out the paragraph or the table row of the
/// place, and the next one when the place is in white space after it. A
/// table needs each row measured for its column widths first, once per
/// table item: [LineSearch] does that in steps.
PageStart lineStart(PreparedSection section, EpubPlace place) =>
    (LineSearch(section, place)..step(const Duration(days: 1))).found!;

/// The search of [lineStart] in steps, so that frames go on while it
/// measures the column widths of a long table.
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

  /// Works toward [found] until [budget] is spent. A step ends after the
  /// unit of work that crosses the budget: the measure of one row of the
  /// place's table, or the search itself once the table is measured.
  ///
  /// NOTE: Only the place's own table is measured in steps. A place in white
  /// space after its item's last line opens on the next item, which the
  /// search measures in its last step if it is a table not yet measured.
  void step(Duration budget) {
    if (_found != null) return;
    final begin = LayoutRun._elapsed();
    final item = _itemOf(_section, _place);
    if (item >= 0) {
      if (_section.flow[item] case final TableItem table
          when LayoutRun._measured[table] == null) {
        final measure = LayoutRun(_section);
        while (measure._measureRow(table, _rows) == null) {
          if (LayoutRun._elapsed() - begin >= budget) return;
        }
      }
    }
    _found = _search(item);
  }

  PageStart _search(int item) {
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
    final run = LayoutRun(section, from: PageStart(item, row));
    try {
      /// Lays out units of work until one adds a line that shows a place,
      /// or to the section end. Returns the holder of the place among the
      /// lines laid out.
      ({Slice? holder, bool past}) layOutShown() {
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
            for (final line in _lines(slice)) (line, slice),
        ]);
      }

      var (:holder, :past) = layOutShown();
      // A place in white space after the lines is on the first line of the
      // next item or row that shows something.
      if (past) (:holder, :past) = layOutShown();
      // The item's first line starts where the run starts: at the section
      // start when nothing comes before it.
      if (holder == null || holder.at == PageStart(item, 0)) return run._from;
      return holder.at;
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
          case ImageRun(:final node) || RaisedRun(:final node):
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
    case BlockStart() || BlockEnd():
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
  _Built(this.paragraph, this.map, this.inlines, this.softHyphens, this.texts);
  final ui.Paragraph paragraph;
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
