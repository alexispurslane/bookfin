import 'dart:math' as math;
import 'dart:typed_data';

import 'page_analysis.dart';
import 'page_geometry.dart';

/// A page's reading text, and for each word of its reflow geometry, its
/// range of that text.
typedef PageReading = ({String source, TextAttachment attachment});

/// What the template finder and [RunningTemplates.mark] read of one analyzed
/// source page: its number, its reflow geometry and analysis (see
/// [analyzePage]), and its reading text, or null on a scanned page whose
/// text has not arrived.
typedef AnalyzedSourcePage = ({
  int sourcePage,
  PageGeometry geometry,
  PageAnalysis analysis,
  PageReading? text,
});

/// The box of a line in page units: left, top, right and bottom.
typedef LineBox = ({double left, double top, double right, double bottom});

/// An edge line of a page (see [RunningTemplates]): its index in the page's
/// reflow geometry, the box around its words, its text or null on a page
/// without text, and the white gap in page units between it and the nearest
/// other line of its page that shares some of its width (infinity when no
/// line does).
typedef EdgeLine = ({int line, LineBox box, String? text, double gap});

/// An edge region of a page: a region that is no scan edge, with its middle
/// within 12 percent of the page height from the top or bottom edge, as an
/// edge line's (see [RunningTemplates]). [region] is its index in the
/// page's analysis, and [box] its box.
typedef EdgeRegion = ({int region, LineBox box});

/// What the template finder and [RunningTemplates.matches] read of one
/// analyzed page: its source page number, its body line height, whether it
/// is a body page, its edge lines and its edge regions. A body page has at least 5 text
/// lines, and pictures cover at most half of it. So a cover, a title page, a
/// section break, a plate and a blank page are not body pages.
typedef PageEdges = ({
  int sourcePage,
  double bodyLineHeight,
  bool body,
  List<EdgeLine> edges,
  List<EdgeRegion> regions,
});

/// The templates of a book's running headers, running footers and folios,
/// which [findRunningTemplates] finds by repetition across the book's pages.
/// With them, one page's lines can be marked without its neighbors.
///
/// Only an edge line can match a template: one of the two highest and the
/// two lowest text lines of a page, with its middle within 12 percent of the
/// page height from the top or bottom edge. A text line holds no word of a
/// region, so a figure, a table or an equation never matches.
class RunningTemplates {
  RunningTemplates({
    required this.lineHeight,
    required this.texts,
    required this.folioOffsets,
    required this.shapes,
    this.regions = const [],
  });

  /// The book's body line height in page units: the median of the body line
  /// heights of the pages that the templates come from. Places are compared
  /// in it.
  final double lineHeight;

  /// The text signatures of running lines, each with the box of a line where
  /// it repeats. An edge line of a page with text is a running line when it
  /// has one of these signatures at the same place (see [_samePlace]).
  final List<({String signature, LineBox box})> texts;

  /// For each kind of folio: the number that it prints minus its source page
  /// number. An edge line of a page with text that holds only a number with
  /// one of these differences is a folio.
  final List<int> folioOffsets;

  /// The boxes of running lines on scanned pages without text, for each
  /// side: the parity of the source page number. An edge line of a page
  /// without text is a running line when it stands apart from the text (see
  /// [_apart]) and has the shape of one of its side's boxes (see
  /// [_sameShape]).
  final List<({int side, LineBox box})> shapes;

  /// The boxes of running regions, for each side. An edge region is a
  /// running region when it is small (see [_small]) and has the shape of
  /// one of its side's boxes (see [_sameShape]).
  final List<({int side, LineBox box})> regions;

  /// [page]'s analysis with the lines that match a template marked as
  /// running lines (see [PageAnalysis.runningLines]).
  // NOTE: This compares a page's few edge lines with a few templates. It
  // takes microseconds, far less than a hop to another isolate.
  PageAnalysis mark(AnalyzedSourcePage page) {
    final running = Uint8List(page.geometry.lineCount);
    final runningRegions = Uint8List(page.analysis.regionCount);
    final edges = pageEdges(page);
    for (final edge in edges.edges) {
      if (matches(page.sourcePage, edge)) running[edge.line] = 1;
    }
    for (final region in edges.regions) {
      if (matchesRegion(page.sourcePage, region)) {
        runningRegions[region.region] = 1;
      }
    }
    return page.analysis.withRunningLines(running, regions: runningRegions);
  }

  /// Whether [region], an edge region of source page [sourcePage], matches
  /// a region template, so that it is a running region.
  bool matchesRegion(int sourcePage, EdgeRegion region) =>
      _small(region.box, lineHeight) &&
      regions.any(
        (template) =>
            template.side == sourcePage % 2 &&
            _sameShape(region.box, template.box, lineHeight),
      );

