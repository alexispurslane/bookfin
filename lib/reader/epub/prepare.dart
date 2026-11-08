// Prepares spine sections for layout: parses each section, cascades its
// style sheets and the reader's rules, builds its boxes, collapses white
// space and turns the result into a flat list of flow items.
//
// Nothing here uses dart:ui, so a worker isolate can run it
// (`Isolate.run(() => prepareSections(sources, settings))`). Layout on the
// UI isolate (layout.dart) turns the flow items into Flutter paragraphs and
// pages. Every length that does not depend on a paragraph's own width is
// already in pixels here.
import 'dart:math' as math;
import 'dart:typed_data';

import 'css.dart';
import 'dom.dart';

// Section sources name publication paths, so their callers resolve
// references with the same rule as the style sheets.
export 'css.dart' show resolvePath;

/// The reader's font family. Its file is assets/fonts/SourceSerif4.ttf.
const readerFontFamily = 'Source Serif 4';

/// The reader's line height, as a factor of the text size.
const readerLineHeight = 1.65;

/// The page size and the reader settings that a layout depends on. Two
/// equal values give equal layouts, so a value is a cache key.
class PageSettings {
  const PageSettings({
    required this.width,
    required this.height,
    required this.fontSize,
    required this.night,
  });

  /// The page size in logical pixels.
  final double width;
  final double height;

  /// The text size in pixels, after the system text scale.
  final double fontSize;

  /// Whether the page uses the night colors rather than cream.
  final bool night;

  @override
  bool operator ==(Object other) =>
      other is PageSettings &&
      other.width == width &&
      other.height == height &&
      other.fontSize == fontSize &&
      other.night == night;

  @override
  int get hashCode => Object.hash(width, height, fontSize, night);

  @override
  String toString() =>
      'PageSettings(${width}x$height, ${fontSize}px'
      '${night ? ', night' : ''})';
}

/// One spine section and what preparing it reads from the publication.
class SectionSource {
  const SectionSource({
    required this.index,
    required this.path,
    required this.xhtml,
    required this.fontPrefix,
    this.styleSheets = const {},
    this.imageSizes = const {},
  });

  /// The section's spine index.
  final int index;

  /// The section's path in the publication, such as `epub/text/one.xhtml`.
  final String path;
  final String xhtml;

  /// The CSS text of each style sheet that the section can reach through
  /// links and `@import`, by its publication path.
  final Map<String, String> styleSheets;

  /// The start of the family name of each of the book's embedded faces:
  /// `bookfin-` and the first 12 hex digits of the publication identity.
  /// Flutter registers fonts for the whole process, so the prefix keeps one
  /// book's faces apart from another book's faces of the same family.
  final String fontPrefix;

  /// The width and height in pixels of each image, by its publication path.
  /// An image without an entry has no intrinsic size.
  final Map<String, (int, int)> imageSizes;
}

/// One section parsed, styled for one [PageSettings] value, and turned into
/// flow items. It holds no dart:ui object, and nothing changes it.
class PreparedSection {
  PreparedSection._(
    this.index,
    this.settings,
    this.dom,
    this.flow,
    this.styles,
    this.fonts,
  );

  /// The section's spine index.
  final int index;
  final PageSettings settings;
  final DomSection dom;

  /// The steps of block layout, in document order.
  final List<FlowItem> flow;

  /// The text styles that the flow items name by index.
  final List<RunStyle> styles;

  /// The embedded faces that [styles] draw with. Each must be registered
  /// (`BookFonts.load`) before the section lays out.
  final List<FontFaceRule> fonts;
}

/// Prepares each of [sources] for a page of [settings].
List<PreparedSection> prepareSections(
  List<SectionSource> sources,
  PageSettings settings,
) => [for (final source in sources) _prepare(source, settings)];

PreparedSection _prepare(SectionSource source, PageSettings settings) {
  final dom = DomSection.parse(source.xhtml);
  final (:styles, faces: declared) = styleSection(source, dom, settings);
  final faces = _Faces(declared, source.fontPrefix);
  final flattener = _Flattener(source, settings, styles, faces);
  flattener.block(_BoxBuilder(styles).block(dom.body), settings.width);
  return PreparedSection._(
    source.index,
    settings,
    dom,
    flattener.flow,
    flattener.runStyles,
    faces.used.toList(),
  );
}

