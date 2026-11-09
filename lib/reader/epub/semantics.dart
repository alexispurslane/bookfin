// What a screen reader reads of a laid page.
//
// A page reads as its text blocks and block images, in strip order. A text
// block is one paragraph of the section: its lines on this page, with a
// hanging first line, which layout draws as a paragraph of its own. Table
// cells are blocks of their own, cell by cell. A block's text is the
// book's own text: each code unit that a line shows names its character in
// the DOM, so the hyphens, soft hyphens and word joiners that layout
// inserts never reach the reader. A block splits into spans where a link
// or an image starts or ends.
import 'dart:ui' as ui;

import 'dom.dart';
import 'layout.dart';
import 'prepare.dart' show softHyphen;

/// One run of a block that a screen reader reads as one node: text outside
/// links, the text of one link, or one image.
class PageSpan {
  const PageSpan(this.label, this.rect, {this.image = false, this.link});

  /// The text, with its white space collapsed, or an image's alt text, or
  /// 'Image' for an image without alt text.
  final String label;

  /// Where the span is drawn, in logical pixels from the page's top left
  /// corner.
  final ui.Rect rect;
  final bool image;

  /// For a span in a link, a point of it, from the page's top left corner,
  /// where a tap follows the link. Null outside links.
  final ui.Offset? link;
}

/// A text block or a block image on a page.
class PageBlock {
  const PageBlock(this.rect, this.spans, {this.header = false});

  /// Where the block's lines or image are drawn, in logical pixels from the
  /// page's top left corner.
  final ui.Rect rect;

  /// The block's spans in reading order. Never empty.
  final List<PageSpan> spans;

  /// Whether the block is in a heading, h1 to h6.
  final bool header;
}

/// The text blocks and block images of [page], in reading order.
List<PageBlock> pageBlocks(LaidPage page) {
  final blocks = <PageBlock>[];
  final lines = <Slice>[];
  void close() {
    if (lines.isEmpty) return;
    if (_textBlock(page, lines) case final block?) blocks.add(block);
    lines.clear();
  }

  for (final slice in page.slices) {
    for (final line in slice.cellSlices.isEmpty ? [slice] : slice.cellSlices) {
      if (line.piece == null) {
        close();
        if (_imageBlock(page, line) case final block?) blocks.add(block);
        continue;
      }
      if (lines.isNotEmpty && !_continues(lines.last, line)) close();
      lines.add(line);
    }
  }
  close();
  return blocks;
}

/// Whether [line] is the line of the same paragraph after [before]: in
/// the same flow item and the next line of it, of the same piece or after
/// a hanging first line.
bool _continues(Slice before, Slice line) =>
    line.at.item == before.at.item &&
    line.at.line == before.at.line + 1 &&
    (identical(line.piece, before.piece) || before.at.line == 0);

/// The block of a block image [line], or null for a slice that shows no
/// image, such as a rule.
PageBlock? _imageBlock(LaidPage page, Slice line) {
  final start = line.start;
  if (start == null) return null;
  final element = page.dom.nodeAt(start.node);
  if (element is! DomElement || element.name != 'img') return null;
  final drawn = page.decorations
      .whereType<ImageDecoration>()
      .where((image) => image.rect.top == line.top)
      .firstOrNull;
  final rect =
      drawn?.rect.shift(ui.Offset(0, -page.top)) ??
      ui.Rect.fromLTRB(
        0,
        line.top - page.top,
        page.settings.width,
        line.bottom - page.top,
      );
  // linkAt finds no link on a block image, so a tap on it follows none.
  return PageBlock(rect, [PageSpan(_alt(element), rect, image: true)]);
}

String _alt(DomElement image) {
  final alt = image.attributes['alt']?.trim() ?? '';
  return alt.isEmpty ? 'Image' : alt;
}

/// The block of the paragraph [lines], or null when they read as nothing.
PageBlock? _textBlock(LaidPage page, List<Slice> lines) {
  final dom = page.dom;
  final spans = _Spans(page);
  EpubPlace? last;
  var rect = ui.Rect.zero;
  for (final (index, line) in lines.indexed) {
    final piece = line.piece!;
    final map = piece.map;
    final box = ui.Rect.fromLTWH(
      piece.x,
      line.top - page.top,
      piece.paragraph.width,
      line.bottom - line.top,
    );
    rect = index == 0 ? box : rect.expandToInclude(box);
    final (first, end) = line.units;
    for (var unit = first; unit < end; unit++) {
      if (map.textPlaceAt(unit) case final place?) {
        // Layout maps a hyphen, soft hyphen or word joiner that it inserts
        // to the letter before it, and a letter that a text transform
        // writes as two to that letter twice.
        if (place == last) continue;
        last = place;
        final text = dom.textAt(place)!;
        final char = text.text.codeUnitAt(place.offset);
        if (char == softHyphen) continue;
        spans.text(String.fromCharCode(char), _linkOf(text), line, unit);
        continue;
      }
      final order = map.nodeAt(unit);
      // A placeholder that no node owns is an indent.
      if (order < 0) continue;
      switch (dom.nodeAt(order)) {
        case final DomElement image when image.name == 'img':
          spans.image(_alt(image), _linkOf(image), line, unit);
        case final DomElement element:
          // A line break.
          spans.text(' ', _linkOf(element), line, unit);
        case final DomText raised:
          spans.text(
            _raised(dom, raised, map, unit),
            _linkOf(raised),
            line,
            unit,
          );
      }
    }
  }
  final read = spans.finish();
  if (read.isEmpty) return null;
  final start = lines.first.start;
  return PageBlock(
    rect,
    read,
    header: start != null && _inHeading(dom.nodeAt(start.node)),
  );
}

