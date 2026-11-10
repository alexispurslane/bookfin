import 'dart:math' as math;
import 'dart:typed_data';

import 'page_geometry.dart';

/// How reflow treats a region. A picture keeps its colors. Ink, such as an
/// equation, a table or a drop cap, takes the theme's text color.
enum RegionKind { picture, ink }

/// The facts about a page that need its pixels: the regions that reflow
/// keeps whole, the prose lines and the body line height. Lengths are in
/// page units. It holds only typed lists, so it crosses isolates as blocks.
///
/// It describes the reflow geometry that [analyzePage] gives with it: the
/// page's word geometry with the ink that no word covered as extra words.
///
/// Invariants, which [checkInvariants] makes sure of:
/// - Each list has its entries for each word, line or region.
/// - Every region box has a positive area inside the page, holds the boxes
///   of its words, and does not overlap another region.
/// - The source words of the reflow words are in increasing order.
/// - A prose line holds no word of a region.
/// - A running line holds no word of a region.
/// - The body line height is positive.
class PageAnalysis {
  PageAnalysis({
    required this.regionBoxes,
    required this.regionKinds,
    required this.wordRegions,
    required this.proseLines,
    required this.sourceWords,
    required this.bodyLineHeight,
    Uint8List? runningLines,
  }) : runningLines = runningLines ?? Uint8List(proseLines.length);

  /// For each region: left, top, right and bottom.
  final Float32List regionBoxes;

  /// For each region: the index of its [RegionKind].
  final Uint8List regionKinds;

  /// For each word of the reflow geometry: the region that holds it, or -1.
  final Int32List wordRegions;

  /// For each line: 1 when it is a prose line, and otherwise 0. A prose line
  /// passes the prose line test and holds no word of a region.
  final Uint8List proseLines;

  /// For each word of the reflow geometry: its index in the word geometry
  /// that the analysis started from, or -1 for ink that no word covered.
  final Int32List sourceWords;

  /// The median height of the prose lines, from ascender top to descender
  /// bottom. A page without prose lines takes the median height of all its
  /// lines, and a page without lines takes [defaultLineHeight].
  final double bodyLineHeight;

  /// For each line: 1 when it is a running line, and otherwise 0. A running
  /// line is a running header, a running footer or a folio. The book's
  /// templates find them by repetition across pages (see
  /// `RunningTemplates.mark` in running_lines.dart). The analysis that
  /// [analyzePage] gives marks none.
  final Uint8List runningLines;

  /// The body line height of a page without lines: a 12 point line on a
  /// page 6 inches wide.
  static const defaultLineHeight = 12 / 432;

  int get regionCount => regionKinds.length;
  RegionKind regionKind(int region) => RegionKind.values[regionKinds[region]];
  bool isProse(int line) => proseLines[line] != 0;
  bool isRunning(int line) => runningLines[line] != 0;

  /// This analysis with the running lines [runningLines], one entry for
  /// each line.
  PageAnalysis withRunningLines(Uint8List runningLines) => PageAnalysis(
    regionBoxes: regionBoxes,
    regionKinds: regionKinds,
    wordRegions: wordRegions,
    proseLines: proseLines,
    sourceWords: sourceWords,
    bodyLineHeight: bodyLineHeight,
    runningLines: runningLines,
  );

  /// The content box of the page whose reflow geometry is [geometry]: left,
  /// top, right and bottom in page units. It is the union of the boxes of
  /// the page's words and regions, without the words of running lines and
  /// without scan edges. All four are 0 on a page without content.
  ///
  /// A scan edge is a region that touches an edge of the page, runs along
  /// more than half of that edge and is thinner than the body line height,
  /// such as the dark border of a scanned page.
  Float32List contentBox(PageGeometry geometry) {
    var left = double.infinity, top = double.infinity;
    var right = -double.infinity, bottom = -double.infinity;
    void add(List<double> boxes, int index) {
      left = math.min(left, boxes[index * 4]);
      top = math.min(top, boxes[index * 4 + 1]);
      right = math.max(right, boxes[index * 4 + 2]);
      bottom = math.max(bottom, boxes[index * 4 + 3]);
    }

    for (var line = 0; line < geometry.lineCount; line++) {
      if (isRunning(line)) continue;
      for (
        var word = geometry.lineStarts[line];
        word < geometry.lineStarts[line + 1];
        word++
      ) {
        add(geometry.boxes, word);
      }
    }
    for (var region = 0; region < regionCount; region++) {
      if (!isScanEdge(region, geometry)) add(regionBoxes, region);
    }
    if (left > right) return Float32List(4);
    return Float32List.fromList([left, top, right, bottom]);
  }

  /// Whether [region] is a scan edge of the page whose reflow geometry is
  /// [geometry] (see [contentBox]). It touches an edge when it lies within
  /// [_edgeTouch] of it.
  bool isScanEdge(int region, PageGeometry geometry) {
    final left = regionBoxes[region * 4], top = regionBoxes[region * 4 + 1];
    final right = regionBoxes[region * 4 + 2];
    final bottom = regionBoxes[region * 4 + 3];
    final along = right - left > 0.5 && bottom - top < bodyLineHeight;
    final down =
        bottom - top > 0.5 * geometry.height && right - left < bodyLineHeight;
    return along &&
            (top <= _edgeTouch || bottom >= geometry.height - _edgeTouch) ||
        down && (left <= _edgeTouch || right >= 1 - _edgeTouch);
  }

