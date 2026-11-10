import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'page_analysis.dart';
import 'page_geometry.dart';
import 'screen_cut.dart';

/// What a column is laid out for. Lengths are logical pixels.
class ColumnSettings {
  /// Throws an [ArgumentError] unless every value is positive and finite.
  ColumnSettings({
    required this.width,
    required this.fontSize,
    required this.screenHeight,
  }) {
    for (final (name, value) in [
      ('width', width),
      ('fontSize', fontSize),
      ('screenHeight', screenHeight),
    ]) {
      if (!(value > 0 && value.isFinite)) {
        throw ArgumentError.value(value, name, 'must be positive');
      }
    }
  }

  /// The width that the lines fill, without the screen's margins.
  final double width;

  /// The reader's text size after the system text scale.
  final double fontSize;

  /// The height of one screen of lines.
  final double screenHeight;
}

/// The words and regions of one source page, placed in lines and cut into
/// screens for one [ColumnSettings]. It holds only typed lists, so it
/// crosses isolates as blocks.
///
/// A piece is one word or one region of the page. Its source rectangle is in
/// page units of the reflow geometry. Its target rectangle is in logical
/// pixels from the column's top left corner. The source image, scaled to the
/// target rectangle, turns by the piece's rotation about the target's
/// center. A positive rotation turns clockwise on the screen.
///
/// A line is the pieces that share one baseline. Its top and bottom hold
/// the turned images of its pieces. The column's first line starts at
/// y = 0. A screen is the lines from its first line's top that fit in
/// [screenHeight]; [cutScreens] cuts them.
///
/// Invariants, which [checkInvariants] makes sure of:
/// - Each list has its entries for each piece, line or screen.
/// - A word or a region shows in at most one piece.
/// - Every piece's source rectangle has a positive area, and its target
///   rectangle has the same shape at a positive scale.
/// - Every target lies inside the column's width.
/// - Lines cover the pieces in order, and every line has a piece.
/// - Each line's top is above its bottom. Lines go down the column in
///   order and do not overlap.
/// - Screens cover the lines in order, and every screen has a line. A
///   screen of more than one line fits in [screenHeight].
class ReflowColumn {
  ReflowColumn({
    required this.width,
    required this.screenHeight,
    required this.scale,
    required this.pieces,
    required this.pieceItems,
    required this.lineStarts,
    required this.lineExtents,
    required this.screenStarts,
  });

  /// The width of the column and the height of a screen, in logical pixels.
  final double width;
  final double screenHeight;

  /// The logical pixels for one page unit of a word that fits the column.
  final double scale;

  /// For each piece: its source rectangle (left, top, right and bottom), its
  /// target rectangle (the same), and its rotation in radians.
  final Float32List pieces;

  /// For each piece: its word in the reflow geometry, or for a region,
  /// -1 - its region.
  final Int32List pieceItems;

  /// For each line: the index of its first piece. One more entry ends the
  /// last line.
  final Int32List lineStarts;

  /// For each line: its top, its baseline and its bottom.
  final Float32List lineExtents;

  /// For each screen: the index of its first line. One more entry ends the
  /// last screen.
  final Int32List screenStarts;

  static const _stride = 9;

  int get pieceCount => pieceItems.length;
  int get lineCount => lineStarts.length - 1;
  int get screenCount => screenStarts.length - 1;

  Rect source(int piece) => Rect.fromLTRB(
    pieces[piece * _stride],
    pieces[piece * _stride + 1],
    pieces[piece * _stride + 2],
    pieces[piece * _stride + 3],
  );

  Rect target(int piece) => Rect.fromLTRB(
    pieces[piece * _stride + 4],
    pieces[piece * _stride + 5],
    pieces[piece * _stride + 6],
    pieces[piece * _stride + 7],
  );

  double rotation(int piece) => pieces[piece * _stride + 8];

  /// The word of [piece] in the reflow geometry, or -1 for a region.
  int word(int piece) => pieceItems[piece] >= 0 ? pieceItems[piece] : -1;

  /// The region of [piece], or -1 for a word.
  int region(int piece) => pieceItems[piece] < 0 ? -1 - pieceItems[piece] : -1;

  double lineTop(int line) => lineExtents[line * 3];
  double lineBaseline(int line) => lineExtents[line * 3 + 1];
  double lineBottom(int line) => lineExtents[line * 3 + 2];

  /// The y in the column where [screen] starts: its first line's top.
  double screenTop(int screen) => lineTop(screenStarts[screen]);

  /// The screen that shows the place at [character] of the page's reading
  /// text. [ranges] gives each word of the reflow geometry its range of
  /// that text, and [analysis] is the page analysis that the column was
  /// laid out from.
  ///
  /// It is the screen of the first shown word, in reading order, whose
  /// range holds the character or starts after it. A word of a region
  /// shows in its region's piece. So a place inside a line that the column
  /// leaves out, such as a running header, opens at the next shown word,
  /// and a place after every shown word opens the last screen.
  int screenAt(int character, TextAttachment ranges, PageAnalysis analysis) {
    final pieceOf = <int, int>{
      for (var piece = 0; piece < pieceCount; piece++) pieceItems[piece]: piece,
    };
    var line = lineCount - 1;
    for (var word = 0; word < analysis.wordRegions.length; word++) {
      if (ranges[word * 2] == ranges[word * 2 + 1] ||
          ranges[word * 2 + 1] <= character) {
        continue;
      }
      final region = analysis.wordRegions[word];
      final piece = pieceOf[region < 0 ? word : -1 - region];
      if (piece == null) continue;
      line = 0;
      while (lineStarts[line + 1] <= piece) {
        line++;
      }
      break;
    }
    return _screenOfLine(line);
  }

