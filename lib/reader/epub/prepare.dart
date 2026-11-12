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
import 'hyphenate.dart';
import 'table.dart';

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
    this.sizesMainText = false,
  });

  /// The page size in logical pixels.
  final double width;
  final double height;

  /// The text size in pixels, after the system text scale. See
  /// [sizesMainText] for the text that it sizes.
  final double fontSize;

  /// Whether the page uses the night colors rather than cream.
  final bool night;

  /// Whether [fontSize] is the size of the book's main text. Then the book
  /// keeps its own proportions: each of its type sizes, and each length
  /// that follows one, scales by [fontSize] over the book's main text size
  /// (see [SectionSource.mainTextSize]). Otherwise [fontSize] is the size of
  /// the body element, as epub.js sets it, and a type size that the book
  /// fixes stays as the book fixes it.
  final bool sizesMainText;

  @override
  bool operator ==(Object other) =>
      other is PageSettings &&
      other.width == width &&
      other.height == height &&
      other.fontSize == fontSize &&
      other.night == night &&
      other.sizesMainText == sizesMainText;

  @override
  int get hashCode =>
      Object.hash(width, height, fontSize, night, sizesMainText);

  @override
  String toString() =>
      'PageSettings(${width}x$height, ${fontSize}px'
      '${sizesMainText ? ' main text' : ''}${night ? ', night' : ''})';

  /// These settings as a JSON object that [PageSettings.fromJson] reads.
  Map<String, Object> toJson() => {
    'width': width,
    'height': height,
    'fontSize': fontSize,
    'night': night,
    'sizesMainText': sizesMainText,
  };

  /// The settings of [json], an object that [toJson] wrote. Throws a
  /// [FormatException] when it is not one, or names no page area.
  factory PageSettings.fromJson(Object? json) {
    if (json is! Map ||
        json['width'] is! num ||
        json['height'] is! num ||
        json['fontSize'] is! num ||
        json['night'] is! bool ||
        json['sizesMainText'] is! bool) {
      throw const FormatException('These are not page settings.');
    }
    bool positive(num value) => value > 0 && value.isFinite;
    final (width, height, fontSize) = (
      json['width'] as num,
      json['height'] as num,
      json['fontSize'] as num,
    );
    if (!positive(width) || !positive(height) || !positive(fontSize)) {
      throw const FormatException('The page settings name no page area.');
    }
    return PageSettings(
      width: width.toDouble(),
      height: height.toDouble(),
      fontSize: fontSize.toDouble(),
      night: json['night'] as bool,
      sizesMainText: json['sizesMainText'] as bool,
    );
  }
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
    this.language,
    this.mainTextSize = defaultMainTextSize,
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

  /// The package's `dc:language`: the language of text whose elements name
  /// none.
  final String? language;

  /// The book's main text size in pixels, as [measureMainTextSize] gives
  /// it. Only styling for [PageSettings.sizesMainText] reads it.
  final double mainTextSize;
}

/// The main text size of a book that sets no type size of its own: the
/// browser's initial font size, in pixels.
const defaultMainTextSize = 16.0;

/// The spine indices of the sections that [measureMainTextSize] reads, of
/// a book whose sections are [lengths] bytes long: the three longest, in
/// spine order.
///
/// The longest sections hold most of a book's text. On each of the 90 books
/// of the corpus (docs/research/native-epub-corpus.md), the three longest
/// give the same main text size as the whole book, at a fraction of the
/// cost of styling every section.
List<int> mainTextSamples(List<int> lengths) {
  final longest = [for (var index = 0; index < lengths.length; index++) index]
    ..sort((a, b) => lengths[b].compareTo(lengths[a]));
  return longest.take(3).toList()..sort();
}

/// The book's main text size: the font size in pixels that covers the most
/// visible characters of [samples] (white space, text that the book's style
/// hides and text of size 0 left out), with the book's own type sizes. The
/// reader's text size does not change it. On a tie the size that comes
/// first wins. A book with no visible text in [samples] gets
/// [defaultMainTextSize], and a sample that does not parse counts no
/// characters.
///
/// A whole book decides it, not each section, so that a section that is all
/// small print, such as the notes, stays smaller than the main text.
///
/// The page size does not change it either: it is measured on the reader's
/// usual phone page, 412 × 671 pixels. Only media queries could make it
/// depend on the page size. Of the 90 corpus books, 8 have media queries on
/// the page width, and none of them sets a type size or hides text. So a
/// book has one main text size, which admission keeps
/// (`Publication.mainTextSize`).
double measureMainTextSize(List<SectionSource> samples) => _mostCharacters(
  samples,
  (source, dom) => _styleSection(source, dom, _mainTextPage, 1).styles,
);

/// The page that [measureMainTextSize] styles the book for.
const _mainTextPage = PageSettings(
  width: 412,
  height: 671,
  fontSize: defaultMainTextSize,
  night: false,
);