// Flow items.

/// One step of block layout.
sealed class FlowItem {
  const FlowItem();
}

/// The start of a block box. The items up to the matching [BlockEnd] are
/// its content. Its lengths are in pixels. Layout places the box in the
/// content box of the block that holds it.
final class BlockStart extends FlowItem {
  const BlockStart({
    required this.placement,
    required this.marginTop,
    required this.marginBottom,
    required this.padding,
    required this.border,
    this.marker,
    this.shrinkToFit = false,
    this.avoidBreakBefore = false,
    this.avoidBreakAfter = false,
    this.avoidBreakInside = false,
  });

  /// Where the box sits across its containing block.
  final BoxPlacement placement;
  final double marginTop;
  final double marginBottom;

  /// The padding and the used border widths, from top to left.
  final List<double> padding;
  final List<double> border;

  /// The list marker drawn left of the box's first line, and the index of
  /// its [RunStyle], or null.
  final ({String text, int style})? marker;

  /// Whether the box is as wide as its widest line (an inline-block or a
  /// float) or as its table's widest content (a table without a set width).
  /// Its content is then paragraphs only, or one [TableItem], which layout
  /// measures.
  final bool shrinkToFit;

  /// Whether a page break right before the box's first line, right after
  /// the box, or inside it is to be avoided.
  final bool avoidBreakBefore;
  final bool avoidBreakAfter;
  final bool avoidBreakInside;
}

/// The end of the block box of the last open [BlockStart].
final class BlockEnd extends FlowItem {
  const BlockEnd();
}

/// A paragraph: the inline content between two blocks.
final class ParagraphItem extends FlowItem {
  const ParagraphItem({
    required this.text,
    required this.indent,
    required this.orphans,
    required this.widows,
  });
  final StyledText text;

  /// The indent of the first line. A percentage resolves against the
  /// paragraph's width, which layout knows. A negative indent hangs the
  /// first line out to the left.
  final Length indent;

  /// The fewest lines that a page break leaves before and after it.
  final int orphans;
  final int widows;
}

/// An image in a block of its own. Layout sizes it and places it in the
/// content box of the block that holds it.
final class ImageItem extends FlowItem {
  const ImageItem({
    required this.node,
    required this.path,
    required this.sizing,
    required this.marginLeft,
    required this.centered,
    required this.marginTop,
    required this.marginBottom,
  });

  /// The image element's [DomNode.order].
  final int node;

  /// The image's publication path, or null when it leaves the publication.
  final String? path;

  /// How the image's size follows from the width of the block that holds
  /// it.
  final ImageSizing sizing;

  /// The image's left margin in pixels, unless both side margins are auto
  /// and so [centered].
  final double marginLeft;
  final bool centered;
  final double marginTop;
  final double marginBottom;
}

/// A table with rows, laid out as a grid of cells (table.dart). Each row is
/// one strip slice, so a page breaks only between rows. The [BlockStart]
/// before it and the [BlockEnd] after it are the table's own box.
final class TableItem extends FlowItem {
  const TableItem(this.rows, this.width);

  /// The rows of cells, in document order. A cell spans the columns of its
  /// colspan, and every row starts at the first column.
  final List<List<TableCell>> rows;

  /// The width in pixels that the lengths in the cells resolve against: the
  /// widest that the table's content can be.
  final double width;
}

/// One cell of a [TableItem]: a box that the table draws as tall as its
/// row, with its content inside.
final class TableCell {
  const TableCell(
    this.flow, {
    required this.colspan,
    required this.padding,
    required this.border,
    required this.align,
  });

  /// The cell's content. A table inside the cell is plain blocks here, so
  /// [flow] holds no [TableItem].
  final List<FlowItem> flow;

  /// The number of columns that the cell spans, at least 1.
  final int colspan;

  /// The cell's padding and used border widths in pixels, from top to
  /// left.
  final List<double> padding;
  final List<double> border;

  /// Where the cell's content sits in a row taller than it: the share of
  /// the free height above it, 0 at the top, 0.5 in the middle and 1 at
  /// the bottom.
  final double align;
}

/// Inline content that layout builds into one Flutter paragraph.
final class StyledText {
  const StyledText(this.style, this.align, this.runs);