  /// The place of [screen] in the page's reading text: the first character
  /// of the range of its first piece that names text, as [ranges] and
  /// [analysis] give them (see [screenAt]). A region's range starts at the
  /// first of its words that names text. Null when no piece of the screen
  /// names text. [screenAt] of the place is [screen].
  int? firstCharacter(
    int screen,
    TextAttachment ranges,
    PageAnalysis analysis,
  ) {
    final first = lineStarts[screenStarts[screen]];
    final end = lineStarts[screenStarts[screen + 1]];
    for (var piece = first; piece < end; piece++) {
      final region = this.region(piece);
      for (var word = 0; word < analysis.wordRegions.length; word++) {
        final shown = region >= 0
            ? analysis.wordRegions[word] == region
            : word == this.word(piece);
        if (shown && ranges[word * 2] < ranges[word * 2 + 1]) {
          return ranges[word * 2];
        }
      }
    }
    return null;
  }

  /// The screen of this column that shows the first piece of [screen] of
  /// [other], a column of the same page laid out for other settings: the
  /// screen of that piece's word or region, or of the first later piece of
  /// [other] that this column shows. It is the last screen when this column
  /// shows none of them. It needs no text, so a text size step keeps the
  /// shown words before a scanned page's text arrives.
  int screenShowing(ReflowColumn other, int screen) {
    final pieceOf = <int, int>{
      for (var piece = 0; piece < pieceCount; piece++) pieceItems[piece]: piece,
    };
    for (
      var piece = other.lineStarts[other.screenStarts[screen]];
      piece < other.pieceCount;
      piece++
    ) {
      final shown = pieceOf[other.pieceItems[piece]];
      if (shown == null) continue;
      var line = 0;
      while (lineStarts[line + 1] <= shown) {
        line++;
      }
      return _screenOfLine(line);
    }
    return screenCount - 1;
  }

  int _screenOfLine(int line) {
    var screen = 0;
    while (screenStarts[screen + 1] <= line) {
      screen++;
    }
    return screen;
  }

  /// Throws a [StateError] when an invariant of the class comment does not
  /// hold. It runs only on demand, from a test or a debug switch.
  void checkInvariants() {
    void require(bool holds, String rule) {
      if (!holds) throw StateError('Reflow column: $rule.');
    }

    // Float32 keeps about 7 digits, so lengths compare within a thousandth.
    const slack = 1e-3;
    require(
      pieces.length == pieceCount * _stride &&
          lineExtents.length == lineCount * 3,
      'each piece and line has its entries',
    );
    final shown = <int>{};
    for (var piece = 0; piece < pieceCount; piece++) {
      require(shown.add(pieceItems[piece]), 'piece $piece shows once');
      final from = source(piece), to = target(piece);
      require(from.width > 0 && from.height > 0, 'piece $piece has a source');
      final scale = to.width / from.width;
      require(
        scale > 0 &&
            (to.height - from.height * scale).abs() <=
                slack * math.max(1, to.height),
        'piece $piece keeps its shape',
      );
      require(
        to.left >= -slack && to.right <= width + slack,
        'piece $piece lies inside the column',
      );
    }
    require(
      lineStarts.isNotEmpty &&
          lineStarts.first == 0 &&
          lineStarts.last == pieceCount,
      'lines cover the pieces',
    );
    for (var line = 0; line < lineCount; line++) {
      require(
        lineStarts[line] < lineStarts[line + 1],
        'line $line has a piece',
      );
      require(lineTop(line) < lineBottom(line), 'line $line has a height');
      require(
        line == 0 || lineBottom(line - 1) <= lineTop(line) + slack,
        'line $line lies below the line before it',
      );
    }
    require(
      screenStarts.isNotEmpty &&
          screenStarts.first == 0 &&
          screenStarts.last == lineCount,
      'screens cover the lines',
    );
    for (var screen = 0; screen < screenCount; screen++) {
      final first = screenStarts[screen], end = screenStarts[screen + 1];
      require(first < end, 'screen $screen has a line');
      require(
        end - first == 1 ||
            lineBottom(end - 1) - lineTop(first) <= screenHeight + slack,
        'screen $screen fits its lines',
      );
    }
  }
}

