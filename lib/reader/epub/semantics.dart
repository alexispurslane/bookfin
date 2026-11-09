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
      if (lines.isNotEmpty && !continuesParagraph(lines.last, line)) close();
      lines.add(line);
    }
  }
  close();
  return blocks;
}

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

/// What one code unit of a line on a page shows of the book.
sealed class BookUnit {
  const BookUnit(this.line, this.unit, this.node);

  /// The line, and the code unit of its piece's text.
  final Slice line;
  final int unit;

  /// The DOM node that the unit shows: a text node or an element.
  final DomNode node;
}

/// A character of the book's text, or the whole text of raised text, such
/// as a note number. The book's soft hyphens are left out.
final class BookText extends BookUnit {
  const BookText(super.line, super.unit, super.node, this.text);

  /// The DOM's own text. White space is as the DOM has it: a space, a tab
  /// or a line end.
  final String text;
}

/// A line break: a `br` element.
final class BookBreak extends BookUnit {
  const BookBreak(super.line, super.unit, super.node);
}

/// An inline image.
final class BookImage extends BookUnit {
  const BookImage(super.line, super.unit, DomElement super.image);
  DomElement get image => node as DomElement;
}

/// The book's own text that [page] shows in [runs], unit by unit, in
/// order. Each run is a text line of the page and the code units of its
/// piece, [from, to). Each DOM character comes once, so the hyphens, soft
/// hyphens and word joiners that layout inserts never appear. A
/// placeholder that no node owns, such as an indent, shows nothing.
Iterable<BookUnit> bookUnits(
  LaidPage page,
  Iterable<(Slice, int, int)> runs,
) sync* {
  final dom = page.dom;
  EpubPlace? last;
  for (final (line, from, to) in runs) {
    final map = line.piece!.map;
    // A run that starts after its paragraph's first unit, as a selection
    // can, starts after the unit before it.
    if (from > 0) last = map.textPlaceAt(from - 1) ?? last;
    for (var unit = from; unit < to; unit++) {
      if (map.textPlaceAt(unit) case final place?) {
        // Layout maps a hyphen, soft hyphen or word joiner that it inserts
        // to the letter before it, and a letter that a text transform
        // writes as two to that letter twice.
        if (place == last) continue;
        last = place;
        final text = dom.textAt(place)!;
        final char = text.text.codeUnitAt(place.offset);
        if (char == softHyphen) continue;
        yield BookText(line, unit, text, String.fromCharCode(char));
        continue;
      }
      final order = map.nodeAt(unit);
      if (order < 0) continue;
      switch (dom.nodeAt(order)) {
        case final DomElement image when image.name == 'img':
          yield BookImage(line, unit, image);
        case final DomElement element:
          yield BookBreak(line, unit, element);
        case final DomText raised:
          yield BookText(line, unit, raised, _raised(dom, raised, map, unit));
      }
    }
  }
}

/// Whether [line] is the line of the same paragraph after [before]: in
/// the same flow item and the next line of it, of the same piece or after
/// a hanging first line.
bool continuesParagraph(Slice before, Slice line) =>
    line.at.item == before.at.item &&
    line.at.line == before.at.line + 1 &&
    (identical(line.piece, before.piece) || before.at.line == 0);

/// The block of the paragraph [lines], or null when they read as nothing.
PageBlock? _textBlock(LaidPage page, List<Slice> lines) {
  final dom = page.dom;
  final spans = _Spans(page);
  var rect = ui.Rect.zero;
  for (final (index, line) in lines.indexed) {
    final piece = line.piece!;
    final box = ui.Rect.fromLTWH(
      piece.x,
      line.top - page.top,
      piece.paragraph.width,
      line.bottom - line.top,
    );
    rect = index == 0 ? box : rect.expandToInclude(box);
  }
  final runs = [for (final line in lines) (line, line.units.$1, line.units.$2)];
  for (final shown in bookUnits(page, runs)) {
    final BookUnit(:line, :unit, :node) = shown;
    switch (shown) {
      case BookText(:final text):
        spans.text(text, _linkOf(node), line, unit);
      case BookBreak():
        spans.text(' ', _linkOf(node), line, unit);
      case BookImage(:final image):
        spans.image(_alt(image), _linkOf(image), line, unit);
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
