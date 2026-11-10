import 'dart:math' as math;
import 'dart:typed_data';

/// The kind of a block of a page, as the source of its geometry knows it. A
/// text layer knows only [text].
enum PageBlockKind { text, picture, table, unknown }

/// How the source sets the lines of a paragraph, when it says so.
/// The order is Tesseract's TessParagraphJustification.
enum ParagraphJustification { unknown, left, center, right }

/// Where the printed words of a page are. Lengths are in page units: 1.0 is
/// the page width, the origin is the top left corner, and y grows down.
/// Words are in reading order: the text layer's order, or Tesseract's.
///
/// It holds only typed lists, so it crosses isolates as blocks.
///
/// Invariants, which [checkInvariants] makes sure of:
/// - Every word box and block box has a positive area inside the page.
/// - Lines cover the words in order, and every line has a word.
/// - Blocks cover the lines in order. A block without lines is one box,
///   such as a picture.
/// - Paragraph starts are increasing lines of the page.
/// - Each list has its entries for each word, line, block or paragraph.
class PageGeometry {
  PageGeometry({
    required this.height,
    required this.boxes,
    required this.ownBaselines,
    required this.hyphens,
    required this.lineStarts,
    required this.lineMetrics,
    required this.blockStarts,
    required this.blockBoxes,
    required this.blockKinds,
    required this.paragraphStarts,
    required this.paragraphJustifications,
    required this.paragraphIndents,
  });

  /// The page height in page units.
  final double height;

  /// For each word: left, top, right and bottom.
  final Float32List boxes;

  /// For each word: the y of its own baseline at its left and right edges,
  /// or NaN when the source does not know it.
  final Float32List ownBaselines;

  /// For each word: the width of a hyphen that ends it, or 0.
  final Float32List hyphens;

  /// For each line: the index of its first word. One more entry ends the
  /// last line.
  final Int32List lineStarts;

  /// For each line: the y of its baseline at x = 0, its slope (the change
  /// of y for one unit of x), its height from ascender top to descender
  /// bottom, and its descender depth below the baseline.
  final Float32List lineMetrics;

  /// For each block: the index of its first line, and one more entry.
  final Int32List blockStarts;

  /// For each block: left, top, right and bottom.
  final Float32List blockBoxes;

  /// For each block: the index of its [PageBlockKind].
  final Uint8List blockKinds;

  /// The lines that start a paragraph in the source, when the source says
  /// so, with the paragraph's [ParagraphJustification] index and its
  /// first-line indent. Empty for a text layer.
  final Int32List paragraphStarts;
  final Uint8List paragraphJustifications;
  final Float32List paragraphIndents;

  int get wordCount => boxes.length ~/ 4;
  int get lineCount => lineStarts.length - 1;
  int get blockCount => blockStarts.length - 1;

  PageBlockKind blockKind(int block) => PageBlockKind.values[blockKinds[block]];
  ParagraphJustification paragraphJustification(int paragraph) =>
      ParagraphJustification.values[paragraphJustifications[paragraph]];

  double lineSlope(int line) => lineMetrics[line * 4 + 1];
  double lineHeight(int line) => lineMetrics[line * 4 + 2];
  double lineDescender(int line) => lineMetrics[line * 4 + 3];

  /// The y of [line]'s baseline at [x].
  double lineBaselineAt(int line, double x) =>
      lineMetrics[line * 4] + lineMetrics[line * 4 + 1] * x;

  /// The left edge of [line]'s first word, and the right edge of its last.
  double lineLeft(int line) => boxes[lineStarts[line] * 4];
  double lineRight(int line) => boxes[(lineStarts[line + 1] - 1) * 4 + 2];