  /// How near a region lies to an edge of the page when it touches it: 3
  /// pixels of a page drawn 1600 pixels wide.
  static const _edgeTouch = 3 / 1600;
  int get proseLineCount => proseLines.fold(0, (count, line) => count + line);

  /// Throws a [StateError] when an invariant of the class comment does not
  /// hold for this analysis of the reflow geometry [geometry]. It runs only
  /// on demand, from a test or a debug switch.
  void checkInvariants(PageGeometry geometry) {
    void require(bool holds, String rule) {
      if (!holds) throw StateError('Page analysis: $rule.');
    }

    require(
      wordRegions.length == geometry.wordCount &&
          sourceWords.length == geometry.wordCount &&
          proseLines.length == geometry.lineCount &&
          runningLines.length == geometry.lineCount &&
          regionBoxes.length == regionCount * 4,
      'each word, line and region has its entries',
    );
    require(
      bodyLineHeight > 0 && bodyLineHeight.isFinite,
      'the body line height is positive',
    );
    for (var region = 0; region < regionCount; region++) {
      final left = regionBoxes[region * 4], top = regionBoxes[region * 4 + 1];
      final right = regionBoxes[region * 4 + 2];
      final bottom = regionBoxes[region * 4 + 3];
      require(
        left >= 0 &&
            top >= 0 &&
            left < right &&
            top < bottom &&
            right <= 1 + 1e-6 &&
            bottom <= geometry.height + 1e-6,
        'region $region lies inside the page',
      );
      for (var other = region + 1; other < regionCount; other++) {
        require(
          !_overlap(regionBoxes, region, regionBoxes, other, 0),
          'regions $region and $other do not overlap',
        );
      }
    }
    var source = -1;
    for (var word = 0; word < geometry.wordCount; word++) {
      final region = wordRegions[word];
      require(
        region >= -1 && region < regionCount,
        'word $word names a region',
      );
      if (region >= 0) {
        require(
          _holds(regionBoxes, region, geometry.boxes, word),
          'region $region holds the box of word $word',
        );
      }
      if (sourceWords[word] >= 0) {
        require(
          sourceWords[word] > source,
          'the source words are in increasing order',
        );
        source = sourceWords[word];
      }
    }
    for (var line = 0; line < geometry.lineCount; line++) {
      for (
        var word = geometry.lineStarts[line];
        word < geometry.lineStarts[line + 1];
        word++
      ) {
        require(
          !isProse(line) || wordRegions[word] == -1,
          'prose line $line holds no region',
        );
        require(
          !isRunning(line) || wordRegions[word] == -1,
          'running line $line holds no region',
        );
      }
    }
  }
}

/// The reflow geometry of a page and its [PageAnalysis].
typedef AnalyzedPage = ({PageGeometry geometry, PageAnalysis analysis});

/// The page analysis of a page drawn [width] by [height] pixels as BGRA
/// [bgra], whose word geometry is [geometry]. It runs in a hop and reads no
/// text. [scanned] says that [geometry] comes from the layout pass, so the
/// words' hyphens and raised marks are found from pixels. A text layer's
/// geometry already gives its hyphens, and its raised marks are words.
///
/// It gives the reflow geometry: [geometry] with the ink that no word covers
/// as extra words of their lines, and on a scanned page, with the hyphens
/// and the raised marks that the pixels show.
///
/// The steps, with the thresholds that docs/plans/pdf-word-image-reflow.md
/// tunes on the reflow fixtures. "Line height" is the height of the line at
/// hand, and "median line height" the median height of the page's lines.
/// 1. Ink. A pixel is ink when its luminance is below half of the paper's,
///    the luminance that 90 percent of the pixels do not exceed.
/// 2. Raised marks (scanned). Ink at a word's right end, after a white
///    gap, that lies wholly more than a third of the line height above the
///    baseline, is a footnote mark or a closing quote. It becomes an extra
///    word, and the word ends before it (see [_Raster.splitMark]).
/// 3. Hyphens (scanned). See [_Raster.hyphen].
/// 4. Word cover. The pixels inside each word box, grown by a fifth of the
///    line height up and down and a twentieth to the sides, are covered.
/// 5. Components. The mask of the ink that no word covers is 4 times
///    smaller in each direction, and a cell is ink when any of its pixels
///    is. Its 8-connected components keep the exact pixel box of their
///    ink. Specks smaller than a sixth of the median line height in both
///    directions are dropped.
/// 6. Uncovered ink. A component that overlaps a line's height by half its
///    own height, is no taller than 1.5 line heights and lies within one
///    line height of the line's ends becomes an extra word of that line.
///    Components of one line less than a fifth of its height apart are one
///    extra word.
/// 7. The prose line test (see [_proseLines]).
/// 8. Regions (see [_regions]).
/// 9. Body line height. The median height of the prose lines.
AnalyzedPage analyzePage(
  ({int width, int height, Uint8List bgra, PageGeometry geometry, bool scanned})
  page,
) {
  if (page.width <= 0 ||
      page.height <= 0 ||
      page.bgra.length != page.width * page.height * 4) {
    throw ArgumentError('The page raster has no pixels of its size.');
  }
  final raster = _Raster.of(page.width, page.height, page.bgra);
  final source = page.geometry;
  final lineHeight = _medianLineHeight(source, null);

  final words = _Words.of(source);
  final marks = <_Extra>[];
  if (page.scanned) {
    for (var line = 0; line < source.lineCount; line++) {
      for (
        var word = source.lineStarts[line];
        word < source.lineStarts[line + 1];
        word++
      ) {
        final mark = raster.splitMark(words, word, source, line);
        if (mark != null) marks.add(mark);
      }
      final last = source.lineStarts[line + 1] - 1;
      words.hyphens[last] = raster.hyphen(words, last, source, line);
    }
  }

  for (var line = 0; line < source.lineCount; line++) {
    final height = source.lineHeight(line);
    for (
      var word = source.lineStarts[line];
      word < source.lineStarts[line + 1];
      word++
    ) {
      raster.cover(words.boxes, word, height / 20, height / 5);
    }
  }
  for (final mark in marks) {
    raster.cover(mark.box, 0, 0, 0);
  }
  final components = raster
      .mask()
      .components(raster.scale)
      .where(
        (box) =>
            box[2] - box[0] >= lineHeight / 6 ||
            box[3] - box[1] >= lineHeight / 6,
      )
      .toList();

  final (inked, loose) = _uncoveredInk(components, source, words);
  final reflow = _reflowGeometry(source, words, [...marks, ...inked]);
  final geometry = reflow.geometry;
  final passes = _proseLines(geometry, reflow.sourceWords);
  final regions = _regions(geometry, passes, loose, lineHeight, raster);
  final proseLines = Uint8List(geometry.lineCount);
  for (var line = 0; line < geometry.lineCount; line++) {
    var prose = passes[line];
    for (
      var word = geometry.lineStarts[line];
      prose && word < geometry.lineStarts[line + 1];
      word++
    ) {
      prose = regions.wordRegions[word] < 0;
    }
    proseLines[line] = prose ? 1 : 0;
  }
  return (
    geometry: geometry,
    analysis: PageAnalysis(
      regionBoxes: regions.boxes,
      regionKinds: regions.kinds,
      wordRegions: regions.wordRegions,
      proseLines: proseLines,
      sourceWords: reflow.sourceWords,
      bodyLineHeight: _medianLineHeight(geometry, proseLines),
    ),
  );
}

