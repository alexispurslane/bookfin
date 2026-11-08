// Lays out one prepared section with Flutter's text engine and cuts it into
// pages. It runs on the UI isolate, because dart:ui paragraphs exist only
// there.
//
// The section flows down one strip as wide as the page, as a scrolled
// document would. Each line, image and rule is a slice of the strip. A page
// is a window [top, bottom) of the strip that holds whole slices, so a
// paragraph splits across pages between its lines. The breaks follow CSS
// fragmentation as Chromium applies it to the WebView reader's columns:
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
import 'prepare.dart';

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

/// Where a page begins: line [line] of flow item [item].
///
/// A paragraph's lines count from its first line, a hanging first line
/// included. An image, and a box without content that is a slice of its
/// own (such as a rule), start at line 0 of their item. The section's first
/// page starts at `PageStart(0, 0)`.
class PageStart implements Comparable<PageStart> {
  const PageStart(this.item, this.line);
  final int item;
  final int line;

  @override
  int compareTo(PageStart other) => item != other.item
      ? item.compareTo(other.item)
      : line.compareTo(other.line);

  @override
  bool operator ==(Object other) =>
      other is PageStart && other.item == item && other.line == line;

  @override
  int get hashCode => Object.hash(item, line);

  @override
  String toString() => 'PageStart($item, $line)';
}

/// A slice of the strip that a page holds whole: a line, an image or a
/// rule.
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
  });
  final double top;
  final double bottom;

  /// The appeal of a page break right before this slice.
  final int appeal;

  /// The start of a page that begins with this slice.
  final PageStart at;

  /// The paragraph that holds this line, or null for an image or a rule.
  final Piece? piece;

  /// The line's index in [piece].
  final int line;

  /// The place of the slice's first character, or null when it shows no
  /// text.
  final EpubPlace? start;

  /// The code units of [piece]'s text that the line shows, [start, end).
  final (int, int) units;
}

/// One laid-out paragraph: a Flutter paragraph at a place on the strip,
/// and where each of its characters comes from in the DOM.
///
/// The run that builds a piece and each page that shows it hold it. Its
/// paragraphs are disposed when the last holder lets it go.
class Piece {
  Piece(this.paragraph, this.x, this.y, this.map);
  final ui.Paragraph paragraph;
  final double x;
  final double y;
  final TextMap map;

  /// Images and raised text drawn in the paragraph's placeholders.
  final List<(ui.Rect, Object)> inlines = [];

  /// The height of the lines that this piece shows, from its top. A hanging
  /// first line is a paragraph of its own that shows only its first line.
  double shown = double.infinity;

  int _holders = 1;

  void _hold() => _holders++;

  void _release() {
    assert(_holders > 0, 'A piece was released more often than held.');
    if (--_holders > 0) return;
    paragraph.dispose();
    for (final (_, held) in inlines) {
      if (held is ui.Paragraph) held.dispose();
    }
  }
}

/// A drawn thing on the strip that is not text: a border, a list marker or
/// a block image.
sealed class Decoration {}

class RuleDecoration extends Decoration {
  RuleDecoration(this.rect);
  final ui.Rect rect;
}