/// The size in pixels of the book's main text as pages of [settings] show
/// it: the font size that covers the most visible characters of [samples],
/// as [measureMainTextSize] counts them, styled for [settings]. When
/// [PageSettings.sizesMainText], it is the settings' text size. Otherwise
/// the reader's text size is the body's, and a book that fixes its own
/// sizes shows them.
double shownMainTextSize(List<SectionSource> samples, PageSettings settings) =>
    _mostCharacters(
      samples,
      (source, dom) => styleSection(source, dom, settings).styles,
    );

/// The font size that covers the most visible characters of [samples],
/// each styled by [style].
double _mostCharacters(
  List<SectionSource> samples,
  Map<DomElement, Style> Function(SectionSource source, DomSection dom) style,
) {
  final characters = <double, int>{};
  for (final source in samples) {
    final DomSection dom;
    try {
      dom = DomSection.parse(source.xhtml);
    } on Exception {
      // NOTE: Preparing the section reports it when the reader reaches it.
      continue;
    }
    final styles = style(source, dom);
    bool hidden(DomElement element) =>
        styles[element]!.display == Display.none ||
        (element.parent != null && hidden(element.parent!));
    for (final text in dom.texts) {
      if (hidden(text.parent!)) continue;
      final size = styles[text.parent!]!.fontSize;
      final count = visibleCount(text.text, 0, text.text.length);
      if (size <= 0 || count == 0) continue;
      characters.update(size, (total) => total + count, ifAbsent: () => count);
    }
  }
  if (characters.isEmpty) return defaultMainTextSize;
  return characters.entries
      .reduce((most, next) => next.value > most.value ? next : most)
      .key;
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
    this.fonts, {
    this.firstPrepared = 0,
    this.reachesEnd = true,
  });

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

  /// The first flow item that a part of the section ([preparePart])
  /// prepared: the item after its last [SkippedItem]. 0 for a whole
  /// section.
  final int firstPrepared;

  /// Whether [flow] goes on to the section's end. A part of the section
  /// ends before it when the section goes on after the part.
  final bool reachesEnd;

  /// Whether this is the whole section, not a part of it.
  bool get whole => firstPrepared == 0 && reachesEnd;

  /// The flow of [element] alone, as a section to lay out on a page of
  /// [settings], or null when no flow item shows a node of [element].
  ///
  /// It holds the flow items from the first to the last that shows a node
  /// of [element]. A paragraph that holds a node of [element] comes whole,
  /// without the runs of the elements of [omit], and a paragraph that
  /// [omit] leaves with no text but white space goes. [settings] has the
  /// text size and the theme of [this.settings]; its width and its height
  /// can differ.
  ///
  /// The excerpt lays out as a fragment of its own, which starts at the
  /// left edge and the top of its page and ends at its last line:
  /// - The boxes around [element] are left out, with their margins,
  ///   padding and borders. The box of [element] is the excerpt's root, and
  ///   has no margins.
  /// - The top margins that meet the excerpt's top are cut, as at a page
  ///   break. Layout cuts the bottom margins at its end.
  /// - The first paragraph has no first-line indent.
  /// - The list marker that the page draws left of the first line, of
  ///   [element] or of a box around it, comes before the first word, as a
  ///   label that no node owns.
  PreparedSection? excerpt(
    DomElement element,
    PageSettings settings, {
    List<DomElement> omit = const [],
  }) {
    (int, int) span(DomElement element) {
      var last = element as DomNode;
      while (last is DomElement && last.children.isNotEmpty) {
        last = last.children.last;
      }
      return (element.order, last.order);
    }

    final (from, to) = span(element);
    bool inside(int node) => node >= from && node <= to;
    bool runShows(InlineRun run) => switch (run) {
      TextRun(:final node) ||
      BreakRun(:final node) ||
      ImageRun(:final node) => inside(node),
      RaisedRun(:final node, :final text) =>
        inside(node) || text.runs.any(runShows),
    };
    bool shows(FlowItem item) => switch (item) {
      ParagraphItem(:final text) => text.runs.any(runShows),
      ImageItem(:final node) => inside(node),
      TableItem(:final rows) => rows.any(
        (row) => row.any((cell) => cell.flow.any(shows)),
      ),
      BlockStart() || BlockEnd() || SkippedItem() => false,
    };
    final omitted = [for (final element in omit) span(element)];
    bool kept(InlineRun run) => !omitted.any(
      (span) => _nodeOf(run) >= span.$1 && _nodeOf(run) <= span.$2,
    );
    StyledText strip(StyledText text) => StyledText(text.style, text.align, [
      for (final run in text.runs)
        if (kept(run))
          run is RaisedRun
              ? RaisedRun(run.node, strip(run.text), run.shift)
              : run,
    ]);
    bool omits(StyledText text) => text.runs.any(
      (run) => !kept(run) || (run is RaisedRun && omits(run.text)),
    );
    FlowItem? without(FlowItem item) {
      if (item is! ParagraphItem || !omits(item.text)) return item;
      final text = strip(item.text);
      if (text.runs.every((run) => run is TextRun && run.text.trim().isEmpty)) {
        return null;
      }
      return ParagraphItem(
        text: text,
        indent: item.indent,
        orphans: item.orphans,
        widows: item.widows,
      );
    }

    final first = flow.indexWhere(shows);
    if (first < 0) return null;
    final end = flow.lastIndexWhere(shows) + 1;
    final open = <BlockStart>[];
    for (final item in flow.take(first)) {
      if (item is BlockStart) open.add(item);
      if (item is BlockEnd) open.removeLast();
    }
    var depth = 0;
    for (final item in flow.getRange(first, end)) {
      if (item is BlockStart) depth++;
      if (item is BlockEnd) depth--;
    }
    final around = <int>{
      for (var parent = element.parent; parent != null; parent = parent.parent)
        parent.order,
    };
    final labeled = open.reversed
        .where((box) => box.marker != null)
        .firstOrNull;
    final label =
        labeled != null &&
            (around.contains(labeled.node) || labeled.node == element.order)
        ? labeled.marker
        : null;
    final boxes = <BlockStart>[];
    var top = true;
    for (final box in open) {
      if (around.contains(box.node)) continue;
      final root = box.node == element.order;
      boxes.add(
        BlockStart(
          node: box.node,
          placement: root ? box.placement.withoutMargins() : box.placement,
          marginTop: top ? 0 : box.marginTop,
          marginBottom: root ? 0 : box.marginBottom,
          padding: box.padding,
          border: box.border,
          marker: label != null && root ? null : box.marker,
          shrinkToFit: box.shrinkToFit,
          avoidBreakBefore: box.avoidBreakBefore,
          avoidBreakAfter: box.avoidBreakAfter,
          avoidBreakInside: box.avoidBreakInside,
        ),
      );
      // A margin inside a box's top padding or border does not meet the top.
      top = top && box.padding[0] == 0 && box.border[0] == 0;
    }
    final items = [
      for (final item in flow.getRange(first, end)) ?without(item),
    ];
    if (items.firstOrNull case final ParagraphItem paragraph) {
      items[0] = ParagraphItem(
        text: label == null
            ? paragraph.text
            : StyledText(paragraph.text.style, paragraph.text.align, [
                RaisedRun(
                  -1,
                  StyledText(label.style, Align.left, [
                    TextRun(
                      label.text,
                      label.style,
                      -1,
                      Int32List(label.text.length),
                    ),
                  ]),
                  0,
                ),
                ...paragraph.text.runs,
              ]),
        indent: const Length.px(0),
        orphans: paragraph.orphans,
        widows: paragraph.widows,
      );
    }
    return PreparedSection._(
      index,
      settings,
      dom,
      [
        ...boxes,
        ...items,
        for (var close = 0; close < boxes.length + depth; close++)
          const BlockEnd(),
      ],
      styles,
      fonts,
    );
  }
}