/// The column of a page: its words wrapped to [ColumnSettings.width] in
/// lines, its regions kept whole, and its lines cut into screens. It runs in
/// a hop. It reads the reflow geometry and the page analysis, never the
/// text, so a page's screens do not move when its text arrives.
///
/// It leaves out the lines that the analysis marks as running lines, such
/// as running headers and folios, the running regions and the scan edges,
/// as the Original view's crop does (see `PageAnalysis.contentBox`). Their
/// text stays in the reading text, and [ReflowColumn.screenAt] opens a
/// place inside them at the next shown word.
///
/// [bodyLineHeight] is the line height in page units that scales the page:
/// one body line is [ColumnSettings.fontSize] times [_wordSizeRatio] tall.
/// Every word and region has that scale, so headings, footnotes and marks
/// keep their size ratios. A word wider than the column, and a region wider
/// than the column or taller than a screen, scale down to fit.
ReflowColumn layoutColumn(
  ({
    PageGeometry geometry,
    PageAnalysis analysis,
    double bodyLineHeight,
    ColumnSettings settings,
  })
  page,
) {
  if (!(page.bodyLineHeight > 0 && page.bodyLineHeight.isFinite)) {
    throw ArgumentError.value(page.bodyLineHeight, 'bodyLineHeight');
  }
  final source = _Source.of(page.geometry, page.analysis);
  final writer = _ColumnWriter(
    source,
    page.settings,
    page.settings.fontSize * _wordSizeRatio / page.bodyLineHeight,
  );
  for (final item in _flow(source)) {
    switch (item) {
      case _Paragraph():
        writer.addParagraph(item);
      case _Region():
        writer.addRegion(item);
    }
  }
  return writer.finish();
}

/// The height of a body line, from ascender top to descender bottom, for a
/// text size of 1. A body line at text size 20 then looks as big as EPUB
/// text at size 20.
/// TODO(tb-fb6j): the device acceptance tunes it once against an EPUB.
const _wordSizeRatio = 0.92;

/// The slope of a source line, in radians, above which its words turn level.
const _turnLimit = 0.3 * math.pi / 180;

/// The facts of a source page that the layout derives once from its reflow
/// geometry and analysis. Lengths are page units.
class _Source {
  _Source._(
    this.geometry,
    this.analysis,
    this.wordLines,
    this.lineBlocks,
    this.measures,
    this.pitches,
    this.pagePitch,
    this.wordGap,
  );

  factory _Source.of(PageGeometry geometry, PageAnalysis analysis) {
    final wordLines = Int32List(geometry.wordCount);
    final lineBlocks = Int32List(geometry.lineCount);
    for (var line = 0; line < geometry.lineCount; line++) {
      wordLines.fillRange(
        geometry.lineStarts[line],
        geometry.lineStarts[line + 1],
        line,
      );
    }
    for (var block = 0; block < geometry.blockCount; block++) {
      lineBlocks.fillRange(
        geometry.blockStarts[block],
        geometry.blockStarts[block + 1],
        block,
      );
    }
    final body = analysis.bodyLineHeight;

    // The baseline distance of each line from the line before it in its
    // block, when it lies below it within three line heights.
    final blockPitches = [
      for (var b = 0; b < geometry.blockCount; b++) <double>[],
    ];
    for (var line = 1; line < geometry.lineCount; line++) {
      if (lineBlocks[line] != lineBlocks[line - 1]) continue;
      final x = geometry.lineLeft(line);
      final distance =
          geometry.lineBaselineAt(line, x) -
          geometry.lineBaselineAt(line - 1, x);
      if (distance > 0 && distance <= 3 * geometry.lineHeight(line)) {
        blockPitches[lineBlocks[line]].add(distance);
      }
    }
    final all = blockPitches.expand((pitches) => pitches).toList();
    final pagePitch = all.isEmpty ? 1.2 * body : _median(all);
    final pitches = Float64List.fromList([
      for (final pitches in blockPitches)
        pitches.isEmpty ? pagePitch : _median(pitches),
    ]);

    // A block's measure: its box, widened by the blocks with prose that
    // overlap more than half of its width. A text layer's block is only as
    // wide as its words, so a heading alone does not show where the text
    // column ends, and only the measure shows that it is centered.
    final prose = List.filled(geometry.blockCount, false);
    for (var line = 0; line < geometry.lineCount; line++) {
      if (analysis.isProse(line)) prose[lineBlocks[line]] = true;
    }
    final boxes = geometry.blockBoxes;
    final measures = Float64List(geometry.blockCount * 2);
    for (var block = 0; block < geometry.blockCount; block++) {
      var left = boxes[block * 4], right = boxes[block * 4 + 2];
      final half = (right - left) / 2;
      for (var other = 0; other < geometry.blockCount; other++) {
        if (!prose[other]) continue;
        final overlap =
            math.min(boxes[block * 4 + 2], boxes[other * 4 + 2]) -
            math.max(boxes[block * 4], boxes[other * 4]);
        if (overlap <= half) continue;
        left = math.min(left, boxes[other * 4]);
        right = math.max(right, boxes[other * 4 + 2]);
      }
      measures
        ..[block * 2] = left
        ..[block * 2 + 1] = right;
    }

    final gaps = <double>[];
    for (var line = 0; line < geometry.lineCount; line++) {
      if (!analysis.isProse(line)) continue;
      for (
        var word = geometry.lineStarts[line] + 1;
        word < geometry.lineStarts[line + 1];
        word++
      ) {
        if (analysis.sourceWords[word] < 0 ||
            analysis.sourceWords[word - 1] < 0) {
          continue;
        }
        gaps.add(geometry.boxes[word * 4] - geometry.boxes[(word - 1) * 4 + 2]);
      }
    }
    return _Source._(
      geometry,
      analysis,
      wordLines,
      lineBlocks,
      measures,
      pitches,
      pagePitch,
      gaps.isEmpty ? body / 3 : _median(gaps),
    );
  }

  final PageGeometry geometry;
  final PageAnalysis analysis;

