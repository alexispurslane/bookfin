import 'dart:async';

import 'package:flutter/foundation.dart';

import 'book_map.dart';
import 'document.dart';

/// What the scrub deck shows: the card in front and the cards behind it.
@immutable
class DeckView {
  const DeckView({
    required this.front,
    this.previous,
    this.next,
    this.settling = false,
  });

  /// The card of the page under the thumb.
  final DeckCard front;

  /// The cards of the pages before and after the front page, or null at the
  /// start or the end of the book.
  final DeckCard? previous;
  final DeckCard? next;

  /// Whether the drag ended. The deck then closes onto the front card while
  /// the reader moves to its page.
  final bool settling;

  @override
  bool operator ==(Object other) =>
      other is DeckView &&
      other.front == front &&
      other.previous == previous &&
      other.next == next &&
      other.settling == settling;

  @override
  int get hashCode => Object.hash(front, previous, next, settling);
}

/// One card of the scrub deck.
@immutable
class DeckCard {
  const DeckCard({required this.page, required this.exact});

  /// The drawn page that the card shows, or null for the page that the
  /// reader shows, before any page of the drag is drawn.
  final PagePreview? page;

  /// Whether [page] is the card's own page. Otherwise it is the finished
  /// page nearest to the card's place, and the card shows it dimmed.
  final bool exact;

  @override
  bool operator ==(Object other) =>
      other is DeckCard && identical(other.page, page) && other.exact == exact;

  @override
  int get hashCode => Object.hash(identityHashCode(page), exact);
}

/// The page images of the scrub deck while the person drags the reader's
/// scrub bar, and the deck that shows them.
///
/// One drag owns its drawn pages. It draws one page at a time: first the
/// page under the thumb, then the next page, then the previous page. A place
/// that the thumb leaves before its turn is never drawn, so a fast drag
/// draws only where the thumb rests. A page that is drawn for a place that
/// the thumb already left still joins the drag's pages.
///
/// Each card shows its own page once that page is drawn. Until then it shows
/// the drawn page nearest to its place, dimmed. Before any page is drawn,
/// the front card shows the page that the reader shows, and no card is
/// behind it. A card is never blank.
///
/// Invariants, which [checkInvariants] checks:
/// - The deck shows exactly while a drag runs.
/// - A drag keeps at most [capacity] drawn pages, and none of them is freed.
/// - Without a drag there are no drawn pages, no failed places and no
///   target.
class PagePreviews {
  PagePreviews({required this.draw, required this.locate, this.capacity = 7})
    : assert(capacity >= 3, 'A deck shows three pages.');

  /// Draws the page that holds a place, a given number of pixels wide.
  final Future<PagePreview> Function(BookPlace place, double width) draw;

  /// Where a place sits in the whole book, from 0 at its start to 1 at its
  /// end.
  final double Function(BookPlace place) locate;

  /// How many drawn pages one drag keeps.
  final int capacity;

  final _deck = ValueNotifier<DeckView?>(null);

  /// The deck, or null while no drag runs.
  ValueListenable<DeckView?> get deck => _deck;

  /// The number of the running drag. A drawing for an earlier drag is freed
  /// when it arrives.
  int _drag = 0;

  /// The place under the thumb, or null while no drag runs.
  BookPlace? _target;

  /// The place where the drag started, which the shown page holds.
  BookPlace? _origin;

  /// How many pixels wide each page of the drag is drawn.
  double _width = 0;

  /// Whether the drag ended and the deck closes onto its target.
  bool _settling = false;

  /// Whether a page is being drawn.
  bool _drawing = false;

  /// The drawn pages of the drag.
  final _pages = <PagePreview>[];

  /// The places of the drag that could not be drawn.
  final _failed = <BookPlace>{};

  /// Opens the deck at [target], where a drag started. Each page is drawn
  /// [width] pixels wide.
  void start(BookTarget target, {required double width}) {
    close();
    _origin = _target = (part: target.part, progress: target.progress);
    _width = width;
    _update();
  }

  /// Moves the front of the deck to [target], a place that the drag passes.
  void aim(BookTarget target) {
    if (_target == null) return;
    _target = (part: target.part, progress: target.progress);
    _update();
  }

  /// Closes the deck onto [target], where the drag ended, while [landing]
  /// moves the reader there. The deck goes, and its pages are freed, when
  /// [landing] completes. The returned future completes then.
  Future<void> settle(BookTarget target, Future<void> landing) async {
    final drag = _drag;
    aim(target);
    _settling = _target != null;
    _update();
    try {
      await landing;
    } finally {
      if (drag == _drag) close();
    }
  }