/// The [DomNode.order] of the node that [run] shows.
int _nodeOf(InlineRun run) => switch (run) {
  TextRun(:final node) ||
  BreakRun(:final node) ||
  ImageRun(:final node) ||
  RaisedRun(:final node) => node,
};

/// Prepares each of [sources] for a page of [settings].
List<PreparedSection> prepareSections(
  List<SectionSource> sources,
  PageSettings settings,
) => [for (final source in sources) _prepare(source, settings).section];

/// How many visible characters before its place a part of a section
/// holds ([preparePart]): enough for the page that holds the place to
/// start in the part at the smallest text size, and for the paragraph
/// before the place, which a place in white space needs.
const _partBefore = 6000;

/// How many visible characters after its place a part of a section holds:
/// enough for the page of the place and the page after it at the smallest
/// text size.
const _partAfter = 10000;

/// The place that [find] picks in the DOM of section [source], and the
/// part of the section around it, prepared for a page of [settings]. Both
/// are null when [find] picks no place.
///
/// The section is the whole section ([PreparedSection.whole]) when the
/// part would hold no paragraph, image or table at or after the place, or
/// would hold the whole section anyway. It is prepared from the same parse.
///
/// The part parses the whole section, but styles the elements and builds
/// the boxes only up to the end of the part, and makes text runs and
/// hyphenation only in the part: about [_partBefore] visible characters
/// before the place and [_partAfter] after it. Its flow items keep the
/// numbers that [prepareSections] gives them: the paragraphs, images and
/// tables before the part are [SkippedItem]s
/// ([PreparedSection.firstPrepared]), and the flow ends after the last
/// whole item of the part ([PreparedSection.reachesEnd]). So a run of the
/// part from a page start in it cuts the whole section's pages, until it
/// needs an item after the part ([LayoutRun.starved]).
///
/// A paragraph or a table that the part's end cuts is not in it. So the
/// part goes on to the end of the `p` element or the table that holds the
/// place, and a place in another block longer than the part, such as a
/// long `div` of text, gets the whole section.
({EpubPlace? place, PreparedSection? section}) preparePart(
  SectionSource source,
  PageSettings settings,
  EpubPlace? Function(DomSection dom) find,
) {
  final dom = DomSection.parse(source.xhtml);
  final place = find(dom);
  if (place == null) return (place: null, section: null);
  final at = dom.visibleBefore(place);
  final from = at - _partBefore;
  final to = at + _partAfter;
  int? until = to >= dom.visibleLength ? null : dom.textHolding(to).order;
  final block = _blockOf(dom.nodeAt(place.node));
  if (until != null && block != null) {
    until = math.max(until, _lastNode(block));
  }
  final (:section, :lastNode, :styles) = _prepare(
    source,
    settings,
    dom: dom,
    from: from <= 0 ? null : dom.textHolding(from).order,
    until: until,
  );
  if (section.whole || (lastNode != null && place.node <= lastNode)) {
    return (place: place, section: section);
  }
  // The whole section keeps the part's styles, so that no element is
  // styled twice.
  final whole = _prepare(source, settings, dom: dom, styled: styles);
  return (place: place, section: whole.section);
}