  /// For each word: its line. For each line: its block.
  final Int32List wordLines;
  final Int32List lineBlocks;

  /// For each block: the left and right edges of the text column that it
  /// sets its lines in. Only the test for centered lines uses it: the
  /// rules for indents, short lines and justified lines use the block's
  /// own box, because a ragged block ends short of a justified one.
  final Float64List measures;

  /// For each block: its median baseline pitch, or the page's.
  final Float64List pitches;
  final double pagePitch;

  /// The median gap between two source words of a prose line.
  final double wordGap;

  double get body => analysis.bodyLineHeight;

  /// Whether [region] shows in the column. A running region, such as a
  /// pencil page number in a scan's margin, and a scan edge, such as the
  /// dark border of a scanned page, do not.
  bool shows(int region) => analysis.isContentRegion(region, geometry);

  double measureLeft(int line) => measures[lineBlocks[line] * 2];
  double measureRight(int line) => measures[lineBlocks[line] * 2 + 1];

  /// How far [line] starts after its block's left edge, and how far it
  /// ends before its block's right edge.
  double indentOf(int line) =>
      geometry.lineLeft(line) - geometry.blockBoxes[lineBlocks[line] * 4];
  double shortOf(int line) =>
      geometry.blockBoxes[lineBlocks[line] * 4 + 2] - geometry.lineRight(line);
  double pitch(int line) => pitches[lineBlocks[line]];
  bool isExtra(int word) => analysis.sourceWords[word] < 0;

  /// The top and the bottom of [line], at its middle.
  double lineTop(int line) {
    final x = (geometry.lineLeft(line) + geometry.lineRight(line)) / 2;
    return geometry.lineBaselineAt(line, x) -
        geometry.lineHeight(line) +
        geometry.lineDescender(line);
  }

  double lineBottom(int line) {
    final x = (geometry.lineLeft(line) + geometry.lineRight(line)) / 2;
    return geometry.lineBaselineAt(line, x) + geometry.lineDescender(line);
  }
}

/// One thing of the flow of a page: a paragraph of words, or a region.
sealed class _Item {
  /// The top and the bottom of the item on the page.
  double get top;
  double get bottom;

  /// The baseline pitch of the item's lines, in page units.
  double get pitch;
}

/// How a paragraph sets its lines.
enum _Alignment { left, justified, center, right }

/// Words that reflow as one paragraph, in reading order, from the source
/// lines [lines].
class _Paragraph extends _Item {
  _Paragraph(this.source, this.words, this.lines, {required this.starts});
  final _Source source;
  final List<int> words;
  final List<int> lines;

  /// Whether the paragraph starts in the source, and is not the rest of a
  /// paragraph that a region interrupted.
  final bool starts;

  _Alignment alignment = _Alignment.left;

  /// The first line's indent, in page units.
  double indent = 0;

  /// Whether each line keeps with the next line, and whether the last line
  /// keeps with the item after the paragraph.
  bool keepLines = false, keepLast = false;

  @override
  double get top => source.lineTop(lines.first);
  @override
  double get bottom => source.lineBottom(lines.last);
  @override
  double get pitch => source.pitch(lines.first);

  /// Sets [alignment] and [indent] from the source lines, once the
  /// paragraph has all its words.
  ///
  /// A center or right justification of the layout pass stays. Tesseract
  /// calls a justified paragraph left, so for a left paragraph the geometry
  /// decides, as it does for a text layer: a paragraph whose lines all sit
  /// in the middle of their measure, with both margins more than a body
  /// line height and differing by less than one, is centered. A paragraph
  /// whose lines reach the right edge of their block, except its last, is
  /// justified. Other paragraphs are left aligned. An indented first line
  /// of a paragraph that starts keeps its indent, at most three body line
  /// heights.
  void settle() {
    final geometry = source.geometry, body = source.body;
    final layout = _layoutJustification();
    double leftMargin(int line) =>
        geometry.lineLeft(line) - source.measureLeft(line);
    double rightMargin(int line) =>
        source.measureRight(line) - geometry.lineRight(line);
    if (layout == ParagraphJustification.center ||
        lines.every(
          (line) =>
              leftMargin(line) > body &&
              rightMargin(line) > body &&
              (leftMargin(line) - rightMargin(line)).abs() < body,
        )) {
      alignment = _Alignment.center;
    } else if (layout == ParagraphJustification.right) {
      alignment = _Alignment.right;
    } else {
      if (lines.length > 1 &&
          lines
              .take(lines.length - 1)
              .every((line) => source.shortOf(line) <= _edgeTolerance * body)) {
        alignment = _Alignment.justified;
      }
      final first = source.indentOf(lines.first);
      if (starts && first > body / 2) indent = math.min(first, 3 * body);
    }
  }

  /// The justification that the layout pass gives the paragraph of the
  /// first line, or [ParagraphJustification.unknown].
  ParagraphJustification _layoutJustification() {
    final geometry = source.geometry;
    var paragraph = -1;
    while (paragraph + 1 < geometry.paragraphStarts.length &&
        geometry.paragraphStarts[paragraph + 1] <= lines.first) {
      paragraph++;
    }
    if (paragraph < 0 ||
        source.lineBlocks[geometry.paragraphStarts[paragraph]] !=
            source.lineBlocks[lines.first]) {
      return ParagraphJustification.unknown;
    }
    return geometry.paragraphJustification(paragraph);
  }
}

