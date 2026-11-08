// Lays out one prepared section with Flutter's text engine and cuts it into
// pages. It runs on the UI isolate, because dart:ui paragraphs exist only
// there.
//
// The section flows down one strip as wide as the page, as a scrolled
// document would. Each line, image and rule is a slice of the strip. A page
// is a window [startY, endY) of the strip that holds whole slices, so a
// paragraph splits across pages between its lines. The breaks follow CSS
// fragmentation as Chromium applies it to the WebView reader's columns:
// margins at a break are dropped, `break-before: page` is ignored as the
// columns ignore it, and a break picks the latest place with the best
// "appeal" (orphans, widows and avoid rules).
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

/// A slice of the strip that a page holds whole: a line, an image or a
/// rule.
class Slice {
  Slice(this.top, this.bottom, this.appeal, {this.piece, this.line = -1});
  final double top;
  final double bottom;

  /// The appeal of a page break right before this slice.
  int appeal;

  /// The paragraph that holds this line, or null for an image or a rule.
  final Piece? piece;
  final int line;

  /// The place of the slice's first character, or null when it shows no
  /// text.
  EpubPlace? start;
}

/// One laid-out paragraph: a Flutter paragraph at a place on the strip,
/// and where each of its characters comes from in the DOM.
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
  MarkerDecoration(this.paragraph, this.offset);
  final ui.Paragraph paragraph;
  final ui.Offset offset;
}

/// One page: the window [startY, endY) of the strip, which holds slices
/// [firstSlice, endSlice).
class PageSlice {
  PageSlice(this.startY, this.endY, this.firstSlice, this.endSlice);
  final double startY;
  final double endY;
  final int firstSlice;
  final int endSlice;

  /// The place of the page's first text, or of its first image when it has
  /// no text, or null when it shows neither.
  EpubPlace? start;

  /// The number of visible characters of the section before [start].
  int startVisible = 0;
}

/// A laid-out section.
class ChapterLayout {
  ChapterLayout(this.section, this.slices, this.decorations)
    : pages = _paginate(slices, section.settings.height) {
    final dom = section.dom;
    // A page starts at its first text, as epub.js saves it, even when an
    // image comes first. A page without text starts at its image.
    for (final page in pages) {
      for (var index = page.firstSlice; index < page.endSlice; index++) {
        final start = slices[index].start;
        if (start == null) continue;
        page.start ??= start;
        if (dom.textAt(start) != null) {
          page.start = start;
          break;
        }
      }
    }
    var next = dom.visibleLength;
    for (final page in pages.reversed) {
      page.startVisible = page.start == null
          ? next
          : dom.visibleBefore(page.start!);
      next = page.startVisible;
    }
  }
  final PreparedSection section;
  final List<Slice> slices;
  final List<Decoration> decorations;
  final List<PageSlice> pages;

  PageSettings get settings => section.settings;

  /// The pieces with lines on [page].
  Iterable<Piece> piecesOn(PageSlice page) sync* {
    Piece? last;
    for (var index = page.firstSlice; index < page.endSlice; index++) {
      final piece = slices[index].piece;
      if (piece != null && !identical(piece, last)) {
        yield piece;
        last = piece;
      }
    }
  }

  /// The start of each line on [page], as a visible character index, for
  /// the fidelity comparison. A line without text, such as an image, is
  /// left out.
  List<int> lineStarts(PageSlice page) => [
    for (var index = page.firstSlice; index < page.endSlice; index++)
      if (slices[index].start case final start?
          when section.dom.textAt(start) != null)
        section.dom.visibleBefore(start),
  ];

  /// The index of the page that holds [place]: the last page that starts
  /// at or before it in document order.
  int pageAt(EpubPlace place) {
    final key = _key(place);
    var found = 0;
    for (var index = 0; index < pages.length; index++) {
      final start = pages[index].start;
      if (start != null && _compare(_key(start), key) <= 0) found = index;
    }
    return found;
  }

  /// The order of [place] in the document. A place in white space counts as
  /// the next visible character of its node, where a page or a line starts.
  (int, int) _key(EpubPlace place) {
    final text = section.dom.textAt(place);
    if (text == null) return (place.node, 0);
    var offset = place.offset;
    while (offset < text.text.length && isSpace(text.text.codeUnitAt(offset))) {
      offset++;
    }
    return (place.node, offset);
  }

  static int _compare((int, int) a, (int, int) b) =>
      a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2);

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

/// Lays out [section] and cuts it into pages.
ChapterLayout layoutSection(PreparedSection section) {
  final flow = _Flow(section)..run();
  return ChapterLayout(section, flow.slices, flow.decorations);
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
  final int firstSlice;

  double get contentLeft => left + start.border[3] + start.padding[3];
}