/// For each word of the reflow geometry that [analysis] describes, its range
/// of the reading text: the range that [attachment] gives its source word,
/// or for an extra word an empty range at the end of the range before it.
TextAttachment reflowAttachment(
  TextAttachment attachment,
  PageAnalysis analysis,
) {
  final words = analysis.sourceWords;
  final ranges = Int32List(words.length * 2);
  var end = 0;
  for (var word = 0; word < words.length; word++) {
    final source = words[word];
    if (source >= 0) {
      ranges
        ..[word * 2] = attachment[source * 2]
        ..[word * 2 + 1] = attachment[source * 2 + 1];
      end = attachment[source * 2 + 1];
    } else {
      ranges
        ..[word * 2] = end
        ..[word * 2 + 1] = end;
    }
  }
  return ranges;
}

/// The median height of the lines of [geometry] that [lines] marks, or of
/// all its lines when [lines] is null or marks none, or
/// [PageAnalysis.defaultLineHeight] for a page without lines.
double _medianLineHeight(PageGeometry geometry, Uint8List? lines) {
  final heights = [
    for (var line = 0; line < geometry.lineCount; line++)
      if (lines == null || lines[line] != 0) geometry.lineHeight(line),
  ];
  if (heights.isNotEmpty) return _median(heights);
  if (lines != null) return _medianLineHeight(geometry, null);
  return PageAnalysis.defaultLineHeight;
}

/// The median of [values], which is not empty.
double _median(List<double> values) {
  final sorted = values.toList()..sort();
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2;
}

/// Whether box [a] of [first] and box [b] of [second] (left, top, right
/// and bottom) are less than [distance] apart, or overlap.
bool _overlap(
  List<double> first,
  int a,
  List<double> second,
  int b,
  double distance,
) =>
    first[a * 4] < second[b * 4 + 2] + distance &&
    second[b * 4] < first[a * 4 + 2] + distance &&
    first[a * 4 + 1] < second[b * 4 + 3] + distance &&
    second[b * 4 + 1] < first[a * 4 + 3] + distance;

/// Whether box [a] of [outer] holds box [b] of [inner].
bool _holds(List<double> outer, int a, List<double> inner, int b) =>
    outer[a * 4] <= inner[b * 4] + 1e-6 &&
    outer[a * 4 + 1] <= inner[b * 4 + 1] + 1e-6 &&
    outer[a * 4 + 2] >= inner[b * 4 + 2] - 1e-6 &&
    outer[a * 4 + 3] >= inner[b * 4 + 3] - 1e-6;

/// The words of a page as the analysis changes them: a word's box ends
/// before a raised mark that it split off, and a scanned word's hyphen
/// comes from pixels.
class _Words {
  _Words(this.boxes, this.ownBaselines, this.hyphens);
  factory _Words.of(PageGeometry geometry) => _Words(
    Float32List.fromList(geometry.boxes),
    Float32List.fromList(geometry.ownBaselines),
    Float32List.fromList(geometry.hyphens),
  );
  final Float32List boxes;
  final Float32List ownBaselines;
  final Float32List hyphens;