/// A region, kept whole.
class _Region extends _Item {
  _Region(this.source, this.region, {required this.keep});
  final _Source source;
  final int region;

  /// Whether it keeps with the item after it, its caption.
  final bool keep;

  @override
  double get top => source.analysis.regionBoxes[region * 4 + 1];
  @override
  double get bottom => source.analysis.regionBoxes[region * 4 + 3];
  @override
  double get pitch => source.pagePitch;
}

/// The paragraphs and regions of a page in the order that they reflow.
List<_Item> _flow(_Source source) {
  final geometry = source.geometry, analysis = source.analysis;
  final items = <_Item>[];
  final placed = List.filled(analysis.regionCount, false);
  final captions = _captions(source);
  final captionLines = {
    for (final caption in captions.values)
      for (
        var line = geometry.blockStarts[caption.block];
        line < geometry.blockStarts[caption.block + 1];
        line++
      )
        line,
  };

  // A region without words goes before the first line, in reading order,
  // that starts below its top and overlaps it in width, or else at the end.
  final holdsWords = List.filled(analysis.regionCount, false);
  for (final region in analysis.wordRegions) {
    if (region >= 0) holdsWords[region] = true;
  }
  final anchored = <int, List<int>>{};
  final boxes = analysis.regionBoxes;
  for (var region = 0; region < analysis.regionCount; region++) {
    if (holdsWords[region] || !source.shows(region)) continue;
    var anchor = geometry.lineCount;
    for (var line = 0; line < geometry.lineCount; line++) {
      if (!_flows(source, line) || captionLines.contains(line)) continue;
      final top = geometry.boxes[geometry.lineStarts[line] * 4 + 1];
      if (top > boxes[region * 4 + 1] &&
          geometry.lineLeft(line) < boxes[region * 4 + 2] &&
          boxes[region * 4] < geometry.lineRight(line)) {
        anchor = line;
        break;
      }
    }
    (anchored[anchor] ??= []).add(region);
  }
  for (final regions in anchored.values) {
    regions.sort((a, b) => boxes[a * 4 + 1].compareTo(boxes[b * 4 + 1]));
  }

  _Paragraph? open;
  void close() {
    if (open == null) return;
    items.add(open!..settle());
    open = null;
  }

  // A region and its caption go together, the caption centered before or
  // after the region as the page sets it, and kept on one screen with it.
  void place(int region) {
    close();
    placed[region] = true;
    final caption = captions[region];
    _Paragraph? words;
    if (caption != null) {
      final lines = [
        for (
          var line = geometry.blockStarts[caption.block];
          line < geometry.blockStarts[caption.block + 1];
          line++
        )
          line,
      ];
      words =
          _Paragraph(
              source,
              [
                for (
                  var word = geometry.lineStarts[lines.first];
                  word < geometry.lineStarts[lines.last + 1];
                  word++
                )
                  word,
              ],
              lines,
              starts: true,
            )
            ..alignment = _Alignment.center
            ..keepLines = true
            ..keepLast = caption.above;
    }
    if (words != null && caption!.above) items.add(words);
    items.add(_Region(source, region, keep: words != null && !caption!.above));
    if (words != null && !caption!.above) items.add(words);
  }

  // A running line, such as a running header or a folio, does not show.
  // Its text stays in the reading text, so search still finds it.
  int? previous;
  for (var line = 0; line < geometry.lineCount; line++) {
    if (captionLines.contains(line) || analysis.isRunning(line)) continue;
    for (final region in anchored[line] ?? const <int>[]) {
      place(region);
    }
    var first = true;
    for (
      var word = geometry.lineStarts[line];
      word < geometry.lineStarts[line + 1];
      word++
    ) {
      final region = analysis.wordRegions[word];
      if (region >= 0) {
        if (!placed[region] && source.shows(region)) place(region);
        continue;
      }
      final starts = first && _startsParagraph(source, line, previous);
      if (starts) close();
      final paragraph = open;
      if (paragraph == null) {
        open = _Paragraph(source, [word], [line], starts: starts);
      } else {
        if (paragraph.lines.last != line) paragraph.lines.add(line);
        paragraph.words.add(word);
      }
      first = false;
    }
    if (!first) previous = line;
  }
  for (final region in anchored[geometry.lineCount] ?? const <int>[]) {
    place(region);
  }
  close();
  return items;
}

