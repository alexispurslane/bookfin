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

/// One card of the scrub deck: its own page once that page is drawn, and
/// blank until then.
@immutable
class DeckCard {
  const DeckCard({required this.page});
  const DeckCard.blank() : page = null;

  /// The card's own drawn page, or null while the card is blank.
  final PagePreview? page;

  @override
  bool operator ==(Object other) =>
      other is DeckCard && identical(other.page, page);

  @override
  int get hashCode => identityHashCode(page);
}

/// The page images of the scrub deck while the person drags the reader's
/// scrub bar, and the deck that shows them.
///
/// One drag owns its drawn pages. It draws one page at a time: first the
/// page under the thumb, then the next page, then the previous page. A place
/// that the thumb leaves before its turn is never drawn, so a fast drag
/// draws only where the thumb rests. A drawing stops early when the deck no
/// longer needs its page: the thumb is in another part of the book, and the
/// page is not a neighbor of the front card. A settling deck needs only its
/// target and stops any other drawing. A page that is drawn for a place that
/// the thumb already left still joins the drag's pages.
///
/// Each card shows its own page once that page is drawn, and is blank until
/// then. Before the front page is drawn, the places of its neighbors are not
/// known, so a blank card stands on each side of it, except past an end of
/// the book.
///
/// Invariants, which [checkInvariants] checks:
/// - The deck shows exactly while a drag runs.
/// - A drag keeps at most [capacity] drawn pages, and none of them is freed.
/// - Without a drag there are no drawn pages, no failed places and no
///   target.
class PagePreviews {
  PagePreviews({required this.draw, required this.locate, this.capacity = 7})
    : assert(capacity >= 3, 'A deck shows three pages.');

  /// Draws the page that holds a place, a given number of pixels wide. When
  /// `abandon` completes before the page is drawn, the drawing can stop
  /// early and fail.
  final Future<PagePreview> Function(
    BookPlace place,
    double width,
    Future<void> abandon,
  )
  draw;

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

  /// How many pixels wide each page of the drag is drawn.
  double _width = 0;

  /// Whether the drag ended and the deck closes onto its target.
  bool _settling = false;

  /// The place whose page is being drawn, if any, for this drag or an
  /// earlier one. The next drawing waits for it.
  BookPlace? _drawing;

  /// Stops the drawing of [_drawing].
  Completer<void>? _abandon;

  /// The drawn pages of the drag.
  final _pages = <PagePreview>[];

  /// The places of the drag that could not be drawn.
  final _failed = <BookPlace>{};

  /// Opens the deck at [target], where a drag started. Each page is drawn
  /// [width] pixels wide.
  void start(BookTarget target, {required double width}) {
    close();
    _target = (part: target.part, progress: target.progress);
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
    _settling = false;
    _stopDrawing();
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

  /// The places that the deck still needs drawn, in order: the target, or
  /// once its page is drawn, the next page and then the previous page. A
  /// settling deck needs only its target.
  List<BookPlace> _needed() {
    final front = _holding(_target);
    final places = front == null
        ? [_target]
        : _settling
        ? const <BookPlace?>[]
        : [front.next, front.previous];
    return [
      for (final place in places)
        if (place != null && _holding(place) == null) place,
    ];
  }

  /// Publishes the deck, stops a drawing that the deck no longer needs, and
  /// draws the next page that it needs.
  void _update() {
    _publish();
    final target = _target;
    if (target == null) return;
    final needed = _needed();
    if (_drawing case final drawing?) {
      // A settling deck stops every other drawing, so the reader can move
      // to its place sooner.
      if (!needed.contains(drawing) &&
          (_settling || drawing.part != target.part)) {
        _stopDrawing();
      }
      return;
    }
    final place = needed.where((place) => !_failed.contains(place)).firstOrNull;
    if (place == null) return;
    final drag = _drag;
    final abandon = _abandon = Completer<void>();
    _drawing = place;
    unawaited(
      draw(place, _width, abandon.future)
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
              if (drag == _drag && !abandon.isCompleted) _failed.add(place);
            },
          )
          .whenComplete(() {
            // Only one page is drawn at a time, so this drawing is the one
            // in progress, even when its drag ended.
            _drawing = null;
            _abandon = null;
            _update();
          }),
    );
  }

  /// Abandons the drawing in progress. The deck draws its next page when
  /// that drawing ends.
  void _stopDrawing() {
    final abandon = _abandon;
    if (abandon != null && !abandon.isCompleted) abandon.complete();
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
    final own = _holding(target);
    // A neighbor's place is known once the front page is drawn. Before then
    // a blank card stands for it, except past an end of the book.
    DeckCard? neighbor(BookPlace? place, bool end) => own == null
        ? (end ? null : const DeckCard.blank())
        : place == null
        ? null
        : DeckCard(page: _holding(place));
    final at = locate(target);
    _deck.value = DeckView(
      front: DeckCard(page: own),
      previous: neighbor(own?.previous, at <= 0),
      next: neighbor(own?.next, at >= 1),
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
        (!running && (_pages.isNotEmpty || _failed.isNotEmpty))) {
      throw StateError(
        'The scrub deck must show the pages of one running drag.',
      );
    }
  }
}