/// The element whose whole flow item a place in [node] needs: the
/// outermost table that holds [node], else the nearest `p` element, or
/// null.
DomElement? _blockOf(DomNode node) {
  DomElement? table;
  DomElement? paragraph;
  for (
    var element = node is DomElement ? node : node.parent;
    element != null;
    element = element.parent
  ) {
    if (element.name == 'table') table = element;
    if (element.name == 'p') paragraph ??= element;
  }
  return table ?? paragraph;
}

/// Prepares [source] for [settings], or only a part of it: with [from],
/// the paragraphs, images and tables whose nodes all come before the node
/// [from] are [SkippedItem]s, and with [until], the elements after the
/// node [until] are neither styled nor boxed, and the flow ends before
/// the first item that they cut. [dom] is the section already parsed, and
/// [styled] the styles of its elements that an earlier prepare of it for
/// [settings] computed. Also gives the last node of the last paragraph,
/// image or table that it prepared, or null when it prepared none, and the
/// styles that it computed.
({PreparedSection section, int? lastNode, Map<DomElement, Style> styles})
_prepare(
  SectionSource source,
  PageSettings settings, {
  DomSection? dom,
  int? from,
  int? until,
  Map<DomElement, Style> styled = const {},
}) {
  final parsed = dom ?? DomSection.parse(source.xhtml);
  final (:styles, faces: declared) = styleSection(
    source,
    parsed,
    settings,
    until: until,
    styled: styled,
  );
  final faces = _Faces(declared, source.fontPrefix);
  final builder = _BoxBuilder(styles, until: until);
  final body = builder.block(parsed.body);
  final flattener = _Flattener(
    source,
    settings,
    styles,
    faces,
    skipBefore: from,
  );
  flattener.block(body, settings.width);
  return (
    section: PreparedSection._(
      source.index,
      settings,
      parsed,
      flattener.flow,
      flattener.runStyles,
      faces.used.toList(),
      firstPrepared: flattener.firstPrepared,
      reachesEnd: !builder.cut,
    ),
    lastNode: flattener.lastNode,
    styles: styles,
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
    required this.node,
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

  /// The [DomNode.order] of the element whose box this is.
  final int node;

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

/// A paragraph, an image or a table that a part of a section
/// ([preparePart]) leaves out, because it comes before the part. It keeps
/// the numbers of the items after it. No run lays it out.
final class SkippedItem extends FlowItem {
  const SkippedItem();
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
    required this.image,
    required this.sizing,
    required this.marginLeft,
    required this.centered,
    required this.marginTop,
    required this.marginBottom,
  });

  /// The image element's [DomNode.order].
  final int node;
  final DrawnImage image;

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
  const TableItem(this.rows, this.width, this.spacing);

  /// The rows of cells, in document order. A cell spans the columns of its
  /// colspan, and every row starts at the first column.
  final List<List<TableCell>> rows;

  /// The width in pixels that the lengths in the cells resolve against: the
  /// widest that the table's content can be.
  final double width;

  /// The space in pixels between the columns and at the table's sides, and
  /// between the rows and at its top and bottom: its `border-spacing`, or
  /// none when its borders collapse.
  final (double, double) spacing;
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

/// A soft hyphen: a place where a line can break inside a word, and gets a
/// hyphen when it does.
const softHyphen = 0xad;

/// A piece of inline content.
sealed class InlineRun {
  const InlineRun();
}

/// Text in one style, after white space collapsing and text transform.
///
/// Where the text asks for hyphenation, it holds a soft hyphen at each
/// place where the line can break inside a word. Such a soft hyphen is not
/// in the text node, and its offset is that of the letter before it. So a
/// line that ends with it ends at that letter.
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
  const ImageRun(this.node, this.image, this.sizing);

  /// The image element's [DomNode.order].
  final int node;
  final DrawnImage image;

  /// How the image's size follows from the paragraph's width.
  final ImageSizing sizing;
}