/// The caption of each picture region that shows and has one: a text block
/// of at most three lines, with no word of a region and no running line,
/// that lies within one body line height above or below the region. At
/// least half of its width lies over or under the region. The nearest such
/// block is the caption, and a block captions one region.
Map<int, ({int block, bool above})> _captions(_Source source) {
  final geometry = source.geometry, analysis = source.analysis;
  final body = source.body;
  final blocks = geometry.blockBoxes, regions = analysis.regionBoxes;
  final captions = <int, ({int block, bool above})>{};
  for (var region = 0; region < analysis.regionCount; region++) {
    if (analysis.regionKind(region) != RegionKind.picture ||
        !source.shows(region)) {
      continue;
    }
    ({int block, bool above})? best;
    var nearest = double.infinity;
    for (var block = 0; block < geometry.blockCount; block++) {
      final first = geometry.blockStarts[block];
      final end = geometry.blockStarts[block + 1];
      if (end == first ||
          end - first > 3 ||
          geometry.blockKind(block) != PageBlockKind.text ||
          captions.values.any((caption) => caption.block == block)) {
        continue;
      }
      var text = true;
      for (var line = first; line < end; line++) {
        text = text && !analysis.isRunning(line);
      }
      for (
        var word = geometry.lineStarts[first];
        word < geometry.lineStarts[end];
        word++
      ) {
        text = text && analysis.wordRegions[word] < 0;
      }
      final width = blocks[block * 4 + 2] - blocks[block * 4];
      final overlap =
          math.min(blocks[block * 4 + 2], regions[region * 4 + 2]) -
          math.max(blocks[block * 4], regions[region * 4]);
      if (!text || overlap < width / 2) continue;
      for (final (gap, above) in [
        (blocks[block * 4 + 1] - regions[region * 4 + 3], false),
        (regions[region * 4 + 1] - blocks[block * 4 + 3], true),
      ]) {
        if (gap.abs() <= body && gap.abs() < nearest) {
          nearest = gap.abs();
          best = (block: block, above: above);
        }
      }
    }
    if (best != null) captions[region] = best;
  }
  return captions;
}

/// Whether [line] starts a paragraph, after the line [previous] that flowed
/// before it. A paragraph starts at the page's first line, at each
/// paragraph start of the layout pass, and where the geometry says so:
/// - the baseline is more than 1.5 pitches of its block below the line
///   before it;
/// - it is indented from its block's left edge by more than half a body
///   line height, the line before it reached its block's right edge, and
///   the lines before and after it in its block are not indented as much.
///   Lines that a side note narrows are all indented, and do not start
///   paragraphs.
/// - the line before it ended more than two body line heights short of its
///   block's right edge.
bool _startsParagraph(_Source source, int line, int? previous) {
  if (previous == null) return true;
  final geometry = source.geometry, body = source.body;
  if (geometry.paragraphStarts.contains(line)) return true;
  final left = geometry.lineLeft(line);
  final distance =
      geometry.lineBaselineAt(line, left) -
      geometry.lineBaselineAt(previous, left);
  if (distance > 1.5 * source.pitch(line)) return true;
  final short = source.shortOf(previous);
  if (short > 2 * body) return true;
  bool indentedAlike(int other) =>
      other >= 0 &&
      other < geometry.lineCount &&
      source.lineBlocks[other] == source.lineBlocks[line] &&
      geometry.lineLeft(other) > left - body / 2;
  return source.indentOf(line) > body / 2 &&
      short <= _edgeTolerance * body &&
      !indentedAlike(line - 1) &&
      !indentedAlike(line + 1);
}

/// How close to its block's right edge a line ends, in body line heights,
/// when it reaches that edge, as a justified line does.
const _edgeTolerance = 0.25;

/// Whether [line] holds a word that flows as a word, outside the regions,
/// and is no running line.
bool _flows(_Source source, int line) {
  final geometry = source.geometry;
  if (source.analysis.isRunning(line)) return false;
  for (
    var word = geometry.lineStarts[line];
    word < geometry.lineStarts[line + 1];
    word++
  ) {
    if (source.analysis.wordRegions[word] < 0) return true;
  }
  return false;
}

/// One word of a paragraph, with the gap before it, in page units.
class _Token {
  _Token(this.word, this.gap, {required this.glued, this.pairs = false});
  final int word;
  final double gap;

  /// Whether no line may break before it: it touches the word before it in
  /// print, as a raised mark, a closing quote or a superscript does.
  final bool glued;

  /// Whether it is the second half of a hyphen pair: the word before it
  /// ends the source line before with a hyphen, and it starts its line.
  final bool pairs;
}

/// A word placed on a reflowed line: the left edge of its target, its
/// scale, and whether it leaves out its hyphen.
class _Placed {
  _Placed(this.word, this.left, this.scale);
  final int word;
  double left;
  final double scale;
  bool joined = false;
}

/// A piece placed on a line whose baseline is at y = 0: its source
/// rectangle, the center and the size of its target, and its rotation.
class _Piece {
  _Piece(
    this.item,
    this.source,
    this.x,
    this.y,
    this.width,
    this.height,
    this.turn,
  );
  final int item;
  final List<double> source;
  final double x, y, width, height, turn;

  /// Half the height of the turned target.
  double get halfHeight =>
      (math.sin(turn) * width).abs() / 2 + (math.cos(turn) * height).abs() / 2;
}

/// Writes the lines of a column, from the top.
class _ColumnWriter {
  _ColumnWriter(this.source, this.settings, this.scale);
  final _Source source;
  final ColumnSettings settings;

  /// The logical pixels for one page unit.
  final double scale;

  final _pieces = <double>[];
  final _items = <int>[];
  final _lineStarts = <int>[];
  final _extents = <double>[];
  final _keeps = <bool>[];

  /// The bottom on the page of the item before, and whether it was a
  /// region.
  double? _sourceBottom;
  bool _afterRegion = false;

  double get _width => settings.width;

  void addParagraph(_Paragraph paragraph) {
    final lines = _wrap(paragraph);
    final gap = _gapBefore(paragraph, paragraph.starts || _afterRegion);
    for (final (index, line) in lines.indexed) {
      final last = index == lines.length - 1;
      _addLine(
        [for (final placed in line) _wordPiece(placed)],
        paragraph.pitch,
        index == 0 ? gap : 0,
        last ? paragraph.keepLast : paragraph.keepLines,
      );
    }
    _sourceBottom = paragraph.bottom;
    _afterRegion = false;
  }