  /// Ends [word] at [right], and moves its own baseline's right end along
  /// the line between its two ends.
  void endAt(int word, double right) {
    final left = boxes[word * 4], oldRight = boxes[word * 4 + 2];
    final atLeft = ownBaselines[word * 2], atRight = ownBaselines[word * 2 + 1];
    ownBaselines[word * 2 + 1] =
        atLeft + (atRight - atLeft) * (right - left) / (oldRight - left);
    boxes[word * 4 + 2] = right;
  }
}

/// Ink that becomes an extra word of [line], placed after the word [after]
/// of the source geometry (-1 before the line's first word), with its
/// [box] in page units.
class _Extra {
  _Extra(this.line, this.after, this.box);
  final int line;
  final int after;
  final Float32List box;
}

/// A page's pixels as luminance, with its paper's luminance.
class _Raster {
  _Raster(this.width, this.height, this.luma, this.paper);

  factory _Raster.of(int width, int height, Uint8List bgra) {
    final luma = Uint8List(width * height);
    final histogram = Int32List(256);
    for (var pixel = 0, byte = 0; pixel < luma.length; pixel++, byte += 4) {
      final value =
          (bgra[byte] * 29 + bgra[byte + 1] * 150 + bgra[byte + 2] * 77) >> 8;
      luma[pixel] = value;
      histogram[value]++;
    }
    var paper = 0;
    for (var count = 0; paper < 255; paper++) {
      count += histogram[paper];
      if (count * 10 >= luma.length * 9) break;
    }
    return _Raster(width, height, luma, math.max(paper, 1));
  }

  final int width, height;
  final Uint8List luma;

  /// The luminance of the paper: 90 percent of the pixels are not lighter.
  final int paper;

  /// Pixels for one page unit.
  double get scale => width.toDouble();

  bool ink(int x, int y) => luma[y * width + x] * 2 < paper;

  /// The first and the last row of ink in column [x] between rows [top]
  /// and [bottom], or null when the column has no ink there.
  (int, int)? column(int x, int top, int bottom) {
    int? first, last;
    for (var y = top; y < bottom; y++) {
      if (!ink(x, y)) continue;
      first ??= y;
      last = y;
    }
    return first == null ? null : (first, last!);
  }

  /// The pixel box of [word] of [words]: left, top, right and bottom,
  /// inside the raster.
  (int, int, int, int) _pixels(Float32List boxes, int word) => (
    (boxes[word * 4] * scale).floor().clamp(0, width),
    (boxes[word * 4 + 1] * scale).floor().clamp(0, height),
    (boxes[word * 4 + 2] * scale).ceil().clamp(0, width),
    (boxes[word * 4 + 3] * scale).ceil().clamp(0, height),
  );

  /// The raised mark at the right end of [word] of [line], split off the
  /// word: [words] then ends the word before it. Null when the word ends in
  /// no raised mark. A mark is the ink after the word's last white gaps
  /// that lies wholly above the lowercase middle of the line: its lowest
  /// ink is more than a third of the line height above the baseline. It is
  /// at most one line height wide, and the word keeps ink before it.
  _Extra? splitMark(_Words words, int word, PageGeometry geometry, int line) {
    final (left, top, right, bottom) = _pixels(words.boxes, word);
    final lineHeight = geometry.lineHeight(line) * scale;
    var x = right - 1;
    while (x >= left && column(x, top, bottom) == null) {
      x--;
    }
    int? markLeft, markRight, markTop, markBottom, coreRight;
    while (x >= left) {
      // One run of ink columns, from the right.
      final runRight = x;
      var runTop = bottom, runBottom = top;
      while (x >= left) {
        final ink = column(x, top, bottom);
        if (ink == null) break;
        runTop = math.min(runTop, ink.$1);
        runBottom = math.max(runBottom, ink.$2);
        x--;
      }
      final baseline =
          geometry.lineBaselineAt(line, (x + 1 + runRight) / 2 / scale) * scale;
      if (runBottom >= baseline - lineHeight / 3) {
        coreRight = runRight + 1;
        break;
      }
      markLeft = x + 1;
      markRight ??= runRight + 1;
      markTop = math.min(markTop ?? runTop, runTop);
      markBottom = math.max(markBottom ?? runBottom, runBottom);
      while (x >= left && column(x, top, bottom) == null) {
        x--;
      }
    }
    if (markLeft == null ||
        coreRight == null ||
        markRight! - markLeft > lineHeight ||
        // A speck, as in step 5 of [analyzePage].
        markRight - markLeft < lineHeight / 6 &&
            markBottom! + 1 - markTop! < lineHeight / 6) {
      return null;
    }
    words.endAt(word, coreRight / scale);
    return _Extra(
      line,
      word,
      Float32List.fromList([
        markLeft / scale,
        markTop! / scale,
        markRight / scale,
        (markBottom! + 1) / scale,
      ]),
    );
  }