  /// Throws a [StateError] when an invariant of the class comment, or of
  /// [attachment] for the reading text [source], does not hold. It runs only
  /// on demand, from a test or a debug switch.
  ///
  /// The invariants of an attachment: it has one range for each word; the
  /// ranges are in increasing order, do not overlap and lie in [source]; a
  /// range that names text does not start or end with white space.
  void checkInvariants({TextAttachment? attachment, String? source}) {
    void require(bool holds, String rule) {
      if (!holds) throw StateError('Page geometry: $rule.');
    }

    bool inside(Float32List list, int index) {
      final left = list[index * 4], top = list[index * 4 + 1];
      final right = list[index * 4 + 2], bottom = list[index * 4 + 3];
      return left >= 0 &&
          top >= 0 &&
          left < right &&
          top < bottom &&
          right <= 1 + 1e-6 &&
          bottom <= height + 1e-6;
    }

    require(height > 0 && height.isFinite, 'the page has a height');
    require(boxes.length % 4 == 0, 'each word has a box');
    for (var word = 0; word < wordCount; word++) {
      require(inside(boxes, word), 'word $word lies inside the page');
    }
    require(ownBaselines.length == wordCount * 2, 'each word has a baseline');
    require(hyphens.length == wordCount, 'each word has a hyphen width');
    require(
      lineStarts.isNotEmpty &&
          lineStarts.first == 0 &&
          lineStarts.last == wordCount,
      'lines cover the words',
    );
    for (var line = 0; line < lineCount; line++) {
      require(
        lineStarts[line] < lineStarts[line + 1],
        'line $line has a word, after the words of the line before it',
      );
    }
    require(lineMetrics.length == lineCount * 4, 'each line has its metrics');
    require(
      blockStarts.isNotEmpty &&
          blockStarts.first == 0 &&
          blockStarts.last == lineCount,
      'blocks cover the lines',
    );
    for (var block = 0; block < blockCount; block++) {
      require(
        blockStarts[block] <= blockStarts[block + 1],
        'block $block follows the lines of the block before it',
      );
      require(inside(blockBoxes, block), 'block $block lies inside the page');
    }
    require(
      blockBoxes.length == blockCount * 4 && blockKinds.length == blockCount,
      'each block has a box and a kind',
    );
    require(
      paragraphJustifications.length == paragraphStarts.length &&
          paragraphIndents.length == paragraphStarts.length,
      'each paragraph has a justification and an indent',
    );
    for (var paragraph = 0; paragraph < paragraphStarts.length; paragraph++) {
      require(
        paragraphStarts[paragraph] >= 0 &&
            paragraphStarts[paragraph] < lineCount &&
            (paragraph == 0 ||
                paragraphStarts[paragraph - 1] < paragraphStarts[paragraph]),
        'paragraph $paragraph starts on a later line of the page',
      );
    }
    if (attachment == null) return;
    require(
      source != null && attachment.length == wordCount * 2,
      'the attachment has a range for each word',
    );
    var end = 0;
    for (var word = 0; word < wordCount; word++) {
      final start = attachment[word * 2], stop = attachment[word * 2 + 1];
      require(
        end <= start && start <= stop && stop <= source!.length,
        'the range of word $word follows the range before it',
      );
      if (start < stop) {
        require(
          !_space.hasMatch(source![start]) &&
              !_space.hasMatch(source[stop - 1]),
          'the range of word $word does not start or end with white space',
        );
      }
      end = stop;
    }
  }
}

/// For each word of a [PageGeometry], its range of `PdfText.source`: the
/// first and the end character. An empty range (start == end) marks a word
/// that names no text, at the place between its neighbors.
typedef TextAttachment = Int32List;

/// The words that recognition found on a page, in the order of the reading
/// text. It holds only typed lists, so it crosses isolates as blocks.
class RecognizedWords {
  const RecognizedWords({
    required this.ranges,
    required this.boxes,
    required this.lines,
  });

  /// A page without words.
  static final none = RecognizedWords(
    ranges: Int32List(0),
    boxes: Float32List(0),
    lines: Int32List(0),
  );

  /// For each word: its first and end character of `PdfText.source`.
  final Int32List ranges;

  /// For each word: left, top, right and bottom in page units, or NaN when
  /// the recognition output does not say where the word is.
  final Float32List boxes;

  /// For each word: the index of its recognized line.
  final Int32List lines;

  int get count => lines.length;
}

