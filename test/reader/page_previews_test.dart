import 'dart:async';
import 'dart:ui' as ui;

import 'package:bookfin/reader/book_map.dart';
import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/page_previews.dart';
import 'package:flutter_test/flutter_test.dart';

/// A small image that stands for a drawn page.
ui.Image picture() {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder);
  return recorder.endRecording().toImageSync(2, 2);
}

/// A made-up book of ten parts, each of ten pages of equal length.
const parts = 10;

/// The first place of page [page] of part [part].
BookPlace pageStart(int part, int page) => (part: part, progress: page / 10);

/// The page of the made-up book that holds [place], as a viewport draws it.
PagePreview pageAt(BookPlace place) {
  final page = (place.progress * 10).floor().clamp(0, 9);
  final (part, start) = (place.part, page / 10);
  return PagePreview(
    part: part,
    start: start,
    end: start + .099,
    image: picture(),
    previous: page > 0
        ? pageStart(part, page - 1)
        : part > 0
        ? pageStart(part - 1, 9)
        : null,
    next: page < 9
        ? pageStart(part, page + 1)
        : part + 1 < parts
        ? pageStart(part + 1, 0)
        : null,
  );
}

/// The place [place] as the scrub bar reports it.
BookTarget target(BookPlace place) => BookTarget(
  fraction: (place.part + place.progress) / parts,
  part: place.part,
  progress: place.progress,
);

/// A viewport that draws each page when the test says so.
class Drawings {
  /// Each place that the previews asked to draw, in order.
  final asked = <BookPlace>[];
  final _pending = <BookPlace, Completer<PagePreview>>{};

  /// Every page drawn so far.
  final drawn = <PagePreview>[];

  /// Each place whose drawing the previews abandoned, in order.
  final abandoned = <BookPlace>[];

  /// Whether a drawing stops when the previews abandon it. A PDF page draws
  /// fast and does not stop.
  var stops = true;

  Future<PagePreview> draw(
    BookPlace place,
    double width,
    Future<void> abandon,
  ) {
    asked.add(place);
    final drawing = _pending[place] = Completer<PagePreview>();
    // Like a viewport, the drawing stops at its next step.
    unawaited(
      abandon.then((_) {
        if (!stops || drawing.isCompleted) return;
        abandoned.add(place);
        _pending.remove(place);
        drawing.completeError(StateError('Abandoned.'));
      }),
    );
    return drawing.future;
  }

  /// Whether the drawing of [place] still runs.
  bool drawing(BookPlace place) => _pending.containsKey(place);

  /// Finishes the drawing of [place], and lets the previews take it.
  Future<PagePreview> finish(BookPlace place) async {
    final page = pageAt(place);
    drawn.add(page);
    _pending.remove(place)!.complete(page);
    await pumpEventQueue();
    return page;
  }

  /// Finishes each drawing until the previews ask for no more.
  Future<void> finishAll() async {
    while (_pending.isNotEmpty) {
      await finish(_pending.keys.first);
    }
  }

  /// Fails the drawing of [place].
  Future<void> fail(BookPlace place) async {
    _pending.remove(place)!.completeError(StateError('Not drawn.'));
    await pumpEventQueue();
  }
}