  /// The index of the [RunStyle] of the block that holds the text. Its font
  /// and line height form the paragraph's strut.
  final int style;
  final Align align;
  final List<InlineRun> runs;
}

/// A piece of inline content.
sealed class InlineRun {
  const InlineRun();
}

/// Text in one style, after white space collapsing and text transform.
final class TextRun extends InlineRun {
  const TextRun(this.text, this.style, this.node, this.offsets);
  final String text;

  /// The index of the run's [RunStyle].
  final int style;

  /// The [DomNode.order] of the text node that the text comes from.
  final int node;

  /// For each code unit of [text], its offset in the text node.
  final Int32List offsets;
}

/// A line break from a `br` element.
final class BreakRun extends InlineRun {
  const BreakRun(this.node);

  /// The `br` element's [DomNode.order].
  final int node;
}

/// An image in a line.
final class ImageRun extends InlineRun {
  const ImageRun(this.node, this.path, this.sizing);

  /// The image element's [DomNode.order].
  final int node;

  /// The image's publication path, or empty when it leaves the publication.
  final String path;

  /// How the image's size follows from the paragraph's width.
  final ImageSizing sizing;
}

/// Raised or lowered text, such as a superscript, drawn as a small
/// paragraph of its own in the line.
final class RaisedRun extends InlineRun {
  const RaisedRun(this.node, this.text, this.shift);

  /// The [DomNode.order] of the raised text's first text node, or of its
  /// element when it has no text.
  final int node;
  final StyledText text;

  /// How far the raised text's baseline sits above the line's baseline, in
  /// pixels. Negative is below.
  final double shift;
}

/// A text style in plain values.
class RunStyle {
  const RunStyle({
    required this.family,
    required this.size,
    required this.weight,
    required this.italic,
    required this.letterSpacing,
    required this.wordSpacing,
    required this.lineHeight,
    required this.underline,
    required this.lineThrough,
    required this.smallCaps,
    required this.oldstyleFigures,
  });

  /// The font family to draw with.
  final String family;
  final double size;

  /// The CSS font weight, from 100 to 900.
  final int weight;
  final bool italic;
  final double letterSpacing;
  final double wordSpacing;

  /// The line height in pixels, or null for `normal`.
  final double? lineHeight;
  final bool underline;
  final bool lineThrough;
  final bool smallCaps;
  final bool oldstyleFigures;

  @override
  bool operator ==(Object other) =>
      other is RunStyle &&
      other.family == family &&
      other.size == size &&
      other.weight == weight &&
      other.italic == italic &&
      other.letterSpacing == letterSpacing &&
      other.wordSpacing == wordSpacing &&
      other.lineHeight == lineHeight &&
      other.underline == underline &&
      other.lineThrough == lineThrough &&
      other.smallCaps == smallCaps &&
      other.oldstyleFigures == oldstyleFigures;

  @override
  int get hashCode => Object.hash(
    family,
    size,
    weight,
    italic,
    letterSpacing,
    wordSpacing,
    lineHeight,
    underline,
    lineThrough,
    smallCaps,
    oldstyleFigures,
  );
}

/// Where a block box sits across its containing block.
class BoxPlacement {
  const BoxPlacement({
    required this.marginLeft,
    required this.marginRight,
    required this.horizontal,
    required this.used,
    required this.autoLeft,
    required this.autoRight,
    required this.parentAlign,
  });
  final double marginLeft;
  final double marginRight;

  /// The box's left and right padding and border.
  final double horizontal;

  /// The content width that the box's width and max-width ask for, or null
  /// when they ask for none.
  final double? used;

  /// Whether the left and the right margin are auto.
  final bool autoLeft;
  final bool autoRight;

  /// The text alignment of an inline-block's parent, which places a
  /// narrow inline-block. Null for any other box.
  final Align? parentAlign;

  /// The content width when the box fills a containing block [width]
  /// pixels wide.
  double available(double width) =>
      width - marginLeft - marginRight - horizontal;