class ImageDecoration extends Decoration {
  ImageDecoration(this.rect, this.path);
  final ui.Rect rect;
  final String path;
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
      final piece = slice.piece;
      if (piece == null) continue;
      for (var unit = slice.units.$2 - 1; unit >= slice.units.$1; unit--) {
        final place = piece.map.textPlaceAt(unit);
        if (place == null) continue;
        final text = dom.textAt(place)!.text;
        if (place.offset < text.length &&
            !isSpace(text.codeUnitAt(place.offset))) {
          return place;
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

  /// The paragraphs of the page's lines. Throws a [StateError] once the
  /// page is disposed.
  Iterable<Piece> get pieces {
    if (_disposed) throw StateError('The page is disposed.');
    return _lines;
  }

  Iterable<Piece> get _lines sync* {
    Piece? previous;
    for (final slice in slices) {
      final piece = slice.piece;
      if (piece != null && !identical(piece, previous)) {
        yield piece;
        previous = piece;
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
  LayoutRun(
    PreparedSection section, {
    PageStart? from,
    Duration Function()? clock,
  }) : _section = section,
       _clock = clock ?? _elapsed,
       _textStyles = [
         for (final style in section.styles)
           _textStyle(style, section.settings.ink),
       ] {
    final start = from ?? const PageStart(0, 0);
    if (start.item < 0 || start.item > section.flow.length) {
      throw RangeError.range(start.item, 0, section.flow.length, 'from.item');
    }
    if (start.line < 0) throw RangeError.value(start.line, 'from.line');
    _resume(start);
  }

  static final _watch = Stopwatch()..start();
  static Duration _elapsed() => _watch.elapsed;

  final PreparedSection _section;
  final Duration Function() _clock;
  final List<ui.TextStyle> _textStyles;

  final _pages = <LaidPage>[];
  bool _done = false;
  bool _disposed = false;

  /// The run's start, which is the section start when no slice comes
  /// before it.
  PageStart _from = const PageStart(0, 0);

  /// The next flow item, and the line of it to start at.
  int _item = 0;
  int _firstLine = 0;

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
        check(piece._holders > 0, 'a held piece is disposed');
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
    if (_done) {
      check(_item == _section.flow.length, 'a done run has items left');
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
    final flow = _section.flow;
    final open = <int>[];
    int? marker;
    var sliceBefore = false;
    for (var index = 0; index < start.item; index++) {
      switch (flow[index]) {
        case final BlockStart block:
          open.add(index);
          if (block.marker != null) marker = index;
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
        case ParagraphItem() || ImageItem():
          sliceBefore = true;
          marker = null;
      }
    }
    if (!sliceBefore && start.line == 0) return;
    _from = start;
    _pageStart = start;
    _item = start.item;
    _firstLine = start.line;
    _dropMargins = true;
    for (final index in open) {
      final block = flow[index] as BlockStart;
      final (left, contentWidth) = _placeBlock(block, index);
      final top = block.padding[0] + block.border[0];
      // The box's top edge is above the page. Its borders are clipped
      // there, so its exact place does not matter.
      _open.add(
        _OpenBlock(block, index, left, contentWidth, top > 0 ? -top : null, 0),
      );
    }
    // A marker waits for the first line of its item. Past that line, the
    // run from the section start already drew it.
    if (marker != null && start.line == 0) {
      final block = flow[marker] as BlockStart;
      final (left, _) = _placeBlock(block, marker);
      _marker(
        block.marker!.text,
        block.marker!.style,
        left + block.border[3] + block.padding[3],
      );
    }
  }

  (double, double) _placeBlock(BlockStart start, int item) {
    final placement = start.placement;
    return placement.place(
      start.shrinkToFit ? _maxContent(item + 1, placement.available) : null,
    );
  }

  // Cutting pages.

  void _layOutItem() {
    final flow = _section.flow;
    if (_item == flow.length) return;
    final index = _item++;
    final line = _firstLine;
    _firstLine = 0;
    switch (flow[index]) {
      case final BlockStart start:
        _openBlock(start, index);
      case BlockEnd():
        _closeBlock(index);
      case final ParagraphItem paragraph:
        final block = _open.last;
        _inline(paragraph, index, block.contentLeft, block.contentWidth, line);
      case final ImageItem image:
        _blockImage(image, index);
    }
  }

  /// Publishes every page that the slices laid out so far decide.
  void _cut() {
    const epsilon = 0.01;
    final atEnd = _item == _section.flow.length;
    while (!_done) {
      final count = _pending.length;
      final limit = _pageTop + _section.settings.height + epsilon;
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
  /// [bottom], and starts the next page after it.
  void _publish(int count, double bottom, {required bool last}) {
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
    _releaseUnreachable();
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
      for (final slice in _pending) ?slice.piece,
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
    final flow = _section.flow;
    for (var index = _from.item; index < flow.length; index++) {
      if (_firstPlace(_section.index, flow[index]) case final place?) {
        return _section.dom.visibleBefore(place);
      }
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
    );
    _pending.add(slice);
    _added++;
    return slice;
  }

  void _openBlock(BlockStart start, int item) {
    final (left, contentWidth) = _placeBlock(start, item);
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
  }) {
    final border = block.start.border;
    final rect = ui.Rect.fromLTRB(
      block.left,
      top,
      block.left + block.contentWidth + block.start.placement.horizontal,
      bottom,
    );
    return [
      if (border[0] > 0)
        RuleDecoration(
          ui.Rect.fromLTWH(rect.left, rect.top, rect.width, border[0]),
        ),
      if (closed && border[2] > 0)
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
  /// on, laid out [available] pixels wide, rounded up.
  double _maxContent(int from, double available) {
    final flow = _section.flow;
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
    _margin(image.marginTop);
    _resolveMargin();
    final rect = ui.Rect.fromLTWH(image.left, _y, image.width, image.height);
    if (image.path case final path?) {
      _decorations.add(ImageDecoration(rect, path));
    }
    final slice = _add(
      _y,
      _y + image.height,
      Appeal.perfect,
      PageStart(item, 0),
      start: EpubPlace(_section.index, image.node, 0),
    );
    _takeMarker(slice);
    _y += image.height;
    _margin(image.marginBottom);
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
        baseline = piece.y + lines[slice.line].baseline;
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

  static ui.TextStyle _textStyle(RunStyle style, ui.Color ink) => ui.TextStyle(
    color: ink,
    fontFamily: style.family,
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
      // The reader's @font-face rule names no weights, so Chromium draws
      // bold text as a thickened regular face with regular widths. Flutter
      // would pick the font's true bold, which is wider.
      const ui.FontVariation('wght', 400),
    ],
  );

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

  /// Builds the paragraph of [text], [width] pixels wide, from its code
  /// unit [from] on. Returns the paragraph, its map, and what each of its
  /// placeholders holds: null for the indent, an image's path, or a raised
  /// paragraph.
  _Built _build(StyledText text, double indent, double width, {int from = 0}) {
    final builder = ui.ParagraphBuilder(_paragraphStyle(text));
    final map = TextMap(_section.index);
    final inlines = <Object?>[];
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
          builder
            ..pushStyle(_textStyles[style])
            ..addText(written.substring(skip))
            ..pop();
          map.addText(node, Int32List.sublistView(run.offsets, skip));
        case BreakRun(:final node):
          final start = unit;
          unit += 1;
          if (start < from) continue;
          trim = false;
          builder.addText('\n');
          map.addPlaceholder(node);
        case ImageRun(:final node, :final path, :final sizing):
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
          inlines.add(path);
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
    return _Built(builder.build(), map, inlines);
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
      final built = _build(item.text, indent, width);
      built.paragraph.layout(ui.ParagraphConstraints(width: width));
      _place(built, x, item, index, from: from);
      return;
    }
    // A negative indent hangs the first line out to the left: lay it out
    // wider, then lay out the rest at the block's width.
    final first = _build(item.text, 0, width - indent);
    first.paragraph.layout(ui.ParagraphConstraints(width: width - indent));
    final count = first.paragraph.computeLineMetrics().length;
    if (count <= 1) {
      _place(first, x + indent, item, index, from: from);
      return;
    }
    final end = _lineStarts(first.paragraph, 2)[1];
    final rest = _build(item.text, 0, width, from: end);
    rest.paragraph.layout(ui.ParagraphConstraints(width: width));
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
    double bottomOf(int line) => line == metrics.length - 1
        ? paragraph.height
        : metrics[line].baseline + metrics[line].descent;
    var top = from == 0 ? 0.0 : bottomOf(from - 1);
    final piece = Piece(paragraph, x, _y - top, built.map);
    _held.add(piece);
    final boxes = paragraph.getBoxesForPlaceholders();
    for (var slot = 0; slot < built.inlines.length; slot++) {
      final held = built.inlines[slot];
      if (held == null) continue;
      if (slot < boxes.length) {
        piece.inlines.add((boxes[slot].toRect(), held));
      } else if (held is ui.Paragraph) {
        held.dispose();
      }
    }
    final starts = _lineStarts(paragraph, math.min(count + 1, metrics.length));
    for (var line = from; line < count; line++) {
      final bottom = bottomOf(line);
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
    _y = piece.y + (lines == null ? paragraph.height : top);
  }

  /// The first code unit of each of a paragraph's [count] lines.
  static List<int> _lineStarts(ui.Paragraph paragraph, int count) {
    final starts = <int>[];
    var offset = 0;
    for (var line = 0; line < count; line++) {
      starts.add(offset);
      final range = paragraph.getLineBoundary(ui.TextPosition(offset: offset));
      var next = math.max(range.end, offset + 1);
      // A hard break's newline belongs to the line that it ends.
      while (paragraph.getLineNumberAt(next) == line) {
        next++;
      }
      offset = next;
    }
    return starts;
  }
}

/// The page start of the line that holds [place], a place in [section]: the
/// last line that starts at or before it. A place in white space counts as
/// the next visible character of its node. It lays out one paragraph.
PageStart lineStart(PreparedSection section, EpubPlace place) {
  if (place.section != section.index) {
    throw ArgumentError.value(place, 'place', 'is not in this section');
  }
  final dom = section.dom;
  final key = _order(dom, place);
  final flow = section.flow;
  var item = -1;
  for (var index = 0; index < flow.length; index++) {
    final first = _firstPlace(section.index, flow[index]);
    if (first != null && _compare(_order(dom, first), key) <= 0) item = index;
  }
  if (item < 0) return const PageStart(0, 0);
  final run = LayoutRun(section, from: PageStart(item, 0));
  try {
    while (run._item <= item) {
      run._layOutItem();
    }
    Slice? found;
    for (final slice in run._pending) {
      if (slice.at.item != item) continue;
      final start = slice.start;
      if (found == null ||
          (start != null && _compare(_order(dom, start), key) <= 0)) {
        found = slice;
      }
    }
    // The item's first line starts where the run starts: at the section
    // start when nothing comes before it.
    if (found == null || found.at.line == 0) return run._from;
    return found.at;
  } finally {
    run.dispose();
  }
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
    case BlockStart() || BlockEnd():
      return null;
  }
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

  /// The index of the page that holds [place]: the last page that starts
  /// at or before it in document order.
  int pageAt(EpubPlace place) {
    final key = _order(section.dom, place);
    var found = 0;
    for (var index = 0; index < pages.length; index++) {
      final start = pages[index].startPlace;
      if (start != null && _compare(_order(section.dom, start), key) <= 0) {
        found = index;
      }
    }
    return found;
  }

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

class _Built {
  _Built(this.paragraph, this.map, this.inlines);
  final ui.Paragraph paragraph;
  final TextMap map;
  final List<Object?> inlines;

  /// Disposes the paragraph and the raised paragraphs in its placeholders.
  void dispose() {
    paragraph.dispose();
    for (final held in inlines) {
      if (held is ui.Paragraph) held.dispose();
    }
  }
}
