// Lays out one spine section with Flutter's text engine and cuts it into
// pages, for the trial renderer.
//
// The section flows down one strip as wide as the page, as a scrolled
// document would. Each line, image and rule is a slice of the strip. A page
// is a window [startY, endY) of the strip that holds whole slices, so a
// paragraph splits across pages between its lines. The breaks follow CSS
// fragmentation as Chromium applies it to the WebView reader's columns:
// margins at an unforced break are dropped, a forced break keeps the margin
// after it, and a break picks the latest place with the best "appeal"
// (orphans, widows and avoid rules).
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'css.dart';
import 'dom.dart';

/// The page size and the reader settings that a layout depends on. The
/// defaults are the WebView reader's: a 412 × 671 pixel page, 20 pixel
/// Source Serif 4 at line height 1.65.
class PageTheme {
  const PageTheme({
    this.width = 412,
    this.height = 671,
    this.fontSize = 20,
    this.fontFamily = 'Source Serif 4',
    this.lineHeight = 1.65,
    this.night = false,
    this.pageBreaks = false,
    this.syntheticBold = true,
  });
  final double width;
  final double height;
  final double fontSize;
  final String fontFamily;
  final double lineHeight;
  final bool night;

  /// Whether `break-before: page` and `break-after: page` start a new page.
  /// The WebView reader lays a section out in CSS columns, where Chromium
  /// ignores page breaks, so the default matches it.
  final bool pageBreaks;

  /// Whether bold text is the regular face thickened, as the WebView reader
  /// draws it, rather than the font's true bold.
  final bool syntheticBold;

  /// The horizontal padding of the page's body: half the column gap that
  /// epub.js uses, a twelfth of the width rounded down to an even number.
  double get sideMargin {
    final section = (width / 12).floor();
    return (section.isEven ? section : section - 1) / 2;
  }

  ui.Color get paper =>
      night ? const ui.Color(0xff251e19) : const ui.Color(0xfff6efe2);
  ui.Color get ink =>
      night ? const ui.Color(0xffdcc9a9) : const ui.Color(0xff39291f);

  /// The rules that the WebView reader adds to each section: epub.js's
  /// theme and image rules and the reader's own style.
  String get readerCss {
    final side = sideMargin;
    final imageWidth = width - 2 * side;
    final imageHeight = height * .95;
    // epub.js adds its image rules first and the reader's style after
    // them, so the reader's max-width wins.
    return 'html{font-family:BookfinSerif,"Source Serif 4",serif}'
        'img{max-width:${imageWidth}px!important;'
        'max-height:${imageHeight}px!important;break-inside:avoid;'
        'box-sizing:border-box}'
        'body{overflow-wrap:break-word;line-height:$lineHeight!important;'
        'padding:0 18px!important}'
        'img{max-width:100%!important;height:auto}';
  }

  /// The declarations that epub.js sets on the body element itself.
  List<Declaration> get bodyOverrides => [
    Declaration('font-size', '${fontSize}px', false),
    Declaration('margin', '0', true),
    Declaration('padding-top', '20px', false),
    Declaration('padding-bottom', '20px', false),
    Declaration('padding-left', '${sideMargin}px', true),
    Declaration('padding-right', '${sideMargin}px', true),
    Declaration('box-sizing', 'border-box', false),
  ];
}

/// One spine section and the publication files that it uses.
class SectionInput {
  const SectionInput(this.path, this.xhtml, this.resource);

  /// The section's path in the publication, such as `epub/text/one.xhtml`.
  final String path;
  final String xhtml;

  /// The bytes of the publication file at a path, or null.
  final Uint8List? Function(String path) resource;
}

/// A section that is parsed and styled, ready for layout at any page size
/// whose media conditions match.
class PreparedSection {
  PreparedSection._(this.input, this.dom, this.styles, this.imageSizes);
  final SectionInput input;
  final DomSection dom;

  /// The computed style of each element of the document.
  final Map<DomElement, Style> styles;

  /// The intrinsic size of each image, by its path.
  final Map<String, ui.Size> imageSizes;
}

/// Parses [input], applies its style sheets and the reader's rules for
/// [theme], and reads the size of each image that it shows.
Future<PreparedSection> prepareSection(
  SectionInput input,
  PageTheme theme,
) async {
  final prepared = styleSection(input, theme);
  final images = <String>{
    for (final element in _elements(prepared.dom.body))
      if (element.name == 'img')
        ?resolvePath(input.path, element.attributes['src'] ?? ''),
  };
  await Future.wait([
    for (final path in images)
      if (input.resource(path) case final bytes?)
        _imageSize(bytes).then((size) {
          if (size != null) prepared.imageSizes[path] = size;
        }),
  ]);
  return prepared;
}