/// The text of the raised text, such as a superscript, whose first text
/// node is [first] and whose placeholder is code unit [unit] of [map]: the
/// text nodes from [first] up to the paragraph's next place. At the
/// paragraph's end, the text nodes from [first] to the end of its parent.
String _raised(DomSection dom, DomText first, TextMap map, int unit) {
  final end =
      map.placeAtUnit(unit + 1)?.node ?? first.parent!.texts.last.order + 1;
  final texts = dom.texts;
  final text = StringBuffer();
  for (
    var index = texts.indexOf(first);
    index >= 0 && index < texts.length && texts[index].order < end;
    index++
  ) {
    text.write(
      texts[index].text.replaceAll(String.fromCharCode(softHyphen), ''),
    );
  }
  return text.toString();
}

/// The nearest link that holds [node], or null.
DomElement? _linkOf(DomNode node) {
  var element = node is DomElement ? node : node.parent;
  while (element != null &&
      !(element.name == 'a' && element.attributes['href'] != null)) {
    element = element.parent;
  }
  return element;
}

bool _inHeading(DomNode node) {
  for (
    var element = node is DomElement ? node : node.parent;
    element != null;
    element = element.parent
  ) {
    if (const {'h1', 'h2', 'h3', 'h4', 'h5', 'h6'}.contains(element.name)) {
      return true;
    }
  }
  return false;
}

/// Builds the spans of one block, unit by unit.
class _Spans {
  _Spans(this._page);

  final LaidPage _page;
  final _spans = <PageSpan>[];

  /// The span in progress: its text, its link, and the code units that it
  /// covers, as runs of one line each.
  final _text = StringBuffer();
  DomElement? _link;
  final _runs = <(Slice, int, int)>[];

  /// Adds [text] from code unit [unit] of [line], in [link] or in none.
  void text(String text, DomElement? link, Slice line, int unit) {
    if (_runs.isNotEmpty && !identical(link, _link)) _close();
    _link = link;
    _text.write(text);
    _cover(line, unit);
  }

  /// Adds an image, labeled [label], at code unit [unit] of [line].
  void image(String label, DomElement? link, Slice line, int unit) {
    _close();
    _link = link;
    _text.write(label);
    _cover(line, unit);
    _close(image: true);
  }

  List<PageSpan> finish() {
    _close();
    return _spans;
  }

  void _cover(Slice line, int unit) {
    if (_runs.lastOrNull case (final last, final from, final to)
        when identical(last, line) && to == unit) {
      _runs.last = (line, from, unit + 1);
    } else {
      _runs.add((line, unit, unit + 1));
    }
  }

  void _close({bool image = false}) {
    final label = image
        ? _text.toString()
        : _text.toString().replaceAll(_space, ' ').trim();
    final runs = [..._runs];
    final link = _link;
    _text.clear();
    _runs.clear();
    _link = null;
    if (label.isEmpty || runs.isEmpty) return;
    final top = _page.top;
    ui.Rect? rect;
    for (final (line, from, to) in runs) {
      final piece = line.piece!;
      for (final box in piece.paragraph.getBoxesForRange(from, to)) {
        final drawn = box.toRect().shift(ui.Offset(piece.x, piece.y - top));
        rect = rect?.expandToInclude(drawn) ?? drawn;
      }
    }
    final (line, from, _) = runs.first;
    final piece = line.piece!;
    final first = piece.paragraph.getBoxesForRange(from, from + 1);
    rect ??= ui.Rect.fromLTRB(
      piece.x,
      line.top - top,
      piece.x + piece.paragraph.width,
      line.bottom - top,
    );
    _spans.add(
      PageSpan(
        label,
        rect,
        image: image,
        // The middle of the span's first character, across, and of its
        // line's exact place on the strip, down, so that linkAt finds that
        // line and that character.
        link: link == null
            ? null
            : ui.Offset(
                piece.x +
                    (first.isEmpty
                        ? 0
                        : (first.first.left + first.first.right) / 2),
                (line.top + line.bottom) / 2 - top,
              ),
      ),
    );
  }

  static final _space = RegExp(r'\s+');
}
