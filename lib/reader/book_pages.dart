import 'package:flutter/foundation.dart';

/// The true pages of one part of the open book in one page settings value:
/// where each page starts, as the number of the part's visible characters
/// before the page, in order from the part's first page, and the part's
/// number of visible characters. A page that shows no text, such as a lone
/// image, starts where the page after it starts.
typedef PartPages = ({List<int> starts, int length});

/// The whole-book page index: the true pages of every part of the open book
/// in one page settings value. A part whose pages are not known yet is null.
/// The page label and the scrub bar both read it, so that they agree on
/// every page's number.
///
/// Invariants, which the constructor asserts: each part has a page, its
/// starts begin at 0, never decrease, and stay within its length.
@immutable
class BookPages {
  BookPages(List<PartPages?> parts) : parts = List.unmodifiable(parts) {
    assert(
      this.parts.every(
        (part) =>
            part == null ||
            (part.starts.isNotEmpty &&
                part.starts.first == 0 &&
                part.starts.last <= part.length &&
                [
                  for (var at = 1; at < part.starts.length; at++)
                    part.starts[at] >= part.starts[at - 1],
                ].every((rising) => rising)),
      ),
      'The pages of a part must start at 0 and never go back.',
    );
  }

  final List<PartPages?> parts;

  /// The number of pages before each part, and the book's page count at the
  /// end, once every part's pages are known.
  late final List<int>? _before = () {
    final before = [0];
    for (final part in parts) {
      if (part == null) return null;
      before.add(before.last + part.starts.length);
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
