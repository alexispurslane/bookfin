import 'package:flutter/foundation.dart';

/// Where the true pages of one part start: the number of the part's visible
/// characters before each page, in order from the part's first page, and
/// the part's number of visible characters. A page that shows no text, such
/// as a lone image, starts where the page after it starts.
typedef VisibleStarts = ({List<int> starts, int length});

/// The true pages of one part of the open book in one page settings value:
/// how many there are, and where they start when a main run measured them.
/// A part that a kept page map seeded knows its count only (t5-q0hs keeps
/// the visible starts in the map too).
typedef PartPages = ({int count, VisibleStarts? visible});

/// The whole-book page index: the true pages of every part of the open book
/// in one page settings value. A part whose pages are not known yet is null.
/// The page label and the scrub bar both read it, so that they agree on
/// every page's number.
///
/// Invariants, which the constructor asserts: each part has a page. Visible
/// starts, where known, are one for each page, begin at 0, never decrease,
/// and stay within the part's length.
@immutable
class BookPages {
  BookPages(List<PartPages?> parts) : parts = List.unmodifiable(parts) {
    assert(
      this.parts.every((part) => part == null || _holds(part)),
      'Each part must have a page, and its visible starts must start at 0 '
      'and never go back.',
    );
  }

  final List<PartPages?> parts;

  static bool _holds(PartPages part) {
    if (part.count < 1) return false;
    final visible = part.visible;
    if (visible == null) return true;
    final starts = visible.starts;
    if (starts.length != part.count ||
        starts.first != 0 ||
        starts.last > visible.length) {
      return false;
    }
    for (var at = 1; at < starts.length; at++) {
      if (starts[at] < starts[at - 1]) return false;
    }
    return true;
  }

  /// The number of pages before each part, and the book's page count at the
  /// end, once every part's pages are known.
  late final List<int>? _before = () {
    final before = [0];
    for (final part in parts) {
      if (part == null) return null;
      before.add(before.last + part.count);
    }
    return before;
  }();

  /// Whether every part's pages are known.
  bool get complete => _before != null;

  /// The number of pages of the whole book, or null while some part's pages
  /// are not known.
  int? get count => _before?.last;

  /// The number among the whole book's pages, from 1, of the page [index]
  /// of part [part], from 0, or null while some part's pages are not known.
  int? numberOf(int part, int index) {
    final before = _before;
    return before == null ? null : before[part] + index + 1;
  }
}