  /// Whether [edge], an edge line of source page [sourcePage], matches a
  /// template, so that it is a running line.
  bool matches(int sourcePage, EdgeLine edge) {
    final text = edge.text;
    if (text == null) {
      final side = sourcePage % 2;
      return _apart(edge, lineHeight) &&
          shapes.any(
            (shape) =>
                shape.side == side &&
                _sameShape(edge.box, shape.box, lineHeight),
          );
    }
    final number = _folioNumber(text);
    final signature = _signature(text);
    return number != null && folioOffsets.contains(number - sourcePage) ||
        texts.any(
          (template) =>
              template.signature == signature &&
              _samePlace(edge.box, template.box, lineHeight),
        );
  }
}

/// The running templates of the book whose analyzed pages are [pages]. It
/// runs in a hop.
///
/// - Text signature. A line's signature is its text in lowercase, with each
///   run of white space as one space and each digit as `#`. A signature that
///   repeats at the same place (see [_samePlace]) on at least 3 pages within
///   20 source pages belongs to a running line. So a chapter's title that
///   repeats only through its chapter is a running header, and the same
///   title in larger type at the chapter's start is not.
/// - Folio. If the number of an edge line that holds only a number, arabic
///   or roman, minus its source page number is the same on at least 3 pages,
///   such lines are folios.
/// - Geometry signature. These templates mark scanned pages whose text has
///   not arrived. For each side, an edge line that stands apart from the
///   text, and whose shape (see [_sameShape]) repeats on at least 30 percent
///   of the side's body pages and on at least 3, belongs to a running line.
///   A body page has at least 5 text lines, and pictures cover at most half
///   of it. So a cover, a title page, a section break, a plate and a blank
///   page do not count.
/// - Region signature (t1-6pf5). For each side, a small edge region (see
///   [EdgeRegion]), narrower and lower than one body line height, whose
///   shape repeats on at least 30 percent of the side's body pages and on at
///   least 3, is a running region, such as a pencil page number or a
///   library stamp in a scan. Every other region stays content.
RunningTemplates findRunningTemplates(List<AnalyzedSourcePage> pages) =>
    runningTemplatesOf([for (final page in pages) pageEdges(page)]);

/// The running templates of the book whose pages have the edge lines
/// [pages] (see [findRunningTemplates]). It runs in a hop.
RunningTemplates runningTemplatesOf(List<PageEdges> pages) {
  final lineHeight = pages.isEmpty
      ? PageAnalysis.defaultLineHeight
      : _median([for (final page in pages) page.bodyLineHeight]);
  final folioPages = <int, Set<int>>{};
  final signatures = <String, List<(int, LineBox)>>{};
  for (final page in pages) {
    for (final edge in page.edges) {
      final text = edge.text;
      if (text == null) continue;
      final number = _folioNumber(text);
      if (number != null) {
        folioPages
            .putIfAbsent(number - page.sourcePage, () => {})
            .add(page.sourcePage);
      }
      final signature = _signature(text);
      if (signature.isNotEmpty) {
        signatures.putIfAbsent(signature, () => []).add((
          page.sourcePage,
          edge.box,
        ));
      }
    }
  }

  final texts = <({String signature, LineBox box})>[];
  for (final MapEntry(key: signature, value: lines) in signatures.entries) {
    for (final (number, box) in lines) {
      final repeats = {
        for (final (other, otherBox) in lines)
          if (other >= number &&
              other < number + _window &&
              _samePlace(box, otherBox, lineHeight))
            other,
      };
      if (repeats.length >= _repeats &&
          !texts.any(
            (template) =>
                template.signature == signature &&
                _samePlace(box, template.box, lineHeight),
          )) {
        texts.add((signature: signature, box: box));
      }
    }
  }

  /// For each side, the boxes that repeat their shape on at least 30
  /// percent of the side's body pages and on at least 3, among the boxes
  /// that [boxesOf] gives each body page.
  List<({int side, LineBox box})> repeated(
    Iterable<LineBox> Function(PageEdges page) boxesOf,
  ) {
    final templates = <({int side, LineBox box})>[];
    for (final side in [0, 1]) {
      final body = [
        for (final page in pages)
          if (page.sourcePage % 2 == side && page.body) boxesOf(page).toList(),
      ];
      final needed = math.max(_repeats, 0.3 * body.length);
      for (final box in body.expand((boxes) => boxes)) {
        final repeats = body.where(
          (boxes) => boxes.any((other) => _sameShape(box, other, lineHeight)),
        );
        if (repeats.length >= needed &&
            !templates.any(
              (template) =>
                  template.side == side &&
                  _sameShape(box, template.box, lineHeight),
            )) {
          templates.add((side: side, box: box));
        }
      }
    }
    return templates;
  }

  final shapes = repeated(
    (page) => [
      for (final edge in page.edges)
        if (_apart(edge, lineHeight)) edge.box,
    ],
  );
  final regions = repeated(
    (page) => [
      for (final region in page.regions)
        if (_small(region.box, lineHeight)) region.box,
    ],
  );

  return RunningTemplates(
    lineHeight: lineHeight,
    texts: texts,
    folioOffsets: [
      for (final MapEntry(key: offset, value: numbers) in folioPages.entries)
        if (numbers.length >= _repeats) offset,
    ],
    shapes: shapes,
    regions: regions,
  );
}