/// Raised or lowered text, such as a superscript, drawn as a small
/// paragraph of its own in the line.
final class RaisedRun extends InlineRun {
  const RaisedRun(this.node, this.text, this.shift);

  /// The [DomNode.order] of the raised text's first text node, or of its
  /// element when it has no text. -1 for a label that no node owns, such
  /// as a list marker before an excerpt's first word: its text is not the
  /// book's.
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

  /// This style as a JSON list, which [RunStyle.fromJson] reads.
  List<Object?> toJson() => [
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
  ];

  /// The style of [json], a list that [toJson] wrote. Throws a
  /// [FormatException] for any other value.
  factory RunStyle.fromJson(Object? json) => switch (json) {
    [
      final String family,
      final num size,
      final int weight,
      final bool italic,
      final num letterSpacing,
      final num wordSpacing,
      final num? lineHeight,
      final bool underline,
      final bool lineThrough,
      final bool smallCaps,
      final bool oldstyleFigures,
    ] =>
      RunStyle(
        family: family,
        size: size.toDouble(),
        weight: weight,
        italic: italic,
        letterSpacing: letterSpacing.toDouble(),
        wordSpacing: wordSpacing.toDouble(),
        lineHeight: lineHeight?.toDouble(),
        underline: underline,
        lineThrough: lineThrough,
        smallCaps: smallCaps,
        oldstyleFigures: oldstyleFigures,
      ),
    _ => throw const FormatException('Not a run style.'),
  };

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

  /// This placement with no side margins: the box starts at the left of
  /// its containing block.
  BoxPlacement withoutMargins() => BoxPlacement(
    marginLeft: 0,
    marginRight: 0,
    horizontal: horizontal,
    used: used,
    autoLeft: false,
    autoRight: false,
    parentAlign: null,
  );

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

/// What a page draws for an image: the decoded file at [path], with its
/// colors inverted by [invert], or else [alt] in the image's box. A page
/// draws an outline while the file is not decoded yet, and in place of a
/// file that cannot decode and has no [alt].
final class DrawnImage {
  const DrawnImage(this.path, {this.invert = 0, this.alt = ''});

  /// The image's publication path, or empty when it leaves the publication.
  final String path;

  /// How far `filter: invert()` moves the image's colors toward their
  /// inverse, from 0 (unchanged) to 1 (inverted).
  final double invert;