  /// Ends any drag at once and frees its pages, as when the book closes.
  void close() {
    _drag++;
    _target = null;
    _origin = null;
    _settling = false;
    _failed.clear();
    // The deck lets go of the pages before they are freed.
    _deck.value = null;
    for (final page in _pages) {
      page.image.dispose();
    }
    _pages.clear();
  }

  void dispose() {
    close();
    _deck.dispose();
  }

  /// The drawn page that holds [place], if any.
  PagePreview? _holding(BookPlace? place) => place == null
      ? null
      : _pages.where((page) => page.holds(place)).firstOrNull;

  /// Where the middle of [page] sits in the whole book.
  double _middle(PagePreview page) =>
      locate((part: page.part, progress: (page.start + page.end) / 2));

  /// The drawn page nearest to [at], a place in the whole book, among the
  /// pages that [side] admits.
  PagePreview? _nearest(double at, [bool Function(double middle)? side]) {
    PagePreview? best;
    var distance = double.infinity;
    for (final page in _pages) {
      final middle = _middle(page);
      if (side != null && !side(middle)) continue;
      if ((middle - at).abs() < distance) {
        distance = (middle - at).abs();
        best = page;
      }
    }
    return best;
  }

  /// The next place to draw: the target, then the next page, then the
  /// previous page. A settling deck needs only its target.
  BookPlace? _wanted() {
    final front = _holding(_target);
    final places = front == null
        ? [_target]
        : _settling
        ? const <BookPlace?>[]
        : [front.next, front.previous];
    for (final place in places) {
      if (place != null &&
          _holding(place) == null &&
          !_failed.contains(place)) {
        return place;
      }
    }
    return null;
  }

  /// Publishes the deck and draws the next page that it needs.
  void _update() {
    _publish();
    if (_drawing || _target == null) return;
    final place = _wanted();
    if (place == null) return;
    final drag = _drag;
    _drawing = true;
    unawaited(
      draw(place, _width)
          .then(
            (page) {
              if (drag != _drag) {
                page.image.dispose();
                return;
              }
              _pages.add(page);
              // The trim keeps what the deck shows with the new page.
              _publish();
              _trim();
            },
            onError: (Object _) {
              if (drag == _drag) _failed.add(place);
            },
          )
          .whenComplete(() {
            _drawing = false;
            if (drag == _drag) _update();
          }),
    );
  }

  /// Frees the drawn pages farthest from the target, beyond [capacity],
  /// except those that the deck shows.
  void _trim() {
    if (_pages.length <= capacity) return;
    final at = locate(_target!);
    final shown = {
      for (final card in [
        _deck.value?.front,
        _deck.value?.previous,
        _deck.value?.next,
      ])
        card?.page,
    };
    final candidates = _pages.where((page) => !shown.contains(page)).toList()
      ..sort(
        (a, b) => (_middle(b) - at).abs().compareTo((_middle(a) - at).abs()),
      );
    for (final page in candidates.take(_pages.length - capacity)) {
      _pages.remove(page);
      page.image.dispose();
    }
  }

  void _publish() {
    final target = _target;
    if (target == null) {
      _deck.value = null;
      return;
    }
    final at = locate(target);
    final own = _holding(target);
    final DeckCard front;
    if (own != null) {
      front = DeckCard(page: own, exact: true);
    } else if (_nearest(at) case final near?) {
      front = DeckCard(page: near, exact: false);
    } else {
      front = DeckCard(page: null, exact: target == _origin);
    }
    // A neighbor's place is known once the front page is drawn. Before then
    // it is somewhere on its side of the target.
    DeckCard? neighbor(
      BookPlace? place,
      bool Function(double middle) side,
      bool end,
    ) {
      if (own != null && place == null || own == null && end) return null;
      if (_holding(place) case final page?) {
        return DeckCard(page: page, exact: true);
      }
      // The shown page stands in for the front card only, so a neighbor
      // waits for a drawn page.
      final near = _nearest(at, side) ?? front.page;
      return near == null ? null : DeckCard(page: near, exact: false);
    }

    _deck.value = DeckView(
      front: front,
      previous: neighbor(own?.previous, (middle) => middle < at, at <= 0),
      next: neighbor(own?.next, (middle) => middle > at, at >= 1),
      settling: _settling,
    );
  }

  /// Checks the invariants in the class comment. It throws a [StateError]
  /// when one does not hold.
  void checkInvariants() {
    final running = _target != null;
    if ((_deck.value != null) != running ||
        _pages.length > capacity ||
        _pages.any((page) => page.image.debugDisposed) ||
        (!running &&
            (_pages.isNotEmpty || _failed.isNotEmpty || _origin != null))) {
      throw StateError(
        'The scrub deck must show the pages of one running drag.',
      );
    }
  }
}