/// The number of pages on which a template must repeat.
const _repeats = 3;

/// The number of source pages within which a text signature must repeat.
const _window = 20;

/// The white gap, in body line heights, that sets a running line apart from
/// the text (see [_apart]).
const _apartGap = 0.75;

/// Whether [edge] stands apart from the text, in a book whose body line
/// height is [lineHeight]: a white gap of at least [_apartGap] body line
/// heights lies between it and every other line of its page that shares
/// some of its width. A running line stands apart from the text. Lines of
/// prose do not, so a page's first line of prose, which lies at the same
/// place on every page, is not a running line.
bool _apart(EdgeLine edge, double lineHeight) =>
    edge.gap >= _apartGap * lineHeight;

/// The edge lines of [page] (see [RunningTemplates]), and the facts about
/// the page that the template finder needs with them (see [PageEdges]).
// NOTE: This reads a page's lines a few times. It takes microseconds, far
// less than a hop to another isolate.
PageEdges pageEdges(AnalyzedSourcePage page) {
  final lines = _lines(page);
  final lineTexts = _lineTexts(page);
  double middle(int line) => _middle(lines[line].box).$2;
  final text = [
    for (var line = 0; line < lines.length; line++)
      if (lines[line].text) line,
  ]..sort((a, b) => middle(a).compareTo(middle(b)));
  final height = page.geometry.height;
  final edge = 0.12 * height;
  double gap(int line) {
    final box = lines[line].box;
    var gap = double.infinity;
    for (var other = 0; other < lines.length; other++) {
      final near = lines[other].box;
      if (other == line || near.left >= box.right || near.right <= box.left) {
        continue;
      }
      gap = math.min(
        gap,
        math.max(near.top - box.bottom, box.top - near.bottom),
      );
    }
    return gap;
  }

  final analysis = page.analysis;
  var pictures = 0.0;
  for (var region = 0; region < analysis.regionCount; region++) {
    if (analysis.regionKind(region) != RegionKind.picture) continue;
    final box = analysis.regionBoxes;
    pictures +=
        (box[region * 4 + 2] - box[region * 4]) *
        (box[region * 4 + 3] - box[region * 4 + 1]);
  }
  return (
    sourcePage: page.sourcePage,
    bodyLineHeight: analysis.bodyLineHeight,
    body: text.length >= 5 && pictures <= height / 2,
    edges: [
      for (final line in {
        ...text.take(2).where((line) => middle(line) <= edge),
        ...text.reversed.take(2).where((line) => middle(line) >= height - edge),
      })
        (
          line: line,
          box: lines[line].box,
          text: lineTexts?[line],
          gap: gap(line),
        ),
    ],
    regions: [
      for (var region = 0; region < analysis.regionCount; region++)
        if (!analysis.isScanEdge(region, page.geometry))
          if (_regionBox(analysis, region) case final box
              when _middle(box).$2 <= edge || _middle(box).$2 >= height - edge)
            (region: region, box: box),
    ],
  );
}

/// For each line of [page]: the box around its words, and whether it is a
/// text line, which holds no word of a region.
List<({LineBox box, bool text})> _lines(AnalyzedSourcePage page) => [
  for (var line = 0; line < page.geometry.lineCount; line++) _line(page, line),
];