  /// The width of the hyphen that ends [word], the last word of [line], or
  /// 0. A hyphen is the word's last ink, within its last 0.6 line heights:
  /// ink columns that together stay within a band a sixth of the line
  /// height thick, after a white column or a column whose ink leaves that
  /// band, such as the stem of the letter that the hyphen touches. The band
  /// is at least 1.5 times as wide as it is thick and at most half a line
  /// height wide, and its middle lies between 0.1 and 0.3 line heights
  /// above the baseline: the middle of the lowercase height, below the arm
  /// of an r. Its width runs from its first ink column to the word's right
  /// edge. A word that is only a hyphen is a dash, so it has no hyphen.
  double hyphen(_Words words, int word, PageGeometry geometry, int line) {
    final (left, top, right, bottom) = _pixels(words.boxes, word);
    final lineHeight = geometry.lineHeight(line) * scale;
    final start = math.max(left, (right - 0.6 * lineHeight).floor());
    var x = right - 1;
    while (x >= start && column(x, top, bottom) == null) {
      x--;
    }
    final runRight = x;
    var runTop = bottom, runBottom = top;
    while (x >= start) {
      final ink = column(x, top, bottom);
      if (ink == null) break;
      final bandTop = math.min(runTop, ink.$1);
      final bandBottom = math.max(runBottom, ink.$2);
      if (bandBottom + 1 - bandTop > lineHeight / 6) break;
      runTop = bandTop;
      runBottom = bandBottom;
      x--;
    }
    if (x < start || runRight <= x) return 0;
    final runLeft = x + 1;
    final width = runRight + 1 - runLeft, thick = runBottom + 1 - runTop;
    final baseline =
        geometry.lineBaselineAt(line, (runLeft + runRight) / 2 / scale) * scale;
    final raised = baseline - (runTop + runBottom + 1) / 2;
    if (width < 1.5 * thick ||
        width > lineHeight / 2 ||
        raised < lineHeight / 10 ||
        raised > 0.3 * lineHeight) {
      return 0;
    }
    return words.boxes[word * 4 + 2] - runLeft / scale;
  }

  /// For each pixel: 1 when a word covers it, so that the mask leaves its
  /// ink out.
  late final covered = Uint8List(width * height);

  /// Covers the pixels of box [index] of [boxes] (in page units), grown by
  /// [sides] to the left and right and [ends] up and down.
  void cover(List<double> boxes, int index, double sides, double ends) {
    final left = ((boxes[index * 4] - sides) * scale).floor().clamp(0, width);
    final top = ((boxes[index * 4 + 1] - ends) * scale).floor().clamp(
      0,
      height,
    );
    final right = ((boxes[index * 4 + 2] + sides) * scale).ceil().clamp(
      0,
      width,
    );
    final bottom = ((boxes[index * 4 + 3] + ends) * scale).ceil().clamp(
      0,
      height,
    );
    for (var y = top; y < bottom; y++) {
      covered.fillRange(y * width + left, y * width + right, 1);
    }
  }

  /// The mask of the ink that no word covers, 4 times smaller in each
  /// direction, with the ink box of each cell.
  _Mask mask() {
    final columns = (width + 3) >> 2, rows = (height + 3) >> 2;
    final cells = Uint8List(columns * rows);
    // For each cell: the first and last ink column and row inside it.
    final extents = Uint8List(columns * rows * 4);
    for (var cell = 0; cell < cells.length; cell++) {
      extents
        ..[cell * 4] = 3
        ..[cell * 4 + 1] = 3;
    }
    for (var y = 0; y < height; y++) {
      final row = (y >> 2) * columns, dy = y & 3;
      for (var x = 0; x < width; x++) {
        final pixel = y * width + x;
        if (luma[pixel] * 2 >= paper || covered[pixel] != 0) continue;
        final cell = row + (x >> 2), dx = x & 3;
        cells[cell] = 1;
        final extent = cell * 4;
        if (dx < extents[extent]) extents[extent] = dx;
        if (dy < extents[extent + 1]) extents[extent + 1] = dy;
        if (dx > extents[extent + 2]) extents[extent + 2] = dx;
        if (dy > extents[extent + 3]) extents[extent + 3] = dy;
      }
    }
    return _Mask(columns, rows, cells, extents);
  }

  /// Whether more than 30 percent of the pixels of [box] (in page units),
  /// grown by [margin] on each side, are mid-tones: between 0.2 and 0.8 of
  /// the paper's luminance. A region's box is tight around its ink, so
  /// without the margin the soft edges of a thin rule or a folio would
  /// count as a picture's mid-tones.
  bool midTones(List<double> box, int index, double margin) {
    final left = ((box[index * 4] - margin) * scale).floor().clamp(0, width);
    final top = ((box[index * 4 + 1] - margin) * scale).floor().clamp(
      0,
      height,
    );
    final right = ((box[index * 4 + 2] + margin) * scale).ceil().clamp(
      0,
      width,
    );
    final bottom = ((box[index * 4 + 3] + margin) * scale).ceil().clamp(
      0,
      height,
    );
    final low = paper * 0.2, high = paper * 0.8;
    var count = 0;
    for (var y = top; y < bottom; y++) {
      for (var x = left; x < right; x++) {
        final value = luma[y * width + x];
        if (value >= low && value <= high) count++;
      }
    }
    return count * 10 > (right - left) * (bottom - top) * 3;
  }
}

/// The ink mask of a page: one cell for 4 by 4 pixels.
class _Mask {
  _Mask(this.columns, this.rows, this.cells, this.extents);
  final int columns, rows;
  final Uint8List cells;
  final Uint8List extents;