  /// The left edge of the border box and the content width, in a
  /// containing block that starts at [x] and is [width] pixels wide. [fit]
  /// is the widest content width of a shrink-to-fit box, or null.
  (double, double) place(double x, double width, [double? fit]) {
    var contentWidth = available(width);
    var left = x + marginLeft;
    var used = this.used;
    if (fit != null) used = math.min(used ?? contentWidth, fit);
    if (used != null && used < contentWidth) {
      final free = width - used - horizontal;
      if (autoLeft && autoRight) {
        left = x + free / 2;
      } else if (autoLeft) {
        left = x + free - marginRight;
      } else if (parentAlign != null) {
        left = switch (parentAlign!) {
          Align.center => x + free / 2,
          Align.right || Align.end => x + free,
          _ => left,
        };
      }
      contentWidth = used;
    }
    return (left, contentWidth);
  }
}

/// How an image's used size follows from the width of the block that holds
/// it: its width and height, and the reader's maximum width and height.
class ImageSizing {
  const ImageSizing({
    required this.intrinsicWidth,
    required this.intrinsicHeight,
    required this.width,
    required this.height,
    required this.attributeWidth,
    required this.attributeHeight,
    required this.maxWidth,
    required this.maxHeight,
  });
  final double intrinsicWidth;
  final double intrinsicHeight;

  /// The CSS width and height. A percentage resolves against the block.
  final Length width;
  final Length height;

  /// The element's width and height attributes, in pixels.
  final double? attributeWidth;
  final double? attributeHeight;
  final Length maxWidth;

  /// The maximum height in pixels, already resolved against the page.
  final double? maxHeight;

  /// The used width and height inside a block [block] pixels wide.
  (double, double) sizeIn(double block) {
    final ratio = intrinsicHeight == 0 ? 1.0 : intrinsicWidth / intrinsicHeight;
    final specifiedWidth = width.resolveOrNull(block) ?? attributeWidth;
    final specifiedHeight = height.resolveOrNull(block) ?? attributeHeight;
    final double w;
    final double h;
    if (specifiedWidth == null && specifiedHeight == null) {
      w = intrinsicWidth;
      h = intrinsicHeight;
    } else if (specifiedWidth == null) {
      w = specifiedHeight! * ratio;
      h = specifiedHeight;
    } else {
      w = specifiedWidth;
      h = specifiedHeight ?? (ratio == 0 ? 0 : specifiedWidth / ratio);
    }
    final maximum = maxWidth.resolveOrNull(block);
    // object-fit: contain keeps the ratio when a maximum applies.
    var scale = 1.0;
    if (maximum != null && w > maximum) scale = maximum / w;
    if (maxHeight != null && h * scale > maxHeight!) scale = maxHeight! / h;
    return (w * scale, h * scale);
  }
}

// Styles.

/// The computed style of each element of [dom], the parsed [source], under
/// its style sheets and the reader's rules for [settings], and the
/// `@font-face` rules of those sheets.
({Map<DomElement, Style> styles, List<FontFaceRule> faces}) styleSection(
  SectionSource source,
  DomSection dom,
  PageSettings settings,
) {
  final media = MediaContext(
    width: settings.width,
    height: settings.height,
    night: settings.night,
  );
  final sheets = sectionSheets(source, dom, media);
  final rules = <StyleRule>[
    ..._userAgentSheet.rules,
    for (final sheet in sheets) ...sheet.rules,
    ...StyleSheet.parse(
      _readerCss(settings),
      firstOrder: 1 << 30,
      media: media,
    ).rules,
  ];
  final cascade = Cascade(
    rules,
    overrides: {dom.body: _bodyOverrides(settings)},
  );
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
  return (
    styles: styles,
    faces: [for (final sheet in sheets) ...sheet.fontFaces],
  );
}

/// The book's style sheets that section [dom] uses, linked or in style
/// elements, in document order, each with the sheets that it imports.
List<StyleSheet> sectionSheets(
  SectionSource source,
  DomSection dom,
  MediaContext media,
) {
  final sheets = <StyleSheet>[];
  var order = 1000;
  for (final element in elementsOf(dom.root)) {
    String? css;
    String? path;
    if (element.name == 'link' &&
        (element.attributes['rel'] ?? '').toLowerCase().contains(
          'stylesheet',
        )) {
      path = resolvePath(source.path, element.attributes['href'] ?? '');
      css = path == null ? null : source.styleSheets[path];
    } else if (element.name == 'style') {
      path = source.path;
      css = element.texts.map((text) => text.text).join();
    }
    if (css == null) continue;
    final sheet = StyleSheet.parse(
      css,
      path: path,
      read: (path) => source.styleSheets[path],
      firstOrder: order,
      media: media,
    );
    sheets.add(sheet);
    order += sheet.rules.length + sheet.pseudoRules.length + 1;
  }
  return sheets;
}