class _Flow {
  _Flow(this.section)
    : _textStyles = [
        for (final style in section.styles)
          _textStyle(style, section.settings.ink),
      ];
  final PreparedSection section;
  final List<ui.TextStyle> _textStyles;
  final slices = <Slice>[];
  final decorations = <Decoration>[];
  final _open = <_OpenBlock>[];
  double y = 0;
  double _positive = 0;
  double _negative = 0;
  bool _avoidNext = false;
  (ui.Paragraph, double)? _pendingMarker;

  void run() {
    final flow = section.flow;
    for (var index = 0; index < flow.length; index++) {
      switch (flow[index]) {
        case final BlockStart start:
          _openBlock(start, index);
        case BlockEnd():
          _closeBlock(index);
        case final ParagraphItem paragraph:
          final block = _open.last;
          _inline(paragraph, block.contentLeft, block.contentWidth);
        case final ImageItem image:
          _blockImage(image);
      }
    }
  }

  void margin(double value) {
    if (value > 0) _positive = math.max(_positive, value);
    if (value < 0) _negative = math.min(_negative, value);
  }

  void resolveMargin() {
    y += _positive + _negative;
    _positive = 0;
    _negative = 0;
  }

  void avoidNextBreak() => _avoidNext = true;

  Slice add(
    double top,
    double bottom,
    int appeal, {
    Piece? piece,
    int line = -1,
  }) {
    var finalAppeal = appeal;
    if (_avoidNext) {
      finalAppeal = math.min(finalAppeal, Appeal.violatingAvoid);
      _avoidNext = false;
    }
    final slice = Slice(top, bottom, finalAppeal, piece: piece, line: line);
    slices.add(slice);
    return slice;
  }

  void _openBlock(BlockStart start, int item) {
    final placement = start.placement;
    final (left, contentWidth) = placement.place(
      start.shrinkToFit ? _maxContent(item + 1, placement.available) : null,
    );
    margin(start.marginTop);
    final top = start.padding[0] + start.border[0];
    double? boxTop;
    if (top > 0) {
      resolveMargin();
      boxTop = y;
      y += top;
    }
    final block = _OpenBlock(
      start,
      item,
      left,
      contentWidth,
      boxTop,
      slices.length,
    );
    _open.add(block);
    if (start.marker case final marker?) {
      _marker(marker.text, marker.style, block.contentLeft);
    }
    if (start.avoidBreakBefore) avoidNextBreak();
  }

  void _closeBlock(int item) {
    final block = _open.removeLast();
    final start = block.start;
    final border = start.border;
    final bottom = start.padding[2] + border[2];
    var boxTop = block.boxTop;
    if (bottom > 0 || boxTop != null) {
      resolveMargin();
      boxTop ??= y;
      y += bottom;
    }
    // A box without content ends right after it starts. With a height,
    // such as a rule, it is one slice.
    if (item == block.item + 1 && boxTop != null && y > boxTop) {
      add(boxTop, y, Appeal.perfect);
    }
    if (border.any((side) => side > 0) && boxTop != null) {
      final rect = ui.Rect.fromLTRB(
        block.left,
        boxTop,
        block.left + block.contentWidth + start.placement.horizontal,
        y,
      );
      if (border[0] > 0) {
        decorations.add(
          RuleDecoration(
            ui.Rect.fromLTWH(rect.left, rect.top, rect.width, border[0]),
          ),
        );
      }
      if (border[2] > 0) {
        decorations.add(
          RuleDecoration(
            ui.Rect.fromLTWH(
              rect.left,
              rect.bottom - border[2],
              rect.width,
              border[2],
            ),
          ),
        );
      }
      if (border[3] > 0) {
        decorations.add(
          RuleDecoration(
            ui.Rect.fromLTWH(rect.left, rect.top, border[3], rect.height),
          ),
        );
      }
      if (border[1] > 0) {
        decorations.add(
          RuleDecoration(
            ui.Rect.fromLTWH(
              rect.right - border[1],
              rect.top,
              border[1],
              rect.height,
            ),
          ),
        );
      }
    }
    if (start.avoidBreakInside) {
      for (var index = block.firstSlice + 1; index < slices.length; index++) {
        slices[index].appeal = math.min(
          slices[index].appeal,
          Appeal.violatingAvoid,
        );
      }
    }
    margin(start.marginBottom);
    if (start.avoidBreakAfter) avoidNextBreak();
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
    _pendingMarker = (paragraph, contentLeft - paragraph.maxIntrinsicWidth);
  }