  /// The ink box of each 8-connected component of the mask, in page units:
  /// left, top, right and bottom. [scale] pixels make one page unit.
  List<Float32List> components(double scale) {
    final seen = Uint8List(cells.length);
    final stack = <int>[];
    final boxes = <Float32List>[];
    for (var start = 0; start < cells.length; start++) {
      if (cells[start] == 0 || seen[start] != 0) continue;
      var left = 1 << 30, top = 1 << 30, right = -1, bottom = -1;
      seen[start] = 1;
      stack.add(start);
      while (stack.isNotEmpty) {
        final cell = stack.removeLast();
        final column = cell % columns, row = cell ~/ columns;
        left = math.min(left, column * 4 + extents[cell * 4]);
        top = math.min(top, row * 4 + extents[cell * 4 + 1]);
        right = math.max(right, column * 4 + extents[cell * 4 + 2] + 1);
        bottom = math.max(bottom, row * 4 + extents[cell * 4 + 3] + 1);
        for (var dy = -1; dy <= 1; dy++) {
          final y = row + dy;
          if (y < 0 || y >= rows) continue;
          for (var dx = -1; dx <= 1; dx++) {
            final x = column + dx;
            if (x < 0 || x >= columns) continue;
            final next = y * columns + x;
            if (cells[next] == 0 || seen[next] != 0) continue;
            seen[next] = 1;
            stack.add(next);
          }
        }
      }
      boxes.add(
        Float32List.fromList([
          left / scale,
          top / scale,
          right / scale,
          bottom / scale,
        ]),
      );
    }
    return boxes;
  }
}

/// The components that lie inside a text line of [geometry], joined into
/// extra words of their lines, and the components that lie in no line.
(List<_Extra>, List<Float32List>) _uncoveredInk(
  List<Float32List> components,
  PageGeometry geometry,
  _Words words,
) {
  final byLine = <int, List<Float32List>>{};
  final loose = <Float32List>[];
  for (final box in components) {
    final tall = box[3] - box[1];
    final center = (box[0] + box[2]) / 2;
    var best = -1;
    var bestOverlap = 0.0;
    for (var line = 0; line < geometry.lineCount; line++) {
      final height = geometry.lineHeight(line);
      if (tall > 1.5 * height ||
          box[2] < geometry.lineLeft(line) - height ||
          box[0] > geometry.lineRight(line) + height) {
        continue;
      }
      final baseline = geometry.lineBaselineAt(line, center);
      final descender = geometry.lineDescender(line);
      final overlap =
          math.min(box[3], baseline + descender) -
          math.max(box[1], baseline + descender - height);
      if (overlap * 2 >= tall && overlap > bestOverlap) {
        best = line;
        bestOverlap = overlap;
      }
    }
    if (best < 0) {
      loose.add(box);
    } else {
      byLine.putIfAbsent(best, () => []).add(box);
    }
  }
  final extras = <_Extra>[];
  for (final MapEntry(key: line, value: boxes) in byLine.entries) {
    boxes.sort((a, b) => a[0].compareTo(b[0]));
    final near = geometry.lineHeight(line) / 5;
    Float32List? joined;
    void finish() {
      final box = joined!;
      var after = geometry.lineStarts[line] - 1;
      for (
        var word = geometry.lineStarts[line];
        word < geometry.lineStarts[line + 1];
        word++
      ) {
        if (words.boxes[word * 4] <= box[0]) after = word;
      }
      extras.add(_Extra(line, after, box));
    }

    for (final box in boxes) {
      if (joined != null && box[0] - joined[2] < near) {
        joined
          ..[1] = math.min(joined[1], box[1])
          ..[2] = math.max(joined[2], box[2])
          ..[3] = math.max(joined[3], box[3]);
      } else {
        if (joined != null) finish();
        joined = Float32List.fromList(box);
      }
    }
    finish();
  }
  return (extras, loose);
}

/// [geometry] with [words]' boxes, own baselines and hyphens, and with
/// [extras] as extra words of their lines, and for each word of the
/// result its source word or -1.
({PageGeometry geometry, Int32List sourceWords}) _reflowGeometry(
  PageGeometry geometry,
  _Words words,
  List<_Extra> extras,
) {
  extras.sort(
    (a, b) => a.line != b.line
        ? a.line.compareTo(b.line)
        : a.after != b.after
        ? a.after.compareTo(b.after)
        : a.box[0].compareTo(b.box[0]),
  );
  final count = geometry.wordCount + extras.length;
  final boxes = Float32List(count * 4);
  final ownBaselines = Float32List(count * 2);
  final hyphens = Float32List(count);
  final sourceWords = Int32List(count);
  final lineStarts = Int32List(geometry.lineCount + 1);
  var next = 0, extra = 0;
  void addExtra(_Extra ink) {
    boxes.setAll(next * 4, ink.box);
    ownBaselines
      ..[next * 2] = double.nan
      ..[next * 2 + 1] = double.nan;
    sourceWords[next] = -1;
    next++;
  }

  for (var line = 0; line < geometry.lineCount; line++) {
    lineStarts[line] = next;
    final first = geometry.lineStarts[line];
    while (extra < extras.length &&
        extras[extra].line == line &&
        extras[extra].after < first) {
      addExtra(extras[extra++]);
    }
    for (var word = first; word < geometry.lineStarts[line + 1]; word++) {
      boxes.setAll(next * 4, words.boxes.sublist(word * 4, word * 4 + 4));
      ownBaselines
        ..[next * 2] = words.ownBaselines[word * 2]
        ..[next * 2 + 1] = words.ownBaselines[word * 2 + 1];
      hyphens[next] = words.hyphens[word];
      sourceWords[next] = word;
      next++;
      while (extra < extras.length &&
          extras[extra].line == line &&
          extras[extra].after == word) {
        addExtra(extras[extra++]);
      }
    }
  }
  lineStarts[geometry.lineCount] = next;
  assert(next == count && extra == extras.length);
  return (
    geometry: PageGeometry(
      height: geometry.height,
      boxes: boxes,
      ownBaselines: ownBaselines,
      hyphens: hyphens,
      lineStarts: lineStarts,
      lineMetrics: geometry.lineMetrics,
      blockStarts: geometry.blockStarts,
      blockBoxes: geometry.blockBoxes,
      blockKinds: geometry.blockKinds,
      paragraphStarts: geometry.paragraphStarts,
      paragraphJustifications: geometry.paragraphJustifications,
      paragraphIndents: geometry.paragraphIndents,
    ),
    sourceWords: sourceWords,
  );
}