/// [root] and every element inside it, in document order.
Iterable<DomElement> elementsOf(DomElement root) sync* {
  yield root;
  for (final child in root.elements) {
    yield* elementsOf(child);
  }
}

/// The horizontal padding of the page's body: half the column gap that
/// epub.js uses, a twelfth of the width rounded down to an even number.
double _sideMargin(double width) {
  final section = (width / 12).floor();
  return (section.isEven ? section : section - 1) / 2;
}

/// The rules that the WebView reader adds to each section: epub.js's theme
/// and image rules and the reader's own style.
String _readerCss(PageSettings settings) {
  final side = _sideMargin(settings.width);
  final imageWidth = settings.width - 2 * side;
  final imageHeight = settings.height * .95;
  // epub.js adds its image rules first and the reader's style after them,
  // so the reader's max-width wins.
  return 'html{font-family:BookfinSerif,"Source Serif 4",serif}'
      'img{max-width:${imageWidth}px!important;'
      'max-height:${imageHeight}px!important;break-inside:avoid;'
      'box-sizing:border-box}'
      'body{overflow-wrap:break-word;line-height:$readerLineHeight!important;'
      'padding:0 18px!important}'
      'img{max-width:100%!important;height:auto}';
}

/// The declarations that epub.js sets on the body element itself.
List<Declaration> _bodyOverrides(PageSettings settings) {
  final side = _sideMargin(settings.width);
  return [
    Declaration('font-size', '${settings.fontSize}px', false),
    const Declaration('margin', '0', true),
    const Declaration('padding-top', '20px', false),
    const Declaration('padding-bottom', '20px', false),
    Declaration('padding-left', '${side}px', true),
    Declaration('padding-right', '${side}px', true),
    const Declaration('box-sizing', 'border-box', false),
  ];
}

/// Chromium's default style for the elements that books use.
final _userAgentSheet = StyleSheet.parse('''
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
table { text-indent: 0; box-sizing: border-box }
td, th { padding: 1px }
thead, tbody, tfoot, tr { vertical-align: middle }
td, th { vertical-align: inherit }
th { font-weight: bold; text-align: center }
caption { text-align: center }
''');

// Box building.

sealed class _Box {}

class _BlockBox extends _Box {
  _BlockBox(this.element, this.style, this.children, {this.marker});
  final DomElement element;
  final Style style;
  final List<_Box> children;
  final String? marker;
}

/// A table with rows: its cells by row, each with its colspan.
class _TableBox extends _Box {
  _TableBox(this.element, this.style, this.rows);
  final DomElement element;
  final Style style;
  final List<List<(_BlockBox, int)>> rows;
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