/// The kinds of the entries of a layout record. native/ocr/bookfin_ocr.c
/// defines the record.
const _pageEntry = 0, _blockEntry = 1, _paragraphEntry = 2;
const _lineEntry = 3, _wordEntry = 4, _entry = 9;

/// The word geometry of the page whose layout pass gave [record], a list of
/// entries of nine numbers in raster pixels (see native/ocr/bookfin_ocr.c).
/// It runs in a hop. Throws a [FormatException] when [record] is not a
/// layout record of one page.
PageGeometry pageGeometryFromLayout(Int32List record) {
  if (record.isEmpty ||
      record.length % _entry != 0 ||
      record[0] != _pageEntry ||
      record[1] != 0 ||
      record[2] != 0 ||
      record[3] <= 0 ||
      record[4] <= 0) {
    throw const FormatException('Not a layout record of one page.');
  }
  final width = record[3].toDouble();
  final pixelHeight = record[4];
  final boxes = <double>[];
  final ownBaselines = <double>[];
  final lineStarts = <int>[];
  final lineBaselines = <(double, double, double, double)>[];
  final blockStarts = <int>[];
  final blockBoxes = <double>[];
  final blockKinds = <int>[];
  final paragraphStarts = <int>[];
  final paragraphJustifications = <int>[];
  final paragraphIndents = <double>[];
  int? paragraphPending;
  for (var index = _entry; index < record.length; index += _entry) {
    final kind = record[index];
    final left = record[index + 1], top = record[index + 2];
    final right = record[index + 3], bottom = record[index + 4];
    final a = record[index + 5], b = record[index + 6];
    final c = record[index + 7], d = record[index + 8];
    if (left < 0 ||
        top < 0 ||
        right <= left ||
        bottom <= top ||
        right > width ||
        bottom > pixelHeight) {
      throw const FormatException('A layout box lies outside its page.');
    }
    switch (kind) {
      case _blockEntry:
        if (paragraphPending != null) {
          throw const FormatException('A paragraph without lines.');
        }
        blockStarts.add(lineStarts.length);
        blockBoxes.addAll([
          left / width,
          top / width,
          right / width,
          bottom / width,
        ]);
        blockKinds.add(_blockKind(a).index);
      case _paragraphEntry:
        if (blockStarts.isEmpty || paragraphPending != null) {
          throw const FormatException('A paragraph outside a block.');
        }
        paragraphPending = paragraphJustifications.length;
        paragraphJustifications.add(
          a >= 0 && a < ParagraphJustification.values.length ? a : 0,
        );
        paragraphIndents.add(b / width);
      case _lineEntry:
        if (blockStarts.isEmpty) {
          throw const FormatException('A line outside a block.');
        }
        if (paragraphPending != null) {
          paragraphStarts.add(lineStarts.length);
          paragraphPending = null;
        }
        if (lineStarts.isNotEmpty && lineStarts.last == boxes.length ~/ 4) {
          throw const FormatException('A line without words.');
        }
        lineStarts.add(boxes.length ~/ 4);
        lineBaselines.add((
          a.toDouble(),
          b.toDouble(),
          c.toDouble(),
          d.toDouble(),
        ));
      case _wordEntry:
        if (lineStarts.isEmpty || paragraphPending != null) {
          throw const FormatException('A word outside a line.');
        }
        boxes.addAll([
          left / width,
          top / width,
          right / width,
          bottom / width,
        ]);
        // Tesseract gives the word's baseline at its box's edges; a line
        // through the two ends gives it exactly there.
        final slope = c == a ? 0.0 : (d - b) / (c - a);
        ownBaselines
          ..add((b + slope * (left - a)) / width)
          ..add((b + slope * (right - a)) / width);
      default:
        throw const FormatException('An unknown layout entry.');
    }
  }
  if (paragraphPending != null ||
      lineStarts.isNotEmpty && lineStarts.last == boxes.length ~/ 4) {
    throw const FormatException('A paragraph or line without words.');
  }
  final wordCount = boxes.length ~/ 4;
  lineStarts.add(wordCount);
  blockStarts.add(lineBaselines.length);
  final lineMetrics = Float32List(lineBaselines.length * 4);
  for (final (line, (x1, y1, x2, y2)) in lineBaselines.indexed) {
    final slope = x2 == x1 ? 0.0 : (y2 - y1) / (x2 - x1);
    final atZero = (y1 - slope * x1) / width;
    // A turned word's box grows by the slope over half its width at its top
    // and its bottom, so the ascent and the descent leave that out.
    var ascent = 0.0, descent = 0.0;
    for (var word = lineStarts[line]; word < lineStarts[line + 1]; word++) {
      final left = boxes[word * 4], right = boxes[word * 4 + 2];
      final center = (left + right) / 2;
      final baseline = atZero + slope * center;
      final turn = slope.abs() * (right - left) / 2;
      ascent = math.max(ascent, baseline - boxes[word * 4 + 1] - turn);
      descent = math.max(descent, boxes[word * 4 + 3] - baseline - turn);
    }
    lineMetrics
      ..[line * 4] = atZero
      ..[line * 4 + 1] = slope
      ..[line * 4 + 2] = math.max(ascent + descent, 1 / width)
      ..[line * 4 + 3] = math.min(descent, ascent + descent);
  }
  return PageGeometry(
    height: pixelHeight / width,
    boxes: Float32List.fromList(boxes),
    ownBaselines: Float32List.fromList(ownBaselines),
    hyphens: Float32List(wordCount),
    lineStarts: Int32List.fromList(lineStarts),
    lineMetrics: lineMetrics,
    blockStarts: Int32List.fromList(blockStarts),
    blockBoxes: Float32List.fromList(blockBoxes),
    blockKinds: Uint8List.fromList(blockKinds),
    paragraphStarts: Int32List.fromList(paragraphStarts),
    paragraphJustifications: Uint8List.fromList(paragraphJustifications),
    paragraphIndents: Float32List.fromList(paragraphIndents),
  );
}