  void addRegion(_Region item) {
    final boxes = source.analysis.regionBoxes, region = item.region;
    final box = boxes.sublist(region * 4, region * 4 + 4);
    final width = box[2] - box[0], height = box[3] - box[1];
    final fit = math.min(
      scale,
      math.min(_width / width, settings.screenHeight / height),
    );
    _addLine(
      [
        _Piece(
          -1 - region,
          box,
          _width / 2,
          -height * fit / 2,
          width * fit,
          height * fit,
          0,
        ),
      ],
      item.pitch,
      _gapBefore(item, true),
      item.keep,
    );
    _sourceBottom = item.bottom;
    _afterRegion = true;
  }

  /// The extra space above [item]'s first line, in logical pixels: the
  /// source's space beyond its line pitch, scaled, at most two pitches.
  double _gapBefore(_Item item, bool applies) {
    final bottom = _sourceBottom;
    if (!applies || bottom == null) return 0;
    final leading = item.pitch - source.body;
    return (item.top - bottom - leading).clamp(0, 2 * item.pitch) * scale;
  }

  /// The words of [paragraph] in reflowed lines, aligned.
  ///
  /// Words that no line may part are one chunk. A chunk goes on the current
  /// line when it fits, and otherwise starts the next line. A chunk wider
  /// than the column scales down to its width, alone.
  List<List<_Placed>> _wrap(_Paragraph paragraph) {
    final tokens = _tokens(paragraph);
    final lines = <List<_Placed>>[];
    // For each line: the chunks after which a gap can stretch, and the
    // right edge of its last word.
    final stretches = <List<int>>[];
    final rights = <double>[];
    var line = <_Placed>[];
    var stretch = <int>[];
    var right = 0.0;
    var start = 0;
    while (start < tokens.length) {
      var end = start + 1;
      var width = _wordWidth(tokens[start].word);
      while (end < tokens.length && tokens[end].glued) {
        width += tokens[end].gap + _wordWidth(tokens[end].word);
        end++;
      }
      final gap = tokens[start].gap * scale;
      // The two halves of a hyphen pair on one line read as one printed
      // word: the first loses its hyphen, and the second follows it with no
      // gap. On two lines, the first keeps its hyphen, as in print.
      final hyphen = line.isNotEmpty && tokens[start].pairs
          ? source.geometry.hyphens[line.last.word] * line.last.scale
          : 0.0;
      if (hyphen > 0 && right - hyphen + width * scale <= _width + 1e-6) {
        line.last.joined = true;
        right = _place(line, tokens, start, end, right - hyphen, scale);
      } else if (line.isNotEmpty &&
          right + gap + width * scale <= _width + 1e-6) {
        stretch.add(line.length);
        right = _place(line, tokens, start, end, right + gap, scale);
      } else {
        if (line.isNotEmpty) {
          lines.add(line);
          stretches.add(stretch);
          rights.add(right);
        }
        line = [];
        stretch = [];
        var left =
            lines.isEmpty &&
                (paragraph.alignment == _Alignment.left ||
                    paragraph.alignment == _Alignment.justified)
            ? paragraph.indent * scale
            : 0.0;
        if (left + width * scale > _width) left = 0;
        right = _place(
          line,
          tokens,
          start,
          end,
          left,
          math.min(scale, _width / width),
        );
      }
      start = end;
    }
    if (line.isNotEmpty) {
      lines.add(line);
      stretches.add(stretch);
      rights.add(right);
    }
    for (final (index, line) in lines.indexed) {
      final room = _width - rights[index];
      switch (paragraph.alignment) {
        case _Alignment.left:
          break;
        case _Alignment.justified:
          final gaps = stretches[index];
          if (index == lines.length - 1 || gaps.isEmpty) break;
          for (final (count, from) in gaps.indexed) {
            final until = count + 1 < gaps.length
                ? gaps[count + 1]
                : line.length;
            for (var word = from; word < until; word++) {
              line[word].left += room * (count + 1) / gaps.length;
            }
          }
        case _Alignment.center:
          for (final placed in line) {
            placed.left += room / 2;
          }
        case _Alignment.right:
          for (final placed in line) {
            placed.left += room;
          }
      }
    }
    return lines;
  }

  /// Places [tokens] from [start] to [end] on [line] from [left] at
  /// [scale], and gives the right edge of the last.
  double _place(
    List<_Placed> line,
    List<_Token> tokens,
    int start,
    int end,
    double left,
    double scale,
  ) {
    var x = left;
    for (var index = start; index < end; index++) {
      if (index > start) x += tokens[index].gap * scale;
      line.add(_Placed(tokens[index].word, x, scale));
      x += _wordWidth(tokens[index].word) * scale;
    }
    return x;
  }

  double _wordWidth(int word) =>
      source.geometry.boxes[word * 4 + 2] - source.geometry.boxes[word * 4];