/// For each line of [geometry], whether it passes the prose line test.
///
/// 1. Its words share a baseline. A word is raised when its box's bottom
///    is more than a third of the line height above the baseline, and
///    lowered when its own baseline is more than a third below it. A line
///    of 10 or more words can have two such words, and a shorter line one.
/// 2. It has no wide gap that lines up with a wide gap of a neighbor line.
///    A gap between two words of the source is wide when it is more than
///    2.5 times the page's median word gap. Two wide gaps line up when
///    they overlap by at least the median word gap. A neighbor line is the
///    line before or after it, with its baseline within two line heights.
///    So the columns of a table fail, and the wide gaps of a justified line
///    or of a running header do not.
/// 3. A line of fewer than 3 words is not held to part 1. It fails when it
///    is more than 1.5 times as tall as the median line of its block.
List<bool> _proseLines(PageGeometry geometry, Int32List sourceWords) {
  final lines = geometry.lineCount;
  final boxes = geometry.boxes;
  // The gaps between the source words of each line: start and end.
  final gaps = <List<(double, double)>>[];
  for (var line = 0; line < lines; line++) {
    final ends = <(double, double)>[];
    var previous = -1;
    for (
      var word = geometry.lineStarts[line];
      word < geometry.lineStarts[line + 1];
      word++
    ) {
      if (sourceWords[word] < 0) continue;
      if (previous >= 0) ends.add((boxes[previous * 4 + 2], boxes[word * 4]));
      previous = word;
    }
    gaps.add(ends);
  }
  final widths = [
    for (final line in gaps)
      for (final (start, end) in line)
        if (end > start) end - start,
  ];
  final median = widths.isEmpty ? 0.0 : _median(widths);
  bool wide((double, double) gap) => gap.$2 - gap.$1 > 2.5 * median;
  bool linedUp(int line, (double, double) gap) {
    for (final neighbor in [line - 1, line + 1]) {
      if (neighbor < 0 || neighbor >= lines) continue;
      final pitch =
          (geometry.lineBaselineAt(neighbor, gap.$1) -
                  geometry.lineBaselineAt(line, gap.$1))
              .abs();
      if (pitch > 2 * geometry.lineHeight(line)) continue;
      for (final other in gaps[neighbor]) {
        if (wide(other) &&
            math.min(gap.$2, other.$2) - math.max(gap.$1, other.$1) >= median) {
          return true;
        }
      }
    }
    return false;
  }

  final blockHeights = [
    for (var block = 0; block < geometry.blockCount; block++)
      geometry.blockStarts[block] == geometry.blockStarts[block + 1]
          ? 0.0
          : _median([
              for (
                var line = geometry.blockStarts[block];
                line < geometry.blockStarts[block + 1];
                line++
              )
                geometry.lineHeight(line),
            ]),
  ];
  final passes = <bool>[];
  var block = 0;
  for (var line = 0; line < lines; line++) {
    while (geometry.blockStarts[block + 1] <= line) {
      block++;
    }
    passes.add(
      !gaps[line].any((gap) => wide(gap) && linedUp(line, gap)) &&
          _sharesBaseline(geometry, line, blockHeights[block]),
    );
  }
  return passes;
}

/// Whether the words of [line] of [geometry] share a baseline, as parts 1
/// and 3 of the prose line test say. [blockHeight] is the median line height
/// of the line's block.
bool _sharesBaseline(PageGeometry geometry, int line, double blockHeight) {
  final boxes = geometry.boxes;
  final first = geometry.lineStarts[line], end = geometry.lineStarts[line + 1];
  final height = geometry.lineHeight(line);
  if (end - first < 3) return height <= 1.5 * blockHeight;
  var shifted = 0;
  for (var word = first; word < end; word++) {
    final center = (boxes[word * 4] + boxes[word * 4 + 2]) / 2;
    final baseline = geometry.lineBaselineAt(line, center);
    final own =
        (geometry.ownBaselines[word * 2] +
            geometry.ownBaselines[word * 2 + 1]) /
        2;
    // A word whose own baseline is unknown (NaN) is not lowered.
    if (boxes[word * 4 + 3] < baseline - height / 3 ||
        own > baseline + height / 3) {
      shifted++;
    }
  }
  return shifted <= (end - first >= 10 ? 2 : 1);
}