/// The parsed and styled section of [input], without image sizes.
PreparedSection styleSection(SectionInput input, PageTheme theme) {
  final dom = DomSection.parse(input.xhtml);
  final media = MediaContext(width: theme.width, height: theme.height);
  final rules = <StyleRule>[
    ...userAgentSheet.rules,
    for (final sheet in sectionSheets(input, dom, media)) ...sheet.rules,
    ...StyleSheet.parse(
      theme.readerCss,
      firstOrder: 1 << 30,
      media: media,
    ).rules,
  ];
  final cascade = Cascade(rules, overrides: {dom.body: theme.bodyOverrides});
  final styles = <DomElement, Style>{};
  final initial = Style.initial();
  final rootStyle = cascade.compute(dom.root, initial, initial.fontSize);
  styles[dom.root] = rootStyle;
  void visit(DomElement element, Style parent) {
    for (final child in element.elements) {
      final style = cascade.compute(child, parent, rootStyle.fontSize);
      styles[child] = style;
      visit(child, style);
    }
  }

  visit(dom.root, rootStyle);
  return PreparedSection._(input, dom, styles, {});
}

/// The book's style sheets that section [dom] uses, linked or in style
/// elements, in document order.
List<StyleSheet> sectionSheets(
  SectionInput input,
  DomSection dom,
  MediaContext media,
) {
  final sheets = <StyleSheet>[];
  var order = 1000;
  for (final element in _elements(dom.root)) {
    String? css;
    if (element.name == 'link' &&
        (element.attributes['rel'] ?? '').toLowerCase().contains(
          'stylesheet',
        )) {
      final path = resolvePath(input.path, element.attributes['href'] ?? '');
      final bytes = path == null ? null : input.resource(path);
      if (bytes != null) css = _decode(bytes);
    } else if (element.name == 'style') {
      css = element.texts.map((text) => text.text).join();
    }
    if (css == null) continue;
    final sheet = StyleSheet.parse(css, firstOrder: order, media: media);
    sheets.add(sheet);
    order += sheet.rules.length + sheet.pseudoRules.length + 1;
  }
  return sheets;
}

/// [root] and every element inside it, in document order.
Iterable<DomElement> elementsOf(DomElement root) => _elements(root);

String _decode(Uint8List bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return String.fromCharCodes(bytes);
  }
}

Future<ui.Size?> _imageSize(Uint8List bytes) async {
  try {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final size = ui.Size(
      descriptor.width.toDouble(),
      descriptor.height.toDouble(),
    );
    descriptor.dispose();
    buffer.dispose();
    return size;
  } catch (_) {
    return null;
  }
}

Iterable<DomElement> _elements(DomElement root) sync* {
  yield root;
  for (final child in root.elements) {
    yield* _elements(child);
  }
}

/// The publication path that [reference] in the file at [base] names, or
/// null when it leaves the publication.
String? resolvePath(String base, String reference) {
  if (reference.isEmpty || reference.contains(':')) return null;
  final path = Uri.decodeComponent(reference.split('#').first);
  final parts = base.split('/')..removeLast();
  for (final part in path.split('/')) {
    if (part == '.' || part.isEmpty) continue;
    if (part == '..') {
      if (parts.isEmpty) return null;
      parts.removeLast();
    } else {
      parts.add(part);
    }
  }
  return parts.join('/');
}

/// Chromium's default style for the elements that books use.
final userAgentSheet = StyleSheet.parse('''
html, address, blockquote, body, center, div, figure, figcaption, footer,
form, header, hr, legend, listing, main, p, plaintext, pre, xmp, article,
aside, h1, h2, h3, h4, h5, h6, hgroup, nav, section, dl, dt, dd, ol, ul, menu,
dir, details, summary, fieldset, table, caption, thead, tbody, tfoot, tr, td,
th, colgroup, col { display: block }
li { display: list-item }
head, link, meta, script, style, title, template, area, base, datalist,
noscript, param, rp, [hidden] { display: none }
body { margin: 8px }
p, dl, multicol { margin: 1em 0 }
blockquote, figure { margin: 1em 40px }
h1 { font-size: 2em; margin: .67em 0; font-weight: bold }
article h1, aside h1, nav h1, section h1 { font-size: 1.5em; margin: .83em 0 }
h2 { font-size: 1.5em; margin: .83em 0; font-weight: bold }
h3 { font-size: 1.17em; margin: 1em 0; font-weight: bold }
h4 { margin: 1.33em 0; font-weight: bold }
h5 { font-size: .83em; margin: 1.67em 0; font-weight: bold }
h6 { font-size: .67em; margin: 2.33em 0; font-weight: bold }
hr { margin: .5em auto; border-style: inset; border-width: 1px }
ul, menu, dir { list-style-type: disc; margin: 1em 0; padding-left: 40px }
ol { list-style-type: decimal; margin: 1em 0; padding-left: 40px }
ul ul, ol ul, ul ol, ol ol, ul menu, ol menu { margin-top: 0; margin-bottom: 0 }
ul ul, ol ul, menu ul { list-style-type: circle }
dd { margin-left: 40px }
pre, xmp, plaintext, listing, code, kbd, samp, tt { font-family: monospace }
pre, xmp, plaintext, listing { white-space: pre; margin: 1em 0 }
b, strong { font-weight: bolder }
i, cite, em, var, dfn, address { font-style: italic }
small { font-size: smaller }
big { font-size: larger }
sub { vertical-align: sub; font-size: smaller }
sup { vertical-align: super; font-size: smaller }
u, ins, a:link { text-decoration: underline }
s, strike, del { text-decoration: line-through }
center { text-align: center }
th { font-weight: bold }
''');