  /// The words of [paragraph] with the gaps before them. Two words of one
  /// source line keep their source gap, at least a third and at most one
  /// body line height. Words that touch in print, closer than a tenth of a
  /// body line height, such as a text layer's superscript, and an extra
  /// word beside its neighbor, keep their exact gap and never part. Words of two source lines are the page's
  /// median word gap apart.
  List<_Token> _tokens(_Paragraph paragraph) {
    final geometry = source.geometry, body = source.body;
    final boxes = geometry.boxes;
    final tokens = <_Token>[];
    final normal = source.wordGap.clamp(body / 3, body);
    for (final (index, word) in paragraph.words.indexed) {
      if (index == 0) {
        tokens.add(_Token(word, 0, glued: false));
        continue;
      }
      final before = paragraph.words[index - 1];
      final line = source.wordLines[word];
      if (source.wordLines[before] != line) {
        tokens.add(
          _Token(
            word,
            normal,
            glued: false,
            pairs:
                geometry.hyphens[before] > 0 &&
                before == geometry.lineStarts[line] - 1 &&
                word == geometry.lineStarts[line],
          ),
        );
        continue;
      }
      final gap = boxes[word * 4] - boxes[before * 4 + 2];
      final glued =
          source.isExtra(word) ||
          source.isExtra(before) && before == geometry.lineStarts[line] ||
          gap < body / 10;
      tokens.add(
        _Token(
          word,
          glued ? gap.clamp(0, body) : gap.clamp(body / 3, body),
          glued: glued,
        ),
      );
    }
    return tokens;
  }

  /// The piece of [placed]. The point of its source line's baseline under
  /// its center lands on the line's baseline, y = 0. A word whose own
  /// baseline lies within a quarter of the line height of the line's
  /// baseline sits on its own baseline, and turns by its slope. This
  /// levels each word of a curved line near the spine. Another word, such
  /// as a raised mark, keeps its offset and turns by the line's slope. A
  /// slope of at most [_turnLimit] does not turn.
  _Piece _wordPiece(_Placed placed) {
    final geometry = source.geometry, word = placed.word;
    final box = geometry.boxes.sublist(word * 4, word * 4 + 4);
    final ownLeftX = box[0], ownRightX = box[2];
    if (placed.joined) box[2] -= geometry.hyphens[word];
    final line = source.wordLines[word];
    final center = (box[0] + box[2]) / 2;
    final atLine = geometry.lineBaselineAt(line, center);
    final ownLeft = geometry.ownBaselines[word * 2];
    final ownRight = geometry.ownBaselines[word * 2 + 1];
    final ownSlope = (ownRight - ownLeft) / (ownRightX - ownLeftX);
    final own = ownLeft + ownSlope * (center - ownLeftX);
    final onOwn =
        own.isFinite && (own - atLine).abs() <= geometry.lineHeight(line) / 4;
    final baseline = onOwn ? own : atLine;
    final slope = math.atan(onOwn ? ownSlope : geometry.lineSlope(line));
    final turn = slope.abs() > _turnLimit ? -slope : 0.0;
    final width = (box[2] - box[0]) * placed.scale;
    final height = (box[3] - box[1]) * placed.scale;
    final drop = ((box[1] + box[3]) / 2 - baseline) * placed.scale;
    return _Piece(
      word,
      box,
      placed.left + width / 2,
      math.cos(turn) * drop,
      width,
      height,
      turn,
    );
  }

  /// Adds a line of [pieces], placed on a baseline at y = 0, [gap] below
  /// the line before it plus the pitch.
  void _addLine(List<_Piece> pieces, double pitch, double gap, bool keep) {
    var ascent = -double.infinity, descent = -double.infinity;
    for (final piece in pieces) {
      ascent = math.max(ascent, piece.halfHeight - piece.y);
      descent = math.max(descent, piece.y + piece.halfHeight);
    }
    final double baseline;
    if (_extents.isEmpty) {
      baseline = ascent;
    } else {
      // The line before keeps the pitch below it. A taller line grows, and
      // keeps the source's leading below the line before it.
      final before = _extents[_extents.length - 2];
      final leading = math.max(0.0, (pitch - source.body) * scale);
      baseline =
          before +
          math.max(pitch * scale, _extents.last - before + leading + ascent) +
          gap;
    }
    _lineStarts.add(_items.length);
    for (final piece in pieces) {
      final y = baseline + piece.y;
      _pieces.addAll([
        ...piece.source,
        piece.x - piece.width / 2,
        y - piece.height / 2,
        piece.x + piece.width / 2,
        y + piece.height / 2,
        piece.turn,
      ]);
      _items.add(piece.item);
    }
    _extents.addAll([baseline - ascent, baseline, baseline + descent]);
    _keeps.add(keep);
  }

  ReflowColumn finish() {
    final lineCount = _keeps.length;
    final screens = cutScreens(
      [for (var line = 0; line < lineCount; line++) _extents[line * 3]],
      [for (var line = 0; line < lineCount; line++) _extents[line * 3 + 2]],
      _keeps,
      settings.screenHeight,
    );
    return ReflowColumn(
      width: _width,
      screenHeight: settings.screenHeight,
      scale: scale,
      pieces: Float32List.fromList(_pieces),
      pieceItems: Int32List.fromList(_items),
      lineStarts: Int32List.fromList([..._lineStarts, _items.length]),
      lineExtents: Float32List.fromList(_extents),
      screenStarts: screens,
    );
  }
}

/// The median of [values], which is not empty.
double _median(List<double> values) {
  final sorted = values.toList()..sort();
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2;
}