/// The regions of a page with [geometry], whose lines pass the prose line
/// test as [passes] says, and whose ink that no word covers and that lies
/// in no line is [loose]. [lineHeight] is the page's median line height.
///
/// A picture or table block of the layout pass, each component of [loose],
/// and each run of neighbor lines that fail the prose line test are
/// regions. Regions less than half a median line height apart join. A word
/// that lies more than half inside a region joins it, and the region grows
/// to hold it. A region is a picture when its block is a picture, or when
/// more than 30 percent of the pixels around it are mid-tones (see
/// [_Raster.midTones], with a margin of a fifth of the median line height).
/// Otherwise it is ink.
({Float32List boxes, Uint8List kinds, Int32List wordRegions}) _regions(
  PageGeometry geometry,
  List<bool> passes,
  List<Float32List> loose,
  double lineHeight,
  _Raster raster,
) {
  final boxes = <double>[];
  final pictures = <bool>[];
  void add(List<double> box, bool picture) {
    boxes.addAll(box);
    pictures.add(picture);
  }

  for (var block = 0; block < geometry.blockCount; block++) {
    final kind = geometry.blockKind(block);
    if (kind == PageBlockKind.picture || kind == PageBlockKind.table) {
      add(
        geometry.blockBoxes.sublist(block * 4, block * 4 + 4),
        kind == PageBlockKind.picture,
      );
    }
  }
  for (final box in loose) {
    add(box, false);
  }
  // Neighbor lines that fail the prose line test are one region. A line is
  // the neighbor of the line before it when its top is within two of that
  // line's heights of its bottom, so two columns or two tables apart on
  // the page stay apart.
  List<double>? failing;
  for (var line = 0; line < geometry.lineCount; line++) {
    if (passes[line]) {
      if (failing != null) add(failing, false);
      failing = null;
      continue;
    }
    final box = [double.infinity, double.infinity, 0.0, 0.0];
    for (
      var word = geometry.lineStarts[line];
      word < geometry.lineStarts[line + 1];
      word++
    ) {
      box[0] = math.min(box[0], geometry.boxes[word * 4]);
      box[1] = math.min(box[1], geometry.boxes[word * 4 + 1]);
      box[2] = math.max(box[2], geometry.boxes[word * 4 + 2]);
      box[3] = math.max(box[3], geometry.boxes[word * 4 + 3]);
    }
    if (failing != null &&
        box[1] - failing[3] <= 2 * geometry.lineHeight(line - 1)) {
      failing
        ..[0] = math.min(failing[0], box[0])
        ..[1] = math.min(failing[1], box[1])
        ..[2] = math.max(failing[2], box[2])
        ..[3] = math.max(failing[3], box[3]);
    } else {
      if (failing != null) add(failing, false);
      failing = box;
    }
  }
  if (failing != null) add(failing, false);

  final near = lineHeight / 2;
  final wordRegions = Int32List(geometry.wordCount);
  var changed = true;
  while (changed) {
    changed = false;
    // Join regions that are less than half a body line height apart.
    for (var region = 0; region < pictures.length; region++) {
      for (var other = region + 1; other < pictures.length; other++) {
        if (!_overlap(boxes, region, boxes, other, near)) continue;
        boxes
          ..[region * 4] = math.min(boxes[region * 4], boxes[other * 4])
          ..[region * 4 + 1] = math.min(
            boxes[region * 4 + 1],
            boxes[other * 4 + 1],
          )
          ..[region * 4 + 2] = math.max(
            boxes[region * 4 + 2],
            boxes[other * 4 + 2],
          )
          ..[region * 4 + 3] = math.max(
            boxes[region * 4 + 3],
            boxes[other * 4 + 3],
          );
        pictures[region] = pictures[region] || pictures[other];
        boxes.removeRange(other * 4, other * 4 + 4);
        pictures.removeAt(other);
        other = region;
        changed = true;
      }
    }
    // A word more than half inside a region joins it, and the region grows
    // to hold it.
    for (var word = 0; word < geometry.wordCount; word++) {
      final left = geometry.boxes[word * 4], top = geometry.boxes[word * 4 + 1];
      final right = geometry.boxes[word * 4 + 2];
      final bottom = geometry.boxes[word * 4 + 3];
      wordRegions[word] = -1;
      for (var region = 0; region < pictures.length; region++) {
        final width =
            math.min(right, boxes[region * 4 + 2]) -
            math.max(left, boxes[region * 4]);
        final height =
            math.min(bottom, boxes[region * 4 + 3]) -
            math.max(top, boxes[region * 4 + 1]);
        if (width <= 0 ||
            height <= 0 ||
            width * height * 2 <= (right - left) * (bottom - top)) {
          continue;
        }
        wordRegions[word] = region;
        if (!_holds(boxes, region, geometry.boxes, word)) {
          boxes
            ..[region * 4] = math.min(boxes[region * 4], left)
            ..[region * 4 + 1] = math.min(boxes[region * 4 + 1], top)
            ..[region * 4 + 2] = math.max(boxes[region * 4 + 2], right)
            ..[region * 4 + 3] = math.max(boxes[region * 4 + 3], bottom);
          changed = true;
        }
        break;
      }
    }
  }
  final kinds = Uint8List(pictures.length);
  for (var region = 0; region < pictures.length; region++) {
    final picture =
        pictures[region] || raster.midTones(boxes, region, lineHeight / 5);
    kinds[region] = (picture ? RegionKind.picture : RegionKind.ink).index;
  }
  return (
    boxes: Float32List.fromList(boxes),
    kinds: kinds,
    wordRegions: wordRegions,
  );
}
