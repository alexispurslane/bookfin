// The book crop: one box for the left-hand pages and one for the right-hand
// pages of a PDF, which the Original view shows of each page (tb-lnak). See
// docs/plans/pdf-word-image-reflow.md, "The book crop".
import 'dart:math' as math;
import 'dart:typed_data';

import 'running_lines.dart';

/// A box on a page in page units: left, top, right and bottom.
typedef PageBox = ({double left, double top, double right, double bottom});

/// What the book profile and a page's crop need of one analyzed page: its
/// edge lines and edge regions, which can be running lines and running
/// regions, and the box around the rest of its content. It is small, so the survey keeps it on disk for every page.
class SurveyedPage {
  SurveyedPage({required this.edges, required this.height, this.core});

  /// The page's number, body line height, body flag, edge lines and edge
  /// regions.
  final PageEdges edges;

  /// The page's height in page units.
  final double height;

  /// The box around the page's content without its edge lines and edge
  /// regions, as `PageAnalysis.contentBox` counts content, or null when
  /// nothing else is there.
  final PageBox? core;

  int get sourcePage => edges.sourcePage;

  /// Whether the page is a body page (see [PageEdges]). Only body pages
  /// shape the side boxes.
  bool get body => edges.body;
}

/// What the book crop needs of [page] (see [SurveyedPage]).
// NOTE: This reads the page's lines and regions twice. It takes
// microseconds, far less than a hop to another isolate.
SurveyedPage surveyPage(AnalyzedSourcePage page) {
  final edges = pageEdges(page);
  // The content rule lives in PageAnalysis.contentBox alone: the core is the
  // content box with every edge line and edge region marked as running.
  final lines = Uint8List(page.geometry.lineCount);
  for (final edge in edges.edges) {
    lines[edge.line] = 1;
  }
  final regions = Uint8List(page.analysis.regionCount);
  for (final region in edges.regions) {
    regions[region.region] = 1;
  }
  final core = page.analysis
      .withRunningLines(lines, regions: regions)
      .contentBox(page.geometry);
  return SurveyedPage(
    edges: edges,
    height: page.geometry.height,
    core: core.every((value) => value == 0)
        ? null
        : (left: core[0], top: core[1], right: core[2], bottom: core[3]),
  );
}

/// What the survey learns from a sample of a book's pages, frozen once: the
/// templates of its running lines, and one box for each side.
class BookProfile {
  BookProfile({required this.templates, required this.boxes})
    : assert(boxes.length == 2, 'A book has two sides.');

  final RunningTemplates templates;

  /// The box of each side, by the parity of the source page number: 0 for
  /// even (left-hand) pages and 1 for odd (right-hand) pages. Null for a
  /// side without body pages.
  final List<PageBox?> boxes;
}

/// The book profile of a book whose sample is [pages]. It runs in a hop.
///
/// For each side, the box runs from the 5th percentile of the left and top
/// content edges of the side's body pages to the 95th percentile of their
/// right and bottom edges, padded by half the book's body line height. The
/// book's body line height is the median of its body pages' body line
/// heights. Pages that are not body pages, such as a cover, a plate or a
/// blank page, do not count.
BookProfile bookProfile(List<SurveyedPage> pages) {
  final templates = runningTemplatesOf([for (final page in pages) page.edges]);
  final body = pages.where((page) => page.body).toList();
  final padding = body.isEmpty
      ? 0.0
      : _median([for (final page in body) page.edges.bodyLineHeight]) / 2;
  PageBox? box(int side) {
    final contents = [
      for (final page in body)
        if (page.sourcePage % 2 == side) ?contentOf(page, templates),
    ];
    if (contents.isEmpty) return null;
    final left = _lowPercentile([for (final box in contents) box.left]);
    final top = _lowPercentile([for (final box in contents) box.top]);
    final right = _highPercentile([for (final box in contents) box.right]);
    final bottom = _highPercentile([for (final box in contents) box.bottom]);
    if (left >= right || top >= bottom) return null;
    return (
      left: math.max(0, left - padding),
      top: math.max(0, top - padding),
      right: math.min(1, right + padding),
      bottom: bottom + padding,
    );
  }

  return BookProfile(templates: templates, boxes: [box(0), box(1)]);
}

/// The content box of [page] in a book with the running [templates]: its
/// core, and its edge lines and edge regions that are not running. Null for
/// a page without content.
PageBox? contentOf(SurveyedPage page, RunningTemplates templates) {
  var content = page.core;
  for (final edge in page.edges.edges) {
    if (!templates.matches(page.sourcePage, edge)) {
      content = _union(content, edge.box);
    }
  }
  for (final region in page.edges.regions) {
    if (!templates.matchesRegion(page.sourcePage, region)) {
      content = _union(content, region.box);
    }
  }
  return content;
}

/// The crop of [page] in a book with [profile]: the part of the page that
/// the Original view shows.
///
/// - A page whose content its side's box holds shows that box. A blank page
///   does too.
/// - A page whose content only the other side's box holds shows that box. An
///   inserted plate can flip the parity of the pages after it.
/// - Any other page shows the union of its side's box and its content box,
///   so no content is ever cut.
/// - Without a box for either side, a page shows its content box padded as
///   a side box would be, and a blank page shows the whole page.
///
/// The crop lies inside the page.
PageBox cropOf(SurveyedPage page, BookProfile profile) {
  final side = page.sourcePage % 2;
  final own = profile.boxes[side], other = profile.boxes[1 - side];
  final content = contentOf(page, profile.templates);
  final whole = (left: 0.0, top: 0.0, right: 1.0, bottom: page.height);
  final PageBox crop;
  if (content == null) {
    crop = own ?? other ?? whole;
  } else if (own != null && _holds(own, content)) {
    crop = own;
  } else if (other != null && _holds(other, content)) {
    crop = other;
  } else if (own ?? other case final box?) {
    crop = _union(box, content);
  } else {
    final padding = page.edges.bodyLineHeight / 2;
    crop = (
      left: content.left - padding,
      top: content.top - padding,
      right: content.right + padding,
      bottom: content.bottom + padding,
    );
  }
  return (
    left: math.max(0, crop.left),
    top: math.max(0, crop.top),
    right: math.min(1, crop.right),
    bottom: math.min(page.height, crop.bottom),
  );
}

/// Whether [outer] holds [inner].
bool _holds(PageBox outer, PageBox inner) =>
    outer.left <= inner.left &&
    outer.top <= inner.top &&
    outer.right >= inner.right &&
    outer.bottom >= inner.bottom;

PageBox _union(PageBox? a, PageBox b) => a == null
    ? b
    : (
        left: math.min(a.left, b.left),
        top: math.min(a.top, b.top),
        right: math.max(a.right, b.right),
        bottom: math.max(a.bottom, b.bottom),
      );

/// The 5th percentile of [values], which is not empty. Its index rounds
/// toward the median, so a sample of fewer than 21 pages still leaves out
/// its lowest value, such as the left edge of one wide table.
double _lowPercentile(List<double> values) {
  final sorted = values.toList()..sort();
  return sorted[(0.05 * (sorted.length - 1)).ceil()];
}

/// The 95th percentile of [values], which is not empty, with its index
/// rounded toward the median (see [_lowPercentile]).
double _highPercentile(List<double> values) {
  final sorted = values.toList()..sort();
  return sorted[(0.95 * (sorted.length - 1)).floor()];
}

/// The median of [values], which is not empty.
double _median(List<double> values) {
  final sorted = values.toList()..sort();
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2;
}