  /// The width of the widest line of the paragraphs from flow item [from]
  /// on, laid out [available] pixels wide, rounded up.
  double _maxContent(int from, double available) {
    final flow = section.flow;
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

  void _blockImage(ImageItem image) {
    margin(image.marginTop);
    resolveMargin();
    final rect = ui.Rect.fromLTWH(image.left, y, image.width, image.height);
    if (image.path case final path?) {
      decorations.add(ImageDecoration(rect, path));
    }
    final slice = add(y, y + image.height, Appeal.perfect)
      ..start = EpubPlace(section.index, image.node, 0);
    _takeMarker(slice);
    y += image.height;
    margin(image.marginBottom);
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
    final offset = ui.Offset(
      x,
      baseline - (metrics.isEmpty ? 0 : metrics.first.baseline),
    );
    decorations.add(MarkerDecoration(paragraph, offset));
  }

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
    final container = section.styles[text.style];
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
    final map = TextMap(section.index);
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

  void _inline(ParagraphItem item, double x, double width) {
    final indent = item.indent.resolve(width);
    resolveMargin();
    if (indent >= 0) {
      final built = _build(item.text, indent, width);
      built.paragraph.layout(ui.ParagraphConstraints(width: width));
      _place(built, x, item);
      return;
    }
    // A negative indent hangs the first line out to the left: lay it out
    // wider, then lay out the rest at the block's width.
    final first = _build(item.text, 0, width - indent);
    first.paragraph.layout(ui.ParagraphConstraints(width: width - indent));
    final count = first.paragraph.computeLineMetrics().length;
    if (count <= 1) {
      _place(first, x + indent, item);
      return;
    }
    final end = _lineStarts(first.paragraph, 2)[1];
    final rest = _build(item.text, 0, width, from: end);
    rest.paragraph.layout(ui.ParagraphConstraints(width: width));
    final total = 1 + rest.paragraph.computeLineMetrics().length;
    _place(first, x + indent, item, lines: 1, total: total);
    _place(rest, x, item, before: 1, total: total);
  }

  /// Adds the lines of [built], drawn at [x], to the strip: all of them,
  /// or the first [lines]. They are lines [before] on of a paragraph of
  /// [total] lines, for the orphans and widows rules of [item].
  void _place(
    _Built built,
    double x,
    ParagraphItem item, {
    int? lines,
    int before = 0,
    int? total,
  }) {
    final paragraph = built.paragraph;
    final piece = Piece(paragraph, x, y, built.map);
    final boxes = paragraph.getBoxesForPlaceholders();
    for (var index = 0; index < boxes.length; index++) {
      final held = index < built.inlines.length ? built.inlines[index] : null;
      if (held != null) piece.inlines.add((boxes[index].toRect(), held));
    }
    final metrics = paragraph.computeLineMetrics();
    final count = lines ?? metrics.length;
    final all = total ?? metrics.length;
    final starts = _lineStarts(paragraph, count);
    var top = 0.0;
    for (var line = 0; line < count; line++) {
      final bottom = line == metrics.length - 1
          ? paragraph.height
          : metrics[line].baseline + metrics[line].descent;
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
      final slice = add(y + top, y + bottom, appeal, piece: piece, line: line)
        ..start = built.map.placeAtUnit(starts[line]);
      if (above == 0) _takeMarker(slice);
      top = bottom;
    }
    if (lines != null) piece.shown = top;
    y += lines == null ? paragraph.height : top;
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

List<PageSlice> _paginate(List<Slice> slices, double height) {
  final pages = <PageSlice>[];
  var start = 0;
  var top = 0.0;
  const epsilon = 0.01;
  while (start < slices.length) {
    final limit = top + height + epsilon;
    var end = start;
    while (end < slices.length && slices[end].bottom <= limit) {
      end++;
    }
    if (end == slices.length) {
      pages.add(PageSlice(top, math.max(slices.last.bottom, top), start, end));
      break;
    }
    int next;
    double nextTop;
    if (end == start) {
      // A slice taller than the page gets a page of its own.
      next = start + 1;
      nextTop = next < slices.length ? slices[next].top : slices[start].bottom;
    } else {
      next = end;
      for (var candidate = end - 1; candidate > start; candidate--) {
        if (slices[candidate].appeal > slices[next].appeal) next = candidate;
      }
      nextTop = slices[next].top;
    }
    pages.add(PageSlice(top, nextTop, start, next));
    start = next;
    top = nextTop;
  }
  if (pages.isEmpty) pages.add(PageSlice(0, 0, 0, 0));
  return pages;
}