void main() {
  late Drawings drawings;
  late PagePreviews previews;
  DeckView view() => previews.deck.value!;

  setUp(() {
    drawings = Drawings();
    previews = PagePreviews(
      draw: drawings.draw,
      locate: (place) => (place.part + place.progress) / parts,
    );
  });
  tearDown(() {
    previews.close();
    previews.dispose();
  });

  test('a drag opens the deck with blank cards and draws the page under '
      'the thumb', () {
    expect(previews.deck.value, isNull);
    final place = (part: 2, progress: .35);
    previews.start(target(place), width: 300);
    expect(view().front, const DeckCard.blank());
    expect(view().previous, const DeckCard.blank());
    expect(view().next, const DeckCard.blank());
    expect(drawings.asked, [place]);
  });

  test(
    'the front card shows the page under the thumb once it is drawn',
    () async {
      final place = (part: 2, progress: .35);
      previews.start(target(place), width: 300);
      final page = await drawings.finish(place);
      expect(view().front, DeckCard(page: page));
    },
  );

  test('the front card follows the thumb', () async {
    final first = (part: 2, progress: .35);
    final second = (part: 6, progress: .52);
    previews.start(target(first), width: 300);
    await drawings.finish(first);
    previews.aim(target(second));
    await pumpEventQueue();
    expect(drawings.asked.last, second);
    final page = await drawings.finish(second);
    expect(view().front, DeckCard(page: page));
  });

  test(
    'the cards behind the front are the previous and the next page',
    () async {
      final place = (part: 2, progress: .35);
      previews.start(target(place), width: 300);
      final front = await drawings.finish(place);
      expect(
        drawings.asked.last,
        front.next,
        reason: 'The next page comes first.',
      );
      final next = await drawings.finish(front.next!);
      expect(drawings.asked.last, front.previous);
      final previous = await drawings.finish(front.previous!);
      expect(view().previous, DeckCard(page: previous));
      expect(view().next, DeckCard(page: next));
      expect(previous.holds(pageStart(2, 2)), isTrue);
      expect(next.holds(pageStart(2, 4)), isTrue);
    },
  );

  test('the first page of the book has no card before it', () async {
    final place = (part: 0, progress: .02);
    previews.start(target(place), width: 300);
    final front = await drawings.finish(place);
    await drawings.finish(front.next!);
    expect(view().previous, isNull);
    expect(drawings.asked, hasLength(2));
  });

  test('a card stays blank until its own page is drawn, even when pages '
      'near it are drawn', () async {
    previews.start(target((part: 2, progress: .15)), width: 300);
    await drawings.finishAll();
    previews.aim(target((part: 2, progress: .75)));
    await drawings.finishAll();
    // Pages 0 to 2 and 6 to 8 of part 2 are drawn.
    previews.aim(target((part: 2, progress: .5)));
    expect(drawings.asked.last, (part: 2, progress: .5));
    expect(view().front, const DeckCard.blank());
    expect(view().previous, const DeckCard.blank());
    expect(view().next, const DeckCard.blank());
    final page = await drawings.finish((part: 2, progress: .5));
    expect(view().front, DeckCard(page: page));
    expect(
      view().next!.page!.holds((part: 2, progress: .6)),
      isTrue,
      reason: 'Page 6 is drawn.',
    );
    expect(view().previous, const DeckCard.blank());
  });

  test('before its page is drawn, the front card has a blank card on each '
      'side, except past an end of the book', () {
    previews.start(target((part: 0, progress: 0)), width: 300);
    expect(view().previous, isNull);
    expect(view().next, const DeckCard.blank());
    previews.aim(target((part: 9, progress: 1)));
    expect(view().previous, const DeckCard.blank());
    expect(view().next, isNull);
  });

  test('a place that the thumb left before its turn is never drawn', () async {
    final first = (part: 1, progress: .1);
    final passed = (part: 4, progress: .1);
    final last = (part: 8, progress: .1);
    previews.start(target(first), width: 300);
    previews.aim(target(passed));
    previews.aim(target(last));
    await pumpEventQueue();
    expect(drawings.asked, [first, last]);
  });

  test('the deck stays on the target page until the reader lands there, then '
      'goes and frees its pages', () async {
    final place = (part: 3, progress: .5);
    previews.start(target(place), width: 300);
    await drawings.finish(place);
    final landing = Completer<void>();
    var landed = false;
    unawaited(
      previews.settle(target(place), landing.future).then((_) => landed = true),
    );
    await pumpEventQueue();
    expect(view().settling, isTrue);
    expect(view().front.page!.holds(place), isTrue);
    expect(landed, isFalse);
    landing.complete();
    await pumpEventQueue();
    expect(landed, isTrue);
    expect(previews.deck.value, isNull);
    expect(drawings.drawn.every((page) => page.image.debugDisposed), isTrue);
  });

  test('a drag keeps only the drawn pages nearest the thumb', () async {
    previews = PagePreviews(
      draw: drawings.draw,
      locate: (place) => (place.part + place.progress) / parts,
      capacity: 3,
    );
    previews.start(target((part: 1, progress: .5)), width: 300);
    await drawings.finishAll();
    previews.aim(target((part: 7, progress: .5)));
    await drawings.finishAll();
    final kept = drawings.drawn.where((page) => !page.image.debugDisposed);
    expect(kept, hasLength(3));
    expect(kept.every((page) => page.part == 7), isTrue);
    previews.checkInvariants();
  });

  test('a place that cannot be drawn is not tried again in the same drag, '
      'and its card stays blank', () async {
    final place = (part: 2, progress: .35);
    final other = (part: 5, progress: .5);
    previews.start(target(place), width: 300);
    await drawings.fail(place);
    expect(view().front, const DeckCard.blank());
    previews.aim(target(other));
    await drawings.finish(other);
    previews.aim(target(place));
    await pumpEventQueue();
    expect(drawings.asked.where((asked) => asked == place), hasLength(1));
    expect(view().front, const DeckCard.blank());
  });

  test('a drawing stops early when the thumb moves to another part of the '
      'book, and the thumb draws there next', () async {
    final first = (part: 2, progress: .35);
    final elsewhere = (part: 6, progress: .5);
    previews.start(target(first), width: 300);
    previews.aim(target(elsewhere));
    await pumpEventQueue();
    expect(drawings.abandoned, [first]);
    expect(drawings.asked.last, elsewhere);
    final page = await drawings.finish(elsewhere);
    expect(view().front, DeckCard(page: page));
  });

  test(
    'a drawing continues while the thumb stays in its part of the book',
    () async {
      final first = (part: 2, progress: .35);
      previews.start(target(first), width: 300);
      previews.aim(target((part: 2, progress: .38)));
      previews.aim(target((part: 2, progress: .9)));
      await pumpEventQueue();
      expect(drawings.abandoned, isEmpty);
      expect(drawings.drawing(first), isTrue);
    },
  );

  test('the drawing of a neighbor page continues while the thumb stays on '
      'its front page', () async {
    final place = (part: 2, progress: .95);
    previews.start(target(place), width: 300);
    final front = await drawings.finish(place);
    expect(drawings.asked.last, (part: 3, progress: 0));
    previews.aim(target((part: 2, progress: .97)));
    await pumpEventQueue();
    expect(drawings.abandoned, isEmpty);
    expect(drawings.drawing(front.next!), isTrue);
  });

  test('an abandoned place is drawn when the thumb comes back to it', () async {
    final first = (part: 2, progress: .35);
    final elsewhere = (part: 6, progress: .5);
    previews.start(target(first), width: 300);
    previews.aim(target(elsewhere));
    await pumpEventQueue();
    await drawings.finish(elsewhere);
    previews.aim(target(first));
    await drawings.finishAll();
    expect(drawings.asked.where((asked) => asked == first), hasLength(2));
    expect(view().front.page!.holds(first), isTrue);
  });

  test('closing the book ends the drag and stops its drawing', () async {
    final place = (part: 2, progress: .35);
    previews.start(target(place), width: 300);
    previews.close();
    await pumpEventQueue();
    expect(previews.deck.value, isNull);
    expect(drawings.abandoned, [place]);
  });

  test('a page drawn after its drag ended is freed', () async {
    drawings.stops = false;
    final place = (part: 2, progress: .35);
    previews.start(target(place), width: 300);
    previews.close();
    final late = await drawings.finish(place);
    expect(late.image.debugDisposed, isTrue);
    expect(previews.deck.value, isNull);
  });

  test(
    'a new drag draws its page once the drawing of the last drag ends',
    () async {
      drawings.stops = false;
      final first = (part: 2, progress: .35);
      final second = (part: 7, progress: .5);
      previews.start(target(first), width: 300);
      previews.close();
      previews.start(target(second), width: 300);
      await drawings.finish(first);
      expect(drawings.asked.last, second);
      final page = await drawings.finish(second);
      expect(view().front, DeckCard(page: page));
    },
  );

  test('a settling deck stops drawing pages other than its target', () async {
    final place = (part: 2, progress: .35);
    previews.start(target(place), width: 300);
    final front = await drawings.finish(place);
    expect(drawings.drawing(front.next!), isTrue);
    unawaited(previews.settle(target(place), Completer<void>().future));
    await pumpEventQueue();
    expect(drawings.abandoned, [front.next]);
    expect(drawings.asked, hasLength(2), reason: 'Nothing else is drawn.');
  });
}