  /// The number of table cells that the box being built is inside. A table
  /// inside a cell lays out as blocks.
  int _cells = 0;

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
      if (!_visible(child)) return;
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
      if (child.name == 'table' && _cells == 0) {
        if (_table(child) case (final captions, final table)) {
          flush();
          children
            ..addAll(captions)
            ..add(table);
          return;
        }
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
      if (childStyle.verticalAlign == VerticalAlign.superscript ||
          childStyle.verticalAlign == VerticalAlign.subscript) {
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

  /// Whether [element] shows: it is not display none, and not a box moved
  /// off the page.
  bool _visible(DomElement element) {
    final style = styles[element]!;
    return style.display != Display.none && !style.movedOffPage;
  }

  /// The captions and the box of [table], or null when it has no row with
  /// a cell. A row is a `tr` in the table or in one of its row groups.
  (List<_BlockBox>, _TableBox)? _table(DomElement table) {
    final captions = <_BlockBox>[];
    final rows = <List<(_BlockBox, int)>>[];
    void row(DomElement tr) {
      _cells++;
      final cells = [
        for (final cell in tr.elements)
          if ((cell.name == 'td' || cell.name == 'th') && _visible(cell))
            (
              block(cell),
              (int.tryParse(cell.attributes['colspan'] ?? '') ?? 1).clamp(
                1,
                1000,
              ),
            ),
      ];
      _cells--;
      if (cells.isNotEmpty) rows.add(cells);
    }

    for (final child in table.elements) {
      if (!_visible(child)) continue;
      switch (child.name) {
        case 'caption':
          captions.add(block(child));
        case 'tr':
          row(child);
        case 'thead' || 'tbody' || 'tfoot':
          for (final tr in child.elements) {
            if (tr.name == 'tr' && _visible(tr)) row(tr);
          }
      }
    }
    if (rows.isEmpty) return null;
    return (captions, _TableBox(table, styles[table]!, rows));
  }

  void _inlineItems(DomElement element, Style style, List<_Item> out) {
    for (final child in element.children) {
      if (child is DomText) {
        out.add(_TextItem(child, style));
      } else if (child is DomElement) {
        final childStyle = styles[child]!;
        if (!_visible(child)) continue;
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

// Flow items from boxes.

/// Turns a tree of boxes into flow items, with every length that the width
/// of its containing block decides in pixels.
class _Flattener {
  _Flattener(this.source, this.settings, this.styles, this.faces);
  final SectionSource source;
  final PageSettings settings;
  final Map<DomElement, Style> styles;
  final _Faces faces;

  /// The flow items being written: the section's, or a table cell's.
  var flow = <FlowItem>[];
  final runStyles = <RunStyle>[];
  final _byValue = <RunStyle, int>{};
  final _byStyle = <Style, int>{};

  /// Adds [box], whose containing block is [width] pixels wide.
  void block(_BlockBox box, double width) {
    final style = box.style;
    if (box.element.name == 'img') {
      _blockImage(box, width);
      return;
    }
    final inlineBlock = style.display == Display.inlineBlock;
    final placement = _start(
      box.element,
      style,
      width,
      marker: box.marker,
      // A shrink-to-fit box with a block inside fills its containing
      // block, as when it is not shrink-to-fit.
      shrinkToFit:
          (inlineBlock || style.floated) &&
          box.children.every((child) => child is _InlineBox),
    );
    final (_, contentWidth) = placement.place(0, width);
    _content(box, contentWidth);
    flow.add(const BlockEnd());
  }

  /// Adds the content of [box], whose content box is [width] pixels wide.
  void _content(_BlockBox box, double width) {
    for (final child in box.children) {
      switch (child) {
        case _BlockBox():
          block(child, width);
        case _TableBox():
          _table(child, width);
        case _InlineBox():
          flow.add(
            ParagraphItem(
              text: StyledText(
                _styleOf(child.container),
                child.container.textAlign,
                _runs(child.items),
              ),
              indent: child.first
                  ? child.container.textIndent
                  : const Length.px(0),
              orphans: child.container.orphans,
              widows: child.container.widows,
            ),
          );
      }
    }
  }

  /// Adds the [BlockStart] of [element], whose containing block is [width]
  /// pixels wide, and returns its placement.
  BoxPlacement _start(
    DomElement element,
    Style style,
    double width, {
    required bool shrinkToFit,
    String? marker,
  }) {
    final marginLeft = style.margin[3].resolve(width);
    final marginRight = style.margin[1].resolve(width);
    final (:padding, :border) = _box(style, width);
    final horizontal = padding[1] + padding[3] + border[1] + border[3];
    final specified = style.width.resolveOrNull(width);
    final maximum = style.maxWidth.resolveOrNull(width);
    double? used = specified == null
        ? null
        : (style.borderBox ? specified - horizontal : specified);
    if (maximum != null) {
      final cap = style.borderBox ? maximum - horizontal : maximum;
      final available = width - marginLeft - marginRight - horizontal;
      if (used == null ? available > cap : used > cap) used = cap;
    }
    final inlineBlock = style.display == Display.inlineBlock;
    final placement = BoxPlacement(
      marginLeft: marginLeft,
      marginRight: marginRight,
      horizontal: horizontal,
      used: used,
      autoLeft: style.margin[3].isAuto,
      autoRight: style.margin[1].isAuto,
      parentAlign: inlineBlock && element.parent != null
          ? styles[element.parent!]!.textAlign
          : null,
    );
    flow.add(
      BlockStart(
        placement: placement,
        marginTop: style.margin[0].resolve(width),
        marginBottom: style.margin[2].resolve(width),
        padding: padding,
        border: border,
        marker: marker != null && !style.listStyleInside
            ? (text: marker, style: _styleOf(style))
            : null,
        shrinkToFit: shrinkToFit,
        avoidBreakBefore: style.breakBefore == BreakRule.avoid,
        avoidBreakAfter: style.breakAfter == BreakRule.avoid,
        avoidBreakInside: style.avoidBreakInside,
      ),
    );
    return placement;
  }

  /// The padding and the used border widths of [style] in pixels, from top
  /// to left, in a containing block [width] pixels wide.
  ({List<double> padding, List<double> border}) _box(
    Style style,
    double width,
  ) => (
    padding: [for (final side in style.padding) side.resolve(width)],
    border: [for (var side = 0; side < 4; side++) style.usedBorder(side)],
  );

  /// Adds the box of [table], whose containing block is [width] pixels
  /// wide, with its [TableItem] inside. Without a set width, the box is as
  /// wide as the table's content.
  void _table(_TableBox table, double width) {
    final placement = _start(
      table.element,
      table.style,
      width,
      shrinkToFit: table.style.width.isAuto,
    );
    final (_, contentWidth) = placement.place(0, width);
    flow
      ..add(
        TableItem([
          for (final row in table.rows)
            [
              for (final (cell, colspan) in row)
                _cell(cell, colspan, contentWidth),
            ],
        ], contentWidth),
      )
      ..add(const BlockEnd());
  }

  /// [cell], which spans [colspan] columns of a table whose content is at
  /// most [width] pixels wide. A cell has no margins, and its column
  /// decides its width.
  TableCell _cell(_BlockBox cell, int colspan, double width) {
    final (:padding, :border) = _box(cell.style, width);
    final outer = flow;
    flow = [];
    _content(cell, width - padding[1] - padding[3] - border[1] - border[3]);
    final items = flow;
    flow = outer;
    return TableCell(
      items,
      colspan: colspan,
      padding: padding,
      border: border,
      // Chromium aligns the baselines of baseline cells, which is close to
      // their tops.
      align: switch (cell.style.verticalAlign) {
        VerticalAlign.top || VerticalAlign.baseline => 0,
        VerticalAlign.bottom => 1,
        _ => 0.5,
      },
    );
  }

  void _blockImage(_BlockBox box, double width) {
    final style = box.style;
    flow.add(
      ImageItem(
        node: box.element.order,
        path: resolvePath(source.path, box.element.attributes['src'] ?? ''),
        sizing: _sizing(box.element, style),
        marginLeft: style.margin[3].resolve(width),
        centered: style.margin[3].isAuto && style.margin[1].isAuto,
        marginTop: style.margin[0].resolve(width),
        marginBottom: style.margin[2].resolve(width),
      ),
    );
  }

  ImageSizing _sizing(DomElement element, Style style) {
    final path = resolvePath(source.path, element.attributes['src'] ?? '');
    final intrinsic = path == null ? null : source.imageSizes[path];
    return ImageSizing(
      intrinsicWidth: (intrinsic?.$1 ?? 0).toDouble(),
      intrinsicHeight: (intrinsic?.$2 ?? 0).toDouble(),
      width: style.width,
      height: style.height,
      attributeWidth: double.tryParse(element.attributes['width'] ?? ''),
      attributeHeight: double.tryParse(element.attributes['height'] ?? ''),
      maxWidth: style.maxWidth,
      maxHeight: style.maxHeight.resolveOrNull(settings.height),
    );
  }

  /// The runs of [items], with white space collapsed as CSS collapses it
  /// in one block.
  List<InlineRun> _runs(List<_Item> items) {
    final runs = <InlineRun>[];
    // Collapsible white space: whether the last code unit written is a
    // space, or the start of the paragraph.
    var space = true;
    for (final item in items) {
      switch (item) {
        case _TextItem(:final node, :final style):
          final text = node.text;
          final collapse =
              style.whiteSpace == WhiteSpace.normal ||
              style.whiteSpace == WhiteSpace.nowrap;
          final keepBreaks = !collapse;
          final out = StringBuffer();
          final offsets = <int>[];
          for (var index = 0; index < text.length; index++) {
            var code = text.codeUnitAt(index);
            if (keepBreaks && code == 0x0a) {
              out.writeCharCode(0x0a);
              offsets.add(index);
              space = true;
              continue;
            }
            if (code == 0x20 || code == 0x09 || code == 0x0a || code == 0x0d) {
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
          final written = out.toString();
          runs.add(
            TextRun(
              switch (style.transform) {
                Transform.upper => _sameLength(written, written.toUpperCase()),
                Transform.lower => _sameLength(written, written.toLowerCase()),
                _ => written,
              },
              _styleOf(style),
              node.order,
              Int32List.fromList(offsets),
            ),
          );
        case _BreakItem(:final element):
          space = true;
          runs.add(BreakRun(element.order));
        case _ImageItem(:final element, :final style):
          space = false;
          runs.add(
            ImageRun(
              element.order,
              resolvePath(source.path, element.attributes['src'] ?? '') ?? '',
              _sizing(element, style),
            ),
          );
        case _RaisedItem(:final element, :final style, items: final inner):
          space = false;
          final parent = styles[element.parent!]!.fontSize;
          final first = inner.whereType<_TextItem>().firstOrNull;
          runs.add(
            RaisedRun(
              first?.node.order ?? element.order,
              StyledText(_styleOf(style), style.textAlign, _runs(inner)),
              // Chromium raises superscripts by a third of the parent's
              // size and lowers subscripts by a fifth, plus one pixel.
              style.verticalAlign == VerticalAlign.superscript
                  ? parent / 3 + 1
                  : -(parent / 5 + 1),
            ),
          );
      }
    }
    return runs;
  }

  /// The index of the run style of [style].
  int _styleOf(Style style) => _byStyle[style] ??= () {
    final run = _runStyle(style, faces.familyOf(style));
    return _byValue.putIfAbsent(run, () {
      runStyles.add(run);
      return runStyles.length - 1;
    });
  }();
}

RunStyle _runStyle(Style style, String family) => RunStyle(
  family: family,
  size: style.fontSize,
  weight: style.fontWeight,
  italic: style.italic,
  letterSpacing: style.letterSpacing,
  wordSpacing: style.wordSpacing,
  lineHeight: style.lineHeightPx,
  underline: style.underline,
  lineThrough: style.lineThrough,
  smallCaps: style.smallCaps,
  oldstyleFigures: style.oldstyleFigures,
);

/// A section's embedded faces by family, and the faces that its runs use.
class _Faces {
  _Faces(Iterable<FontFaceRule> faces, this.prefix) {
    for (final face in faces) {
      (_byFamily[face.family] ??= []).add(face);
    }
  }

  final String prefix;
  final _byFamily = <String, List<FontFaceRule>>{};

  /// The faces that the runs use, in the order of first use.
  final used = <FontFaceRule>{};

  /// The family to draw [style] with: the first of its families that is
  /// embedded or that the renderer has. That is an embedded family, the
  /// reader's font or monospace, and else the reader's font. The face of an
  /// embedded family that suits [style] joins [used].
  String familyOf(Style style) {
    for (final name in style.fontFamily) {
      final family = name.toLowerCase();
      if (_byFamily[family] case final faces?) {
        final face = _nearest(faces, style);
        used.add(face);
        return face.familyIn(prefix);
      }
      switch (family) {
        case 'bookfinserif' || 'source serif 4' || 'serif':
          return readerFontFamily;
        case 'monospace':
          return 'monospace';
      }
    }
    return readerFontFamily;
  }

  /// The face of [faces] that CSS font matching picks for [style], in a
  /// simple form: the same slant if one has it, then the nearest weight.
  static FontFaceRule _nearest(List<FontFaceRule> faces, Style style) {
    final slant = faces.where((face) => face.italic == style.italic).toList();
    return (slant.isEmpty ? faces : slant).reduce(
      (best, face) =>
          (face.weight - style.fontWeight).abs() <
              (best.weight - style.fontWeight).abs()
          ? face
          : best,
    );
  }
}

String _sameLength(String original, String changed) =>
    changed.length == original.length ? changed : original;