/// The [PageBlockKind] of Tesseract's TessPolyBlockType [type]. Equations,
/// rules and noise are [PageBlockKind.unknown]: the page analysis finds
/// their ink.
PageBlockKind _blockKind(int type) => switch (type) {
  1 || 2 || 3 || 7 || 8 => PageBlockKind.text,
  9 || 10 || 11 => PageBlockKind.picture,
  6 => PageBlockKind.table,
  _ => PageBlockKind.unknown,
};

/// The visible words of a text layer page, from its character boxes, with
/// their ranges of [source], or null when the boxes are not usable. Words
/// entirely outside the page are not printed and have no geometry. Their
/// characters stay in [source], so the remaining ranges keep their meaning.
/// It runs in the hop that prepares the page's text.
///
/// [words] holds the first and the end character of each word of [source]:
/// a run without white space, cut after a line-end hyphen that pdfium marks
/// with U+0002. [boxes] holds left, top, right and bottom in PDF points, with
/// y up, for each UTF-16 code unit of [source]. The page is [width] by
/// [height] PDF points.
///
/// The boxes are not usable when a character has no finite box of positive
/// area, when a visible word crosses a page edge, or when a visible word is
/// more than three line heights tall.
({PageGeometry geometry, TextAttachment attachment})?
pageGeometryFromCharacters({
  required String source,
  required Float64List boxes,
  required Int32List words,
  required double width,
  required double height,
}) {
  if (words.isEmpty ||
      boxes.length != source.length * 4 ||
      !(width > 0 && width.isFinite && height > 0 && height.isFinite)) {
    return null;
  }
  final visibleRanges = <int>[];
  final visibleBoxes = <double>[];
  final visibleBaselines = <double>[];
  final bottoms = <double>[];
  for (var word = 0; word < words.length ~/ 2; word++) {
    var left = double.infinity, top = double.infinity;
    var right = -double.infinity, bottom = -double.infinity;
    bottoms.clear();
    for (var unit = words[word * 2]; unit < words[word * 2 + 1]; unit++) {
      final x1 = boxes[unit * 4], y1 = boxes[unit * 4 + 1];
      final x2 = boxes[unit * 4 + 2], y2 = boxes[unit * 4 + 3];
      if (!(x1.isFinite && x2.isFinite && x1 < x2) ||
          !(y1.isFinite && y2.isFinite && y2 < y1)) {
        return null;
      }
      left = math.min(left, x1 / width);
      top = math.min(top, (height - y1) / width);
      right = math.max(right, x2 / width);
      bottom = math.max(bottom, (height - y2) / width);
      // A character outside the BMP has one box for both of its code units,
      // so it counts once, at its first code unit.
      final code = source.codeUnitAt(unit);
      if (code >= 0xDC00 && code <= 0xDFFF) continue;
      final point = code >= 0xD800 && code <= 0xDBFF && unit + 1 < source.length
          ? 0x10000 +
                (code - 0xD800 << 10) +
                source.codeUnitAt(unit + 1) -
                0xDC00
          : code;
      if (!_descenders.contains(point)) bottoms.add((height - y2) / width);
    }
    if (right <= 0 || left >= 1 || bottom <= 0 || top >= height / width) {
      continue;
    }
    if (left < 0 || right > 1 || top < 0 || bottom > height / width) {
      return null;
    }
    visibleRanges.addAll([words[word * 2], words[word * 2 + 1]]);
    visibleBoxes.addAll([left, top, right, bottom]);
    final baseline = bottoms.isEmpty ? double.nan : _median(bottoms);
    visibleBaselines.addAll([baseline, baseline]);
  }
  if (visibleRanges.isEmpty) return null;
  final attachment = Int32List.fromList(visibleRanges);
  final wordCount = attachment.length ~/ 2;
  final wordBoxes = Float32List.fromList(visibleBoxes);
  final ownBaselines = Float32List.fromList(visibleBaselines);

  // A word starts a new line when it starts to the left of the word before
  // it, or when its height does not overlap the height of its line so far.
  // The text is a candidate, so its order is the reading order.
  // NOTE: pdfium puts a line break between a letter and its raised mark,
  // such as the 2 of v², and the mark's height overlaps the letter's height
  // only by about a fifth. So a mark that overlaps at all stays on its line.
  final lineStarts = <int>[0];
  var lineTop = wordBoxes[1], lineBottom = wordBoxes[3];
  for (var word = 1; word < wordCount; word++) {
    final top = wordBoxes[word * 4 + 1], bottom = wordBoxes[word * 4 + 3];
    if (wordBoxes[word * 4] < wordBoxes[(word - 1) * 4] ||
        math.min(bottom, lineBottom) <= math.max(top, lineTop)) {
      lineStarts.add(word);
      lineTop = top;
      lineBottom = bottom;
    } else {
      lineTop = math.min(lineTop, top);
      lineBottom = math.max(lineBottom, bottom);
    }
  }
  lineStarts.add(wordCount);
  final lineCount = lineStarts.length - 1;

  final lineMetrics = Float32List(lineCount * 4);
  final lineTops = Float64List(lineCount), lineBottoms = Float64List(lineCount);
  final hyphens = Float32List(wordCount);
  for (var line = 0; line < lineCount; line++) {
    final first = lineStarts[line], end = lineStarts[line + 1];
    final baselines = [
      for (var word = first; word < end; word++)
        if (!ownBaselines[word * 2].isNaN) ownBaselines[word * 2].toDouble(),
    ];
    final baseline = _median(
      baselines.isNotEmpty
          ? baselines
          : [
              for (var word = first; word < end; word++)
                wordBoxes[word * 4 + 3],
            ],
    );
    var top = double.infinity, bottom = -double.infinity;
    for (var word = first; word < end; word++) {
      top = math.min(top, wordBoxes[word * 4 + 1]);
      bottom = math.max(bottom, wordBoxes[word * 4 + 3]);
    }
    lineTops[line] = top;
    lineBottoms[line] = bottom;
    final ascent = math.max(baseline - top, 0.0);
    final descent = math.max(bottom - baseline, 0.0);
    lineMetrics
      ..[line * 4] = baseline
      ..[line * 4 + 1] = 0
      ..[line * 4 + 2] = math.max(ascent + descent, 1e-6)
      ..[line * 4 + 3] = descent;
    // A word that is only a hyphen is a dash, not the first half of a word.
    final last = end - 1;
    final hyphen = attachment[last * 2 + 1] - 1;
    if (hyphen > attachment[last * 2] &&
        _hyphens.contains(source.codeUnitAt(hyphen))) {
      hyphens[last] = (boxes[hyphen * 4 + 2] - boxes[hyphen * 4]) / width;
    }
  }

  final lineHeight = _median([
    for (var line = 0; line < lineCount; line++) lineMetrics[line * 4 + 2],
  ]);
  for (var word = 0; word < wordCount; word++) {
    if (wordBoxes[word * 4 + 3] - wordBoxes[word * 4 + 1] > 3 * lineHeight) {
      return null;
    }
  }

  // A line starts a new block when the gap above it is more than twice the
  // median line pitch, or when its left edge moves by more than a quarter
  // of the page width.
  final pitches = [
    for (var line = 1; line < lineCount; line++)
      if (lineMetrics[line * 4] > lineMetrics[(line - 1) * 4])
        lineMetrics[line * 4] - lineMetrics[(line - 1) * 4],
  ];
  final pitch = pitches.isEmpty ? double.infinity : _median(pitches);
  double lineLeft(int line) => wordBoxes[lineStarts[line] * 4];
  final blockStarts = <int>[0];
  for (var line = 1; line < lineCount; line++) {
    if (lineTops[line] - lineBottoms[line - 1] > 2 * pitch ||
        (lineLeft(line) - lineLeft(line - 1)).abs() > 0.25) {
      blockStarts.add(line);
    }
  }
  blockStarts.add(lineCount);
  final blockCount = blockStarts.length - 1;
  final blockBoxes = Float32List(blockCount * 4);
  for (var block = 0; block < blockCount; block++) {
    var left = double.infinity, top = double.infinity;
    var right = -double.infinity, bottom = -double.infinity;
    final first = lineStarts[blockStarts[block]];
    for (var word = first; word < lineStarts[blockStarts[block + 1]]; word++) {
      left = math.min(left, wordBoxes[word * 4]);
      top = math.min(top, wordBoxes[word * 4 + 1]);
      right = math.max(right, wordBoxes[word * 4 + 2]);
      bottom = math.max(bottom, wordBoxes[word * 4 + 3]);
    }
    blockBoxes
      ..[block * 4] = left
      ..[block * 4 + 1] = top
      ..[block * 4 + 2] = right
      ..[block * 4 + 3] = bottom;
  }

  return (
    geometry: PageGeometry(
      height: height / width,
      boxes: wordBoxes,
      ownBaselines: ownBaselines,
      hyphens: hyphens,
      lineStarts: Int32List.fromList(lineStarts),
      lineMetrics: lineMetrics,
      blockStarts: Int32List.fromList(blockStarts),
      blockBoxes: blockBoxes,
      blockKinds: Uint8List(blockCount)
        ..fillRange(0, blockCount, PageBlockKind.text.index),
      paragraphStarts: Int32List(0),
      paragraphJustifications: Uint8List(0),
      paragraphIndents: Float32List(0),
    ),
    attachment: attachment,
  );
}