// The layout model.

/// A position in the section's DOM: a character offset in a text node, or
/// an element such as an image.
class DomPosition {
  const DomPosition.text(DomText this.text, this.offset) : element = null;
  const DomPosition.element(DomElement this.element) : text = null, offset = 0;
  final DomText? text;
  final DomElement? element;
  final int offset;
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

  /// The place of a forced page break before this slice, or null.
  double? forcedBreak;

  /// The paragraph that holds this line, or null for an image or a rule.
  final Piece? piece;
  final int line;

  /// The DOM position of the slice's first character, or null when it
  /// shows no text.
  DomPosition? start;
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

  /// The DOM position of the page's first text, or of its first image when
  /// it has no text, or null when it shows neither.
  DomPosition? start;

  /// The number of visible characters of the section before [start].
  int startVisible = 0;
}

/// A laid-out section.
class ChapterLayout {
  ChapterLayout(this.section, this.theme, this.slices, this.decorations)
    : pages = _paginate(slices, theme.height) {
    // A page starts at its first text, as epub.js saves it, even when an
    // image comes first. A page without text starts at its image.
    for (final page in pages) {
      for (var index = page.firstSlice; index < page.endSlice; index++) {
        final start = slices[index].start;
        if (start == null) continue;
        page.start ??= start;
        if (start.text != null) {
          page.start = start;
          break;
        }
      }
    }
    var next = section.dom.visibleLength;
    for (final page in pages.reversed) {
      page.startVisible = page.start == null
          ? next
          : visibleIndex(section.dom, page.start!);
      next = page.startVisible;
    }
  }
  final PreparedSection section;
  final PageTheme theme;
  final List<Slice> slices;
  final List<Decoration> decorations;
  final List<PageSlice> pages;

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
      if (slices[index].start case final start? when start.text != null)
        visibleIndex(section.dom, start),
  ];

  /// The index of the page that holds [position]: the last page that
  /// starts at or before it in document order.
  int pageAt(DomPosition position) {
    final key = _key(position);
    var found = 0;
    for (var index = 0; index < pages.length; index++) {
      final start = pages[index].start;
      if (start != null && _compare(_key(start), key) <= 0) found = index;
    }
    return found;
  }

  /// The order of [position] in the document. A place in white space
  /// counts as the next visible character of its node, where a page or a
  /// line starts.
  static (int, int) _key(DomPosition position) {
    final text = position.text;
    if (text == null) return (position.element!.order, 0);
    var offset = position.offset;
    while (offset < text.text.length && isSpace(text.text.codeUnitAt(offset))) {
      offset++;
    }
    return (text.order, offset);
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

/// The number of visible characters of [section] before [position].
int visibleIndex(DomSection section, DomPosition position) {
  final text = position.text;
  if (text != null) {
    return text.visibleBefore + visibleCount(text.text, 0, position.offset);
  }
  // An element's place is the first text in or after it.
  return section.textFrom(position.element!)?.visibleBefore ??
      section.visibleLength;
}

// Box building.

sealed class _Box {}

class _BlockBox extends _Box {
  _BlockBox(this.element, this.style, this.children, {this.marker});
  final DomElement element;
  final Style style;
  final List<_Box> children;
  final String? marker;
}

/// An anonymous block of inline content.
class _InlineBox extends _Box {
  _InlineBox(this.items, this.container, this.first);
  final List<_Item> items;
  final Style container;

  /// Whether this is the first box of its block, whose first line takes the
  /// block's text-indent.
  final bool first;
}

sealed class _Item {}

class _TextItem extends _Item {
  _TextItem(this.node, this.style);
  final DomText node;
  final Style style;
}

class _ImageItem extends _Item {
  _ImageItem(this.element, this.style);
  final DomElement element;
  final Style style;
}

class _BreakItem extends _Item {
  _BreakItem(this.element);
  final DomElement element;
}

/// Raised or lowered text, laid out as its own small paragraph in a
/// placeholder.
class _RaisedItem extends _Item {
  _RaisedItem(this.element, this.style, this.items);
  final DomElement element;
  final Style style;
  final List<_Item> items;
}

class _BoxBuilder {
  _BoxBuilder(this.styles);
  final Map<DomElement, Style> styles;

  _BlockBox block(DomElement element, {String? marker}) {
    final style = styles[element]!;
    final children = <_Box>[];
    final run = <_Item>[];
    void flush() {
      if (run.any(_shows)) {
        children.add(_InlineBox(List.of(run), style, children.isEmpty));
      }
      run.clear();
    }

    var ordinal = 0;
    final ordered = element.name == 'ol';
    final start = int.tryParse(element.attributes['start'] ?? '') ?? 1;
    void walk(DomNode node, Style parent) {
      if (node is DomText) {
        run.add(_TextItem(node, parent));
        return;
      }
      final child = node as DomElement;
      final childStyle = styles[child]!;
      // An absolutely placed box leaves the flow. Books use it to move
      // text off the page; the support check reports other uses.
      if (childStyle.display == Display.none ||
          childStyle.position == 'absolute' ||
          childStyle.position == 'fixed') {
        return;
      }
      if (child.name == 'br') {
        run.add(_BreakItem(child));
        return;
      }
      if (child.name == 'img') {
        if (childStyle.display == Display.inline) {
          run.add(_ImageItem(child, childStyle));
        } else {
          flush();
          children.add(_BlockBox(child, childStyle, const []));
        }
        return;
      }
      if (childStyle.display != Display.inline) {
        flush();
        String? childMarker;
        if (childStyle.display == Display.listItem) {
          childMarker = _marker(
            childStyle.listStyleType,
            ordered ? start + ordinal : ordinal + 1,
          );
          ordinal++;
        }
        children.add(block(child, marker: childMarker));
        return;
      }
      if (childStyle.verticalAlign != VerticalAlign.baseline) {
        final inner = <_Item>[];
        _inlineItems(child, childStyle, inner);
        run.add(_RaisedItem(child, childStyle, inner));
        return;
      }
      for (final grandchild in child.children) {
        walk(grandchild, childStyle);
      }
    }

    for (final child in element.children) {
      walk(child, style);
    }
    flush();
    return _BlockBox(element, style, children, marker: marker);
  }

  void _inlineItems(DomElement element, Style style, List<_Item> out) {
    for (final child in element.children) {
      if (child is DomText) {
        out.add(_TextItem(child, style));
      } else if (child is DomElement) {
        final childStyle = styles[child]!;
        if (childStyle.display == Display.none) continue;
        if (child.name == 'br') {
          out.add(_BreakItem(child));
        } else {
          _inlineItems(child, childStyle, out);
        }
      }
    }
  }

  static bool _shows(_Item item) => switch (item) {
    _TextItem(:final node, :final style) =>
      style.whiteSpace == WhiteSpace.pre ||
              style.whiteSpace == WhiteSpace.preWrap
          ? node.text.isNotEmpty
          : visibleCount(node.text, 0, node.text.length) > 0,
    _ => true,
  };
}

String? _marker(String type, int number) {
  String alpha(int value, int base) {
    var result = '';
    for (var rest = value; rest > 0; rest = (rest - 1) ~/ 26) {
      result = String.fromCharCode(base + (rest - 1) % 26) + result;
    }
    return result;
  }

  String roman(int value) {
    const numerals = [
      (1000, 'm'),
      (900, 'cm'),
      (500, 'd'),
      (400, 'cd'),
      (100, 'c'),
      (90, 'xc'),
      (50, 'l'),
      (40, 'xl'),
      (10, 'x'),
      (9, 'ix'),
      (5, 'v'),
      (4, 'iv'),
      (1, 'i'),
    ];
    var rest = value;
    final buffer = StringBuffer();
    for (final (amount, letters) in numerals) {
      while (rest >= amount) {
        buffer.write(letters);
        rest -= amount;
      }
    }
    return buffer.toString();
  }

  return switch (type) {
    'none' => null,
    'disc' => '• ',
    'circle' => '◦ ',
    'square' => '▪ ',
    'decimal' => '$number. ',
    'lower-alpha' || 'lower-latin' => '${alpha(number, 0x61)}. ',
    'upper-alpha' || 'upper-latin' => '${alpha(number, 0x41)}. ',
    'lower-roman' => '${roman(number)}. ',
    'upper-roman' => '${roman(number).toUpperCase()}. ',
    _ => '$number. ',
  };
}

// Inline layout.

/// Where each code unit of a paragraph's text comes from: a text node and
/// an offset in it, or an element for a placeholder.
class TextMap {
  final starts = <int>[];
  final nodes = <Object?>[];
  final offsets = <Int32List?>[];
  int length = 0;

  void addText(DomText node, List<int> domOffsets) {
    starts.add(length);
    nodes.add(node);
    offsets.add(Int32List.fromList(domOffsets));
    length += domOffsets.length;
  }

  void addPlaceholder(Object? owner) {
    starts.add(length);
    nodes.add(owner);
    offsets.add(null);
    length += 1;
  }

  /// The DOM position of code unit [index], or of the next one that has
  /// text, or null when none follows.
  DomPosition? positionAt(int index) {
    var segment = _segment(index);
    for (; segment < starts.length; segment++) {
      final node = nodes[segment];
      final local = math.max(0, index - starts[segment]);
      final units = offsets[segment];
      if (node is DomText && units != null) {
        if (local < units.length) return DomPosition.text(node, units[local]);
      } else if (node is DomText && local == 0) {
        // Raised text in a placeholder starts at its first text node.
        return DomPosition.text(node, 0);
      } else if (node is DomElement && local == 0) {
        return DomPosition.element(node);
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

class _Flow {
  _Flow(this.theme, this.section);
  final PageTheme theme;
  final PreparedSection section;
  final slices = <Slice>[];
  final decorations = <Decoration>[];
  final _styles = <Style, ui.TextStyle>{};
  double y = 0;
  double _positive = 0;
  double _negative = 0;
  double? _forced;
  bool _avoidNext = false;

  void margin(double value) {
    if (value > 0) _positive = math.max(_positive, value);
    if (value < 0) _negative = math.min(_negative, value);
  }

  void resolveMargin() {
    y += _positive + _negative;
    _positive = 0;
    _negative = 0;
  }

  /// A forced break before the next slice. The margins before it are
  /// dropped.
  void forceBreak() {
    if (slices.isEmpty) return;
    _positive = 0;
    _negative = 0;
    _forced = y;
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
    if (_forced != null) {
      slice.forcedBreak = _forced;
      _forced = null;
    }
    slices.add(slice);
    return slice;
  }

  void block(_BlockBox box, double x, double width) {
    final style = box.style;
    if (style.breakBefore == BreakRule.page && theme.pageBreaks) forceBreak();
    final marginLeft = style.margin[3].resolve(width);
    final marginRight = style.margin[1].resolve(width);
    final padding = [for (final side in style.padding) side.resolve(width)];
    final border = [
      for (var side = 0; side < 4; side++) style.usedBorder(side),
    ];
    final horizontal = padding[1] + padding[3] + border[1] + border[3];
    var contentWidth = width - marginLeft - marginRight - horizontal;
    var left = x + marginLeft;
    if (box.element.name == 'img') {
      _blockImage(box, x, width);
      return;
    }
    final specified = style.width.resolveOrNull(width);
    final maximum = style.maxWidth.resolveOrNull(width);
    double? used = specified == null
        ? null
        : (style.borderBox ? specified - horizontal : specified);
    if (maximum != null) {
      final cap = style.borderBox ? maximum - horizontal : maximum;
      if (used == null ? contentWidth > cap : used > cap) used = cap;
    }
    if (style.display == Display.inlineBlock || style.floated) {
      final fit = _maxContent(box, contentWidth) ?? contentWidth;
      used = math.min(used ?? contentWidth, fit);
    }
    if (used != null && used < contentWidth) {
      final free = width - used - horizontal;
      final autoLeft = style.margin[3].isAuto;
      final autoRight = style.margin[1].isAuto;
      if (autoLeft && autoRight) {
        left = x + free / 2;
      } else if (autoLeft) {
        left = x + free - marginRight;
      } else if (style.display == Display.inlineBlock &&
          box.element.parent != null) {
        final parentAlign = section.styles[box.element.parent!]!.textAlign;
        left = switch (parentAlign) {
          Align.center => x + free / 2,
          Align.right || Align.end => x + free,
          _ => left,
        };
      }
      contentWidth = used;
    }
    margin(style.margin[0].resolve(width));
    final top = padding[0] + border[0];
    double? boxTop;
    if (top > 0) {
      resolveMargin();
      boxTop = y;
      y += top;
    }
    final firstSlice = slices.length;
    final contentLeft = left + border[3] + padding[3];
    if (box.marker != null && !style.listStyleInside) {
      _marker(box, contentLeft);
    }
    if (style.breakBefore == BreakRule.avoid) avoidNextBreak();
    for (final child in box.children) {
      switch (child) {
        case _BlockBox():
          block(child, contentLeft, contentWidth);
        case _InlineBox():
          inline(child, contentLeft, contentWidth);
      }
    }
    final bottom = padding[2] + border[2];
    if (bottom > 0 || boxTop != null) {
      resolveMargin();
      boxTop ??= y;
      y += bottom;
    }
    if (box.children.isEmpty && boxTop != null && y > boxTop) {
      // An empty box with a height, such as a rule, is one slice.
      add(boxTop, y, Appeal.perfect);
    }
    if (border.any((side) => side > 0) && boxTop != null) {
      final rect = ui.Rect.fromLTRB(
        left,
        boxTop,
        left + contentWidth + horizontal,
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
    if (style.avoidBreakInside) {
      for (var index = firstSlice + 1; index < slices.length; index++) {
        slices[index].appeal = math.min(
          slices[index].appeal,
          Appeal.violatingAvoid,
        );
      }
    }
    margin(style.margin[2].resolve(width));
    if (style.breakAfter == BreakRule.page && theme.pageBreaks) forceBreak();
    if (style.breakAfter == BreakRule.avoid) avoidNextBreak();
  }

  void _marker(_BlockBox box, double contentLeft) {
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle())
      ..pushStyle(textStyle(box.style))
      ..addText(box.marker!);
    final paragraph = builder.build()
      ..layout(const ui.ParagraphConstraints(width: double.infinity));
    // The marker sits left of the first line, on its baseline: the first
    // line's top is not known yet, so the offset is fixed on the next
    // slice.
    _pendingMarker = (paragraph, contentLeft - paragraph.maxIntrinsicWidth);
  }

  (ui.Paragraph, double)? _pendingMarker;

  double? _maxContent(_BlockBox box, double available) {
    var widest = 0.0;
    for (final child in box.children) {
      if (child is! _InlineBox) return null;
      final built = _build(child, 0, available);
      built.paragraph.layout(
        const ui.ParagraphConstraints(width: double.infinity),
      );
      widest = math.max(widest, built.paragraph.maxIntrinsicWidth);
    }
    return widest.ceilToDouble();
  }

  void _blockImage(_BlockBox box, double x, double width) {
    final style = box.style;
    final path = resolvePath(
      section.input.path,
      box.element.attributes['src'] ?? '',
    );
    final size = _imageSize(box.element, style, width);
    margin(style.margin[0].resolve(width));
    resolveMargin();
    final left = style.margin[3].isAuto && style.margin[1].isAuto
        ? x + (width - size.width) / 2
        : x + style.margin[3].resolve(width);
    final rect = ui.Rect.fromLTWH(left, y, size.width, size.height);
    if (path != null) decorations.add(ImageDecoration(rect, path));
    final slice = add(y, y + size.height, Appeal.perfect)
      ..start = DomPosition.element(box.element);
    _takeMarker(slice);
    y += size.height;
    margin(style.margin[2].resolve(width));
  }

  /// The used size of image [element], after its width, height and the
  /// reader's maximum width and height.
  ui.Size _imageSize(DomElement element, Style style, double width) {
    final path = resolvePath(
      section.input.path,
      element.attributes['src'] ?? '',
    );
    final intrinsic =
        (path == null ? null : section.imageSizes[path]) ?? ui.Size.zero;
    var w =
        style.width.resolveOrNull(width) ??
        double.tryParse(element.attributes['width'] ?? '');
    var h =
        style.height.resolveOrNull(width) ??
        double.tryParse(element.attributes['height'] ?? '');
    final ratio = intrinsic.height == 0
        ? 1.0
        : intrinsic.width / intrinsic.height;
    if (w == null && h == null) {
      w = intrinsic.width;
      h = intrinsic.height;
    } else if (w == null) {
      w = h! * ratio;
    } else {
      h ??= ratio == 0 ? 0 : w / ratio;
    }
    final maxWidth = style.maxWidth.resolveOrNull(width);
    final maxHeight = style.maxHeight.resolveOrNull(theme.height);
    // object-fit: contain keeps the ratio when a maximum applies.
    var scale = 1.0;
    if (maxWidth != null && w > maxWidth) scale = maxWidth / w;
    if (maxHeight != null && h * scale > maxHeight) scale = maxHeight / h;
    return ui.Size(w * scale, h * scale);
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

  ui.TextStyle textStyle(Style style) => _styles[style] ??= ui.TextStyle(
    color: theme.ink,
    fontFamily: _family(style.fontFamily),
    fontSize: style.fontSize,
    fontWeight: _weight(style.fontWeight),
    fontStyle: style.italic ? ui.FontStyle.italic : ui.FontStyle.normal,
    letterSpacing: style.letterSpacing == 0 ? null : style.letterSpacing,
    wordSpacing: style.wordSpacing == 0 ? null : style.wordSpacing,
    height: style.lineHeightPx == null
        ? null
        : style.lineHeightPx! / style.fontSize,
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
      ui.FontVariation('opsz', style.fontSize.clamp(8, 60).toDouble()),
      // The reader's @font-face rule names no weights, so Chromium draws
      // bold text as a thickened regular face with regular widths. Flutter
      // would pick the font's true bold, which is wider.
      if (theme.syntheticBold) const ui.FontVariation('wght', 400),
    ],
  );

  String _family(List<String> names) {
    for (final name in names) {
      switch (name.toLowerCase()) {
        case 'bookfinserif' || 'source serif 4' || 'serif':
          return theme.fontFamily;
        case 'monospace':
          return 'monospace';
      }
    }
    return theme.fontFamily;
  }

  static ui.FontWeight _weight(int weight) =>
      ui.FontWeight.values[((weight / 100).round() - 1).clamp(0, 8)];

  ui.ParagraphStyle _paragraphStyle(Style container) {
    final height = container.lineHeightPx;
    return ui.ParagraphStyle(
      textAlign: switch (container.textAlign) {
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
        fontFamily: _family(container.fontFamily),
        fontSize: container.fontSize,
        height: height == null ? null : height / container.fontSize,
        leadingDistribution: ui.TextLeadingDistribution.even,
        fontWeight: _weight(container.fontWeight),
      ),
      textHeightBehavior: const ui.TextHeightBehavior(
        leadingDistribution: ui.TextLeadingDistribution.even,
      ),
    );
  }

  /// Builds the paragraph of [box], from its code unit [from] on. Returns
  /// the paragraph, its map, and what each of its placeholders holds: null
  /// for the indent, an image's path, or a raised paragraph.
  _Built _build(_InlineBox box, double indent, double width, {int from = 0}) {
    final builder = ui.ParagraphBuilder(_paragraphStyle(box.container));
    final map = TextMap();
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
      map.addPlaceholder(null);
      inlines.add(null);
      unit = 1;
    }
    // A continued paragraph starts after the line that it continues, whose
    // last space ends that line.
    var trim = from > 0;
    // Collapsible white space: whether the last code unit written is a
    // space, or the start of the paragraph.
    var space = true;
    void items(List<_Item> list) {
      for (final item in list) {
        switch (item) {
          case _TextItem(:final node, :final style):
            final text = node.text;
            final collapse =
                style.whiteSpace == WhiteSpace.normal ||
                style.whiteSpace == WhiteSpace.nowrap;
            final keepBreaks =
                style.whiteSpace != WhiteSpace.normal &&
                style.whiteSpace != WhiteSpace.nowrap;
            final out = StringBuffer();
            final offsets = <int>[];
            for (var index = 0; index < text.length; index++) {
              var code = text.codeUnitAt(index);
              final isBreak = code == 0x0a;
              if (keepBreaks && isBreak) {
                out.writeCharCode(0x0a);
                offsets.add(index);
                space = true;
                continue;
              }
              if (code == 0x20 ||
                  code == 0x09 ||
                  code == 0x0a ||
                  code == 0x0d) {
                if (collapse || style.whiteSpace == WhiteSpace.preLine) {
                  if (space) continue;
                  code = 0x20;
                  space = true;
                } else {
                  code = code == 0x09 ? 0x20 : code;
                }
              } else {
                space = false;
              }
              out.writeCharCode(code);
              offsets.add(index);
            }
            if (offsets.isEmpty) continue;
            var written = out.toString();
            written = switch (style.transform) {
              Transform.upper => _sameLength(written, written.toUpperCase()),
              Transform.lower => _sameLength(written, written.toLowerCase()),
              _ => written,
            };
            final start = unit;
            unit += written.length;
            if (unit <= from) continue;
            var skip = math.max(0, from - start);
            if (trim) {
              while (skip < written.length &&
                  written.codeUnitAt(skip) == 0x20) {
                skip++;
              }
              if (skip == written.length) continue;
              trim = false;
            }
            builder
              ..pushStyle(textStyle(style))
              ..addText(written.substring(skip))
              ..pop();
            map.addText(node, offsets.sublist(skip));
          case _BreakItem():
            final start = unit;
            unit += 1;
            space = true;
            if (start < from) continue;
            trim = false;
            builder.addText('\n');
            map.addPlaceholder(item.element);
          case _ImageItem(:final element, :final style):
            final size = _imageSize(element, style, width);
            final start = unit;
            unit += 1;
            space = false;
            if (start < from) continue;
            trim = false;
            builder.addPlaceholder(
              size.width,
              size.height,
              ui.PlaceholderAlignment.baseline,
              baseline: ui.TextBaseline.alphabetic,
              baselineOffset: size.height,
            );
            map.addPlaceholder(element);
            inlines.add(
              resolvePath(
                    section.input.path,
                    element.attributes['src'] ?? '',
                  ) ??
                  '',
            );
          case _RaisedItem(:final element, :final style, items: final inner):
            final raised = _build(_InlineBox(inner, style, false), 0, width);
            raised.paragraph.layout(
              const ui.ParagraphConstraints(width: double.infinity),
            );
            final start = unit;
            unit += 1;
            space = false;
            if (start < from) continue;
            trim = false;
            final lines = raised.paragraph.computeLineMetrics();
            final baseline = lines.isEmpty ? 0.0 : lines.first.baseline;
            final parent = section.styles[element.parent!]!.fontSize;
            // Chromium raises superscripts by a third of the parent's size
            // and lowers subscripts by a fifth, plus one pixel.
            final shift = style.verticalAlign == VerticalAlign.superscript
                ? parent / 3 + 1
                : -(parent / 5 + 1);
            builder.addPlaceholder(
              raised.paragraph.maxIntrinsicWidth,
              raised.paragraph.height,
              ui.PlaceholderAlignment.baseline,
              baseline: ui.TextBaseline.alphabetic,
              baselineOffset: baseline + shift,
            );
            final first = inner.whereType<_TextItem>().firstOrNull;
            map.addPlaceholder(first?.node ?? element);
            inlines.add(raised.paragraph);
        }
      }
    }

    items(box.items);
    return _Built(builder.build(), map, inlines);
  }

  void inline(_InlineBox box, double x, double width) {
    final indent = box.first ? box.container.textIndent.resolve(width) : 0.0;
    resolveMargin();
    if (indent >= 0) {
      final built = _build(box, indent, width);
      built.paragraph.layout(ui.ParagraphConstraints(width: width));
      _place(built, x, box.container);
      return;
    }
    // A negative indent hangs the first line out to the left: lay it out
    // wider, then lay out the rest at the block's width.
    final first = _build(box, 0, width - indent);
    first.paragraph.layout(ui.ParagraphConstraints(width: width - indent));
    final count = first.paragraph.computeLineMetrics().length;
    if (count <= 1) {
      _place(first, x + indent, box.container);
      return;
    }
    final end = _lineStarts(first.paragraph, 2)[1];
    final rest = _build(box, 0, width, from: end);
    rest.paragraph.layout(ui.ParagraphConstraints(width: width));
    final total = 1 + rest.paragraph.computeLineMetrics().length;
    _place(first, x + indent, box.container, lines: 1, total: total);
    _place(rest, x, box.container, before: 1, total: total);
  }

  /// Adds the lines of [built], drawn at [x], to the strip: all of them,
  /// or the first [lines]. They are lines [before] on of a paragraph of
  /// [total] lines, for the orphans and widows rules.
  void _place(
    _Built built,
    double x,
    Style container, {
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
          all >= container.orphans + container.widows &&
          all - above < container.widows;
      final appeal = above == 0
          ? Appeal.perfect
          : above < container.orphans || widows
          ? Appeal.violatingOrphansWidows
          : Appeal.perfect;
      final slice = add(y + top, y + bottom, appeal, piece: piece, line: line)
        ..start = built.map.positionAt(starts[line]);
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
}

String _sameLength(String original, String changed) =>
    changed.length == original.length ? changed : original;

/// Lays out [section] for [theme] and cuts it into pages.
ChapterLayout layoutSection(PreparedSection section, PageTheme theme) {
  final flow = _Flow(theme, section);
  final body = _BoxBuilder(section.styles).block(section.dom.body);
  flow.block(body, 0, theme.width);
  return ChapterLayout(section, theme, flow.slices, flow.decorations);
}

List<PageSlice> _paginate(List<Slice> slices, double height) {
  final pages = <PageSlice>[];
  var start = 0;
  var top = 0.0;
  const epsilon = 0.01;
  while (start < slices.length) {
    final limit = top + height + epsilon;
    var end = start;
    while (end < slices.length &&
        slices[end].bottom <= limit &&
        !(end > start && slices[end].forcedBreak != null)) {
      end++;
    }
    if (end == slices.length) {
      pages.add(PageSlice(top, math.max(slices.last.bottom, top), start, end));
      break;
    }
    int next;
    double nextTop;
    if (end > start && slices[end].forcedBreak != null) {
      next = end;
      nextTop = slices[end].forcedBreak!;
    } else if (end == start) {
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