/// The box around the words of [line] of [page], and whether it is a text
/// line.
({LineBox box, bool text}) _line(AnalyzedSourcePage page, int line) {
  final geometry = page.geometry;
  var left = double.infinity, top = double.infinity;
  var right = -double.infinity, bottom = -double.infinity;
  var text = true;
  for (
    var word = geometry.lineStarts[line];
    word < geometry.lineStarts[line + 1];
    word++
  ) {
    text = text && page.analysis.wordRegions[word] < 0;
    left = math.min(left, geometry.boxes[word * 4]);
    top = math.min(top, geometry.boxes[word * 4 + 1]);
    right = math.max(right, geometry.boxes[word * 4 + 2]);
    bottom = math.max(bottom, geometry.boxes[word * 4 + 3]);
  }
  return (
    box: (left: left, top: top, right: right, bottom: bottom),
    text: text,
  );
}

/// The box of [region] of [analysis].
LineBox _regionBox(PageAnalysis analysis, int region) {
  final boxes = analysis.regionBoxes;
  return (
    left: boxes[region * 4],
    top: boxes[region * 4 + 1],
    right: boxes[region * 4 + 2],
    bottom: boxes[region * 4 + 3],
  );
}

/// Whether [box] is small, in a book whose body line height is
/// [lineHeight]: narrower and lower than one body line height.
bool _small(LineBox box, double lineHeight) =>
    box.right - box.left < lineHeight && box.bottom - box.top < lineHeight;

/// The middle of [box]: x and y.
(double, double) _middle(LineBox box) =>
    ((box.left + box.right) / 2, (box.top + box.bottom) / 2);

/// Whether the lines with the boxes [a] and [b] have the same shape, in a
/// book whose body line height is [lineHeight]: their middles lie within
/// half a line height, and their heights differ by at most a quarter of the
/// taller.
bool _sameShape(LineBox a, LineBox b, double lineHeight) {
  final (ax, ay) = _middle(a);
  final (bx, by) = _middle(b);
  final aHeight = a.bottom - a.top, bHeight = b.bottom - b.top;
  return (ax - bx).abs() <= lineHeight / 2 &&
      (ay - by).abs() <= lineHeight / 2 &&
      (aHeight - bHeight).abs() <= math.max(aHeight, bHeight) / 4;
}

/// Whether the lines with the boxes [a] and [b] lie at the same place, in a
/// book whose body line height is [lineHeight]: they have the same shape
/// (see [_sameShape]), and they share half the width of the wider.
bool _samePlace(LineBox a, LineBox b, double lineHeight) =>
    _sameShape(a, b, lineHeight) &&
    math.min(a.right, b.right) - math.max(a.left, b.left) >=
        math.max(a.right - a.left, b.right - b.left) / 2;

/// The signature of a line whose text is [text]: in lowercase, each run of
/// white space as one space, and each digit as `#`.
String _signature(String text) =>
    text.toLowerCase().trim().replaceAll(_space, ' ').replaceAll(_digit, '#');

final _space = RegExp(r'\s+');
final _digit = RegExp('[0-9]');

/// For each line of [page], its text, or null when the page has no text.
List<String>? _lineTexts(AnalyzedSourcePage page) {
  final text = page.text;
  if (text == null) return null;
  final geometry = page.geometry;
  return [
    for (var line = 0; line < geometry.lineCount; line++)
      text.source.substring(
        text.attachment[geometry.lineStarts[line] * 2],
        text.attachment[(geometry.lineStarts[line + 1] - 1) * 2 + 1],
      ),
  ];
}

/// The number that [text] holds when it holds only a number, arabic or
/// lowercase or capital roman, with punctuation around it, or null.
int? _folioNumber(String text) {
  final match = _folio.firstMatch(text.trim().toLowerCase());
  if (match == null) return null;
  final arabic = match[1];
  if (arabic != null) return int.parse(arabic);
  final roman = match[2]!;
  if (roman.isEmpty) return null;
  var value = 0;
  for (var index = 0; index < roman.length; index++) {
    final digit = _romanDigits[roman[index]]!;
    final next = index + 1 < roman.length ? _romanDigits[roman[index + 1]]! : 0;
    value += digit < next ? -digit : digit;
  }
  return value;
}

/// A folio's text: up to 5 arabic digits, or a well-formed roman number,
/// with punctuation around it but no letters or other digits.
final _folio = RegExp(
  r'^[^0-9a-z]*(?:([0-9]{1,5})|'
  r'(m{0,3}(?:cm|cd|d?c{0,3})(?:xc|xl|l?x{0,3})(?:ix|iv|v?i{0,3})))'
  r'[^0-9a-z]*$',
);

const _romanDigits = {
  'i': 1,
  'v': 5,
  'x': 10,
  'l': 50,
  'c': 100,
  'd': 500,
  'm': 1000,
};

/// The median of [values], which is not empty.
double _median(List<double> values) {
  final sorted = values.toList()..sort();
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2;
}