/// The characters whose letters reach below the baseline, as Unicode code
/// points: Latin, Greek and mathematical italic letters with descenders,
/// and punctuation that hangs below the baseline. A word's own baseline is
/// the median bottom of its other characters.
final _descenders = {
  ...'gjpqyçşţęąųįǫ,;()[]{}|/_@\$§µßβγζημξρςφχψ'.runes,
  ...'𝑔𝑗𝑝𝑞𝑦𝛽𝛾𝜁𝜂𝜇𝜉𝜌𝜑𝜒𝜓𝜙'.runes,
};

/// The UTF-16 code units of a hyphen that can end a line: the hyphen-minus,
/// the soft hyphen, the hyphen, the non-breaking hyphen, and U+0002, which
/// pdfium puts in place of a hyphen that it found at a line end.
const _hyphens = {0x2D, 0xAD, 0x2010, 0x2011, 0x02};

/// The median of [values], which is not empty.
double _median(List<double> values) {
  final sorted = values.toList()..sort();
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2;
}

/// For each word of [page]'s geometry, its range of the reading text that
/// [page]'s recognized words name. It runs in a hop.
///
/// The layout pass and recognition can find slightly different words, so
/// the text attaches by box overlap, not by index:
/// 1. Each recognized word joins the layout word whose box overlaps it
///    most. The overlap must cover at least a third of the smaller box.
/// 2. A recognized word that joins no layout word joins the layout word of
///    the nearest earlier joined word on its recognized line, or else of
///    the nearest later one. A line without any joined word stays apart.
/// 3. A layout word's range runs from the first character of its first
///    joined word to the end of its last one.
/// 4. A layout word without joined words, or whose range would start before
///    the end of an earlier range, names no text.
TextAttachment attachText(
  ({PageGeometry geometry, RecognizedWords words}) page,
) {
  final geometry = page.geometry, words = page.words;
  final joined = Int32List(words.count)..fillRange(0, words.count, -1);
  double area(Float32List list, int index) =>
      (list[index * 4 + 2] - list[index * 4]) *
      (list[index * 4 + 3] - list[index * 4 + 1]);
  // NOTE: Each recognized word looks at every layout word. A dense page has
  // about 900 of each, which is under a million cheap steps in a hop.
  for (var word = 0; word < words.count; word++) {
    final left = words.boxes[word * 4], top = words.boxes[word * 4 + 1];
    final right = words.boxes[word * 4 + 2];
    final bottom = words.boxes[word * 4 + 3];
    if (!(left < right && top < bottom)) continue; // No box, or NaN.
    final own = area(words.boxes, word);
    var best = -1;
    var bestOverlap = 0.0;
    for (var layout = 0; layout < geometry.wordCount; layout++) {
      final boxes = geometry.boxes;
      final width =
          math.min(right, boxes[layout * 4 + 2]) -
          math.max(left, boxes[layout * 4]);
      if (width <= 0) continue;
      final height =
          math.min(bottom, boxes[layout * 4 + 3]) -
          math.max(top, boxes[layout * 4 + 1]);
      if (height <= 0) continue;
      final overlap = width * height;
      if (overlap > bestOverlap &&
          overlap * 3 >= math.min(own, area(boxes, layout))) {
        best = layout;
        bestOverlap = overlap;
      }
    }
    joined[word] = best;
  }
  final lineJoined = Int32List.fromList(joined);
  for (var word = 0; word < words.count; word++) {
    if (joined[word] >= 0) continue;
    final line = words.lines[word];
    var neighbor = -1;
    for (var before = word - 1; before >= 0; before--) {
      if (words.lines[before] != line) break;
      if (joined[before] >= 0) {
        neighbor = joined[before];
        break;
      }
    }
    if (neighbor < 0) {
      for (var after = word + 1; after < words.count; after++) {
        if (words.lines[after] != line) break;
        if (joined[after] >= 0) {
          neighbor = joined[after];
          break;
        }
      }
    }
    lineJoined[word] = neighbor;
  }
  final starts = Int32List(geometry.wordCount)
    ..fillRange(0, geometry.wordCount, -1);
  final ends = Int32List(geometry.wordCount);
  for (var word = 0; word < words.count; word++) {
    final layout = lineJoined[word];
    if (layout < 0) continue;
    final start = words.ranges[word * 2], end = words.ranges[word * 2 + 1];
    if (starts[layout] < 0 || start < starts[layout]) starts[layout] = start;
    if (end > ends[layout]) ends[layout] = end;
  }
  final attachment = Int32List(geometry.wordCount * 2);
  var end = 0;
  for (var layout = 0; layout < geometry.wordCount; layout++) {
    final start = starts[layout];
    if (start >= end) {
      end = ends[layout];
      attachment[layout * 2] = start;
    } else {
      attachment[layout * 2] = end;
    }
    attachment[layout * 2 + 1] = end;
  }
  return attachment;
}

final _space = RegExp(r'\s');