  /// The image's `alt` text, or empty.
  final String alt;
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
/// `@font-face` rules of those sheets. With [until], only the elements up
/// to the node [until] in document order have a style. [styled] holds the
/// styles that an earlier call computed for the same [dom] and [settings]:
/// they are kept, and only the other elements are styled.
({Map<DomElement, Style> styles, List<FontFaceRule> faces}) styleSection(
  SectionSource source,
  DomSection dom,
  PageSettings settings, {
  int? until,
  Map<DomElement, Style> styled = const {},
}) => _styleSection(
  source,
  dom,
  settings,
  settings.sizesMainText ? settings.fontSize / source.mainTextSize : null,
  until: until,
  styled: styled,
);

/// [styleSection] with each of the book's own type sizes grown by
/// [fontScale] (see [Cascade.fontScale]), or, when [fontScale] is null,
/// with the body's font size set to the reader's text size, as epub.js
/// sets it.
({Map<DomElement, Style> styles, List<FontFaceRule> faces}) _styleSection(
  SectionSource source,
  DomSection dom,
  PageSettings settings,
  double? fontScale, {
  int? until,
  Map<DomElement, Style> styled = const {},
}) {
  final media = MediaContext(
    width: settings.width,
    height: settings.height,
    night: settings.night,
  );
  final sheets = sectionSheets(source, dom, media);
  final rules = <StyleRule>[
    for (final sheet in sheets) ...sheet.rules,
    ...StyleSheet.parse(
      _readerCss(settings),
      firstOrder: 1 << 30,
      media: media,
    ).rules,
  ];
  final cascade = Cascade(
    rules,
    userAgent: _userAgentSheet.rules,
    overrides: {
      dom.body: [
        if (fontScale == null)
          Declaration('font-size', '${settings.fontSize}px', false),
        ..._bodyOverrides(settings),
      ],
    },
    fontScale: fontScale ?? 1,
  );
  final styles = <DomElement, Style>{};
  final initial = Style.initial()..fontSize *= fontScale ?? 1;
  final rootStyle =
      styled[dom.root] ?? cascade.compute(dom.root, initial, initial.fontSize);
  styles[dom.root] = rootStyle;
  void visit(DomElement element, Style parent) {
    for (final child in element.elements) {
      // The later siblings come after it too.
      if (until != null && child.order > until) return;
      final style =
          styled[child] ?? cascade.compute(child, parent, rootStyle.fontSize);
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
List<DomElement> elementsOf(DomElement root) {
  final found = <DomElement>[];
  void visit(DomElement element) {
    found.add(element);
    element.elements.forEach(visit);
  }

  visit(root);
  return found;
}

/// The horizontal padding of the page's body: half the column gap that
/// epub.js uses, a twelfth of the width rounded down to an even number.
double _sideMargin(double width) {
  final section = (width / 12).floor();
  return (section.isEven ? section : section - 1) / 2;
}

/// The rules that the former WebView reader added to each section: epub.js's
/// theme and image rules and the reader's own style.
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

/// The declarations that epub.js sets on the body element itself, but for
/// its font size.
List<Declaration> _bodyOverrides(PageSettings settings) {
  final side = _sideMargin(settings.width);
  return [
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
table { text-indent: 0; box-sizing: border-box; border-spacing: 2px;
  border-collapse: separate }
td, th { padding: 1px }
thead, tbody, tfoot, tr { vertical-align: middle }
td, th { vertical-align: inherit }
th { font-weight: bold; text-align: center }
caption { text-align: center }
''');

// Box building.

sealed class _Box {}

class _BlockBox extends _Box {
  _BlockBox(
    this.element,
    this.style,
    this.children, {
    this.marker,
    this.cut = false,
  });
  final DomElement element;
  final Style style;
  final List<_Box> children;
  final String? marker;

  /// Whether the box building stopped inside the box ([_BoxBuilder.cut]):
  /// its last child can be cut too, and the inline content after its last
  /// block child is left out.
  final bool cut;
}

/// A table with rows: the style of each row and its cells, each with its
/// colspan.
class _TableBox extends _Box {
  _TableBox(this.element, this.style, this.rows);
  final DomElement element;
  final Style style;
  final List<({Style style, List<(_BlockBox, int)> cells})> rows;
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
  _BoxBuilder(this.styles, {this.until});
  final Map<DomElement, Style> styles;

  /// The last node that the boxes hold, in document order, or null for
  /// every node.
  final int? until;

  /// Whether the building stopped at a node after [until]. Each box open
  /// then is cut ([_BlockBox.cut]), and a table open then is left out.
  bool cut = false;

  /// Whether [node] comes after [until]: then the building stops.
  bool _stopsAt(DomNode node) {
    if (until case final last? when node.order > last) cut = true;
    return cut;
  }

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
      if (_stopsAt(node)) return;
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
        final built = _table(child);
        // A table that the building stops in is left out.
        if (cut) return;
        if (built case (final captions, final table)) {
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
        if (cut) return;
        run.add(_RaisedItem(child, childStyle, inner));
        return;
      }
      for (final grandchild in child.children) {
        walk(grandchild, childStyle);
      }
    }

    for (final child in element.children) {
      walk(child, style);
      if (cut) break;
    }
    // The inline content that the building stopped in is left out.
    if (!cut) flush();
    return _BlockBox(element, style, children, marker: marker, cut: cut);
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
    final rows = <({Style style, List<(_BlockBox, int)> cells})>[];
    void row(DomElement tr) {
      _cells++;
      final cells = [
        for (final cell in tr.elements)
          if (!_stopsAt(cell) &&
              (cell.name == 'td' || cell.name == 'th') &&
              _visible(cell))
            (
              block(cell),
              (int.tryParse(cell.attributes['colspan'] ?? '') ?? 1).clamp(
                1,
                1000,
              ),
            ),
      ];
      _cells--;
      if (cells.isNotEmpty) rows.add((style: styles[tr]!, cells: cells));
    }

    for (final child in table.elements) {
      if (_stopsAt(child)) break;
      if (!_visible(child)) continue;
      switch (child.name) {
        case 'caption':
          captions.add(block(child));
        case 'tr':
          row(child);
        case 'thead' || 'tbody' || 'tfoot':
          for (final tr in child.elements) {
            if (_stopsAt(tr)) break;
            if (tr.name == 'tr' && _visible(tr)) row(tr);
          }
      }
    }
    if (rows.isEmpty) return null;
    return (captions, _TableBox(table, styles[table]!, rows));
  }

  void _inlineItems(DomElement element, Style style, List<_Item> out) {
    for (final child in element.children) {
      if (_stopsAt(child)) return;
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
  _Flattener(
    this.source,
    this.settings,
    this.styles,
    this.faces, {
    this.skipBefore,
  });
  final SectionSource source;
  final PageSettings settings;
  final Map<DomElement, Style> styles;
  final _Faces faces;

  /// The first node of a part of the section: a paragraph, an image or a
  /// table whose nodes all come before it is a [SkippedItem]. Null when
  /// none is skipped.
  final int? skipBefore;

  /// The number of boxes around the item being written whose content is
  /// never skipped: shrink-to-fit boxes, whose width layout measures from
  /// all their content, and table cells.
  int _keepAll = 0;

  /// The index of the flow item after the last [SkippedItem].
  int firstPrepared = 0;

  /// The last node of the last paragraph, image or table that is not
  /// skipped, or null before the first.
  int? lastNode;

  /// Whether an item whose last node is [last] is skipped.
  bool _skips(int last) =>
      _keepAll == 0 && skipBefore != null && last < skipBefore!;

  void _skip() {
    flow.add(const SkippedItem());
    firstPrepared = flow.length;
  }

  /// Notes a prepared item whose last node is [last]. An item in a cell
  /// comes after its table's own note, so the latest node counts.
  void _prepared(int last) => lastNode = math.max(lastNode ?? last, last);

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
    // A box that can shrink to fit needs all its content for its width, so
    // a part leaves it out when the part's end cuts it.
    if (box.cut && (inlineBlock || style.floated)) return;
    // A shrink-to-fit box with a block inside fills its containing block,
    // as when it is not shrink-to-fit.
    final shrinkToFit =
        (inlineBlock || style.floated) &&
        box.children.every((child) => child is _InlineBox);
    final placement = _start(
      box.element,
      style,
      width,
      marker: box.marker,
      shrinkToFit: shrinkToFit,
    );
    final (_, contentWidth) = placement.place(0, width);
    if (shrinkToFit) _keepAll++;
    _content(box, contentWidth);
    if (shrinkToFit) _keepAll--;
    // A cut box goes on after the part.
    if (!box.cut) flow.add(const BlockEnd());
  }

  /// Adds the content of [box], whose content box is [width] pixels wide.
  void _content(_BlockBox box, double width) {
    for (final child in box.children) {
      switch (child) {
        case _BlockBox():
          block(child, width);
        case _TableBox():
          _table(child, width);
        case _InlineBox() when _skips(_lastOf(child.items.last)):
          _skip();
        case _InlineBox():
          _prepared(_lastOf(child.items.last));
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
  /// pixels wide, and returns its placement. [box] gives its padding and
  /// border widths when they are not those of its style, as for a table
  /// whose borders collapse.
  BoxPlacement _start(
    DomElement element,
    Style style,
    double width, {
    required bool shrinkToFit,
    String? marker,
    ({List<double> padding, List<double> border})? box,
  }) {
    final marginLeft = style.margin[3].resolve(width);
    final marginRight = style.margin[1].resolve(width);
    final (:padding, :border) = box ?? _box(style, width);
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
        node: element.order,
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
  ///
  /// A table whose borders collapse has no border-spacing and no padding,
  /// as in Chromium. Its cells and its own box take the collapsed widths
  /// of table.dart, and each draws its half of each border.
  void _table(_TableBox table, double width) {
    final style = table.style;
    List<double> own(Style style) => [
      for (var side = 0; side < 4; side++) style.usedBorder(side),
    ];
    final collapsed = style.collapseBorders
        ? collapseBorders([
            for (final row in table.rows)
              (
                border: own(row.style),
                cells: [
                  for (final (cell, colspan) in row.cells)
                    (span: colspan, border: own(cell.style)),
                ],
              ),
          ], own(style))
        : null;
    final placement = _start(
      table.element,
      style,
      width,
      shrinkToFit: style.width.isAuto,
      box: collapsed == null
          ? null
          : (padding: const [0, 0, 0, 0], border: collapsed.table),
    );
    final (_, contentWidth) = placement.place(0, width);
    if (_skips(_lastNode(table.element))) {
      _skip();
      flow.add(const BlockEnd());
      return;
    }
    _prepared(_lastNode(table.element));
    _keepAll++;
    flow
      ..add(
        TableItem(
          [
            for (final (r, row) in table.rows.indexed)
              [
                for (final (c, (cell, colspan)) in row.cells.indexed)
                  _cell(
                    cell,
                    colspan,
                    contentWidth,
                    border: collapsed?.cells[r][c],
                  ),
              ],
          ],
          contentWidth,
          collapsed == null ? style.borderSpacing : (0, 0),
        ),
      )
      ..add(const BlockEnd());
    _keepAll--;
  }

  /// [cell], which spans [colspan] columns of a table whose content is at
  /// most [width] pixels wide. A cell has no margins, and its column
  /// decides its width. [border] gives its border widths when the table's
  /// borders collapse.
  TableCell _cell(
    _BlockBox cell,
    int colspan,
    double width, {
    List<double>? border,
  }) {
    final (:padding, border: styled) = _box(cell.style, width);
    border ??= styled;
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
    if (_skips(box.element.order)) {
      _skip();
      return;
    }
    _prepared(box.element.order);
    final style = box.style;
    flow.add(
      ImageItem(
        node: box.element.order,
        image: _drawn(box.element, style),
        sizing: _sizing(box.element, style),
        marginLeft: style.margin[3].resolve(width),
        centered: style.margin[3].isAuto && style.margin[1].isAuto,
        marginTop: style.margin[0].resolve(width),
        marginBottom: style.margin[2].resolve(width),
      ),
    );
  }

  DrawnImage _drawn(DomElement element, Style style) => DrawnImage(
    resolvePath(source.path, element.attributes['src'] ?? '') ?? '',
    invert: style.invert,
    alt: element.attributes['alt'] ?? '',
  );

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
  /// in one block, and hyphenated where they ask for it.
  List<InlineRun> _runs(List<_Item> items) {
    final runs = <InlineRun>[];
    // The language that hyphenates each run, or null.
    final languages = <String?>[];
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
          // With hyphens: none, a line does not break at the book's own
          // soft hyphens either.
          final keepSoftHyphens = style.hyphens != Hyphens.none;
          final out = StringBuffer();
          final offsets = <int>[];
          for (var index = 0; index < text.length; index++) {
            var code = text.codeUnitAt(index);
            if (code == softHyphen && !keepSoftHyphens) continue;
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
          // An empty lang names an unknown language, which has no patterns.
          languages.add(
            style.hyphens == Hyphens.auto
                ? style.language ?? source.language
                : null,
          );
        case _BreakItem(:final element):
          space = true;
          runs.add(BreakRun(element.order));
        case _ImageItem(:final element, :final style):
          space = false;
          runs.add(
            ImageRun(
              element.order,
              _drawn(element, style),
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
      if (languages.length < runs.length) languages.add(null);
    }
    return _hyphenate(runs, languages);
  }

  /// [runs] with a soft hyphen at each break that hyphenation allows, in
  /// text runs that [languages] gives a language with patterns. Runs of text
  /// next to each other form one text, so a word can span several of them.
  /// A word breaks by the patterns of the language at its start, and only
  /// where the text before the break asks for hyphenation.
  static List<InlineRun> _hyphenate(
    List<InlineRun> runs,
    List<String?> languages,
  ) {
    if (languages.every((language) => language == null)) return runs;
    final hyphenators = <String, Hyphenator?>{};
    Hyphenator? hyphenatorOf(int run) => switch (languages[run]) {
      final language? => hyphenators.putIfAbsent(
        language,
        () => Hyphenator.forLanguage(language),
      ),
      null => null,
    };
    // For each run, the places in its text that get a soft hyphen.
    final breaks = List.generate(runs.length, (_) => <int>[]);
    var first = 0;
    while (first < runs.length) {
      if (runs[first] is! TextRun) {
        first++;
        continue;
      }
      // The text of the runs from [first] to [end], and the run and the
      // place in it of each of its code units.
      var end = first;
      final joined = StringBuffer();
      final owners = <int>[];
      final places = <int>[];
      for (; end < runs.length && runs[end] is TextRun; end++) {
        final text = (runs[end] as TextRun).text;
        joined.write(text);
        for (var at = 0; at < text.length; at++) {
          owners.add(end);
          places.add(at);
        }
      }
      final text = joined.toString();
      for (final (start, stop) in hyphenationWords(text)) {
        final hyphenator = hyphenatorOf(owners[start]);
        if (hyphenator == null) continue;
        for (final at in hyphenator.breaks(text.substring(start, stop))) {
          final letter = start + at - 1;
          if (hyphenatorOf(owners[letter]) == null) continue;
          breaks[owners[letter]].add(places[letter] + 1);
        }
      }
      first = end;
    }
    return [
      for (final (index, run) in runs.indexed)
        if (run is TextRun && breaks[index].isNotEmpty)
          _withSoftHyphens(run, breaks[index])
        else
          run,
    ];
  }

  /// [run] with a soft hyphen before each of [places] in its text, in
  /// increasing order. Each soft hyphen has the offset of the letter
  /// before it.
  static TextRun _withSoftHyphens(TextRun run, List<int> places) {
    final text = StringBuffer();
    final offsets = Int32List(run.offsets.length + places.length);
    var unit = 0;
    void copy(int from, int to) {
      text.write(run.text.substring(from, to));
      for (var at = from; at < to; at++) {
        offsets[unit++] = run.offsets[at];
      }
    }

    var from = 0;
    for (final place in places) {
      copy(from, place);
      text.writeCharCode(softHyphen);
      offsets[unit++] = run.offsets[place - 1];
      from = place;
    }
    copy(from, run.text.length);
    return TextRun(text.toString(), run.style, run.node, offsets);
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

/// The last node in document order that [item] shows, or that an element
/// of it holds.
int _lastOf(_Item item) => switch (item) {
  _TextItem(:final node) => node.order,
  _ImageItem(:final element) ||
  _BreakItem(:final element) ||
  _RaisedItem(:final element) => _lastNode(element),
};

/// The last node of [node] and everything inside it, in document order.
int _lastNode(DomNode node) {
  var last = node;
  while (last is DomElement && last.children.isNotEmpty) {
    last = last.children.last;
  }
  return last.order;
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
