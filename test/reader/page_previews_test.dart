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

  Future<PagePreview> draw(BookPlace place, double width) {
    asked.add(place);
    return (_pending[place] = Completer<PagePreview>()).future;
  }

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

  test('a drag opens the deck on the shown page and draws the page under '
      'the thumb', () {
    expect(previews.deck.value, isNull);
    final place = (part: 2, progress: .35);
    previews.start(target(place), width: 300);
    expect(view().front.page, isNull, reason: 'The shown page stands in.');
    expect(view().front.exact, isTrue);
    expect(view().previous, isNull, reason: 'No card is blank.');
    expect(view().next, isNull);
    expect(drawings.asked, [place]);
  });

  test(
    'the front card shows the page under the thumb once it is drawn',
    () async {
      final place = (part: 2, progress: .35);
      previews.start(target(place), width: 300);
      final page = await drawings.finish(place);
      expect(view().front, DeckCard(page: page, exact: true));
    },
  );

  test('the front card follows the thumb', () async {
    final first = (part: 2, progress: .35);
    final second = (part: 6, progress: .52);
    previews.start(target(first), width: 300);
    await drawings.finish(first);
    previews.aim(target(second));
    // The next page of the first place is being drawn, and finishes first.
    await drawings.finish(drawings.asked.last);
    expect(drawings.asked.last, second);
    final page = await drawings.finish(second);
    expect(view().front, DeckCard(page: page, exact: true));
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
      expect(view().previous, DeckCard(page: previous, exact: true));
      expect(view().next, DeckCard(page: next, exact: true));
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

  test('until its page is drawn, a card shows the nearest finished page, '
      'dimmed, and never a blank card', () async {
    previews.start(target((part: 2, progress: .15)), width: 300);
    await drawings.finishAll();
    previews.aim(target((part: 2, progress: .75)));
    await drawings.finishAll();
    // Pages 0 to 2 and 6 to 8 of part 2 are drawn.
    previews.aim(target((part: 2, progress: .5)));
    expect(drawings.asked.last, (part: 2, progress: .5));
    expect(view().front.exact, isFalse);
    expect(view().front.page!.holds((part: 2, progress: .6)), isTrue);
    expect(view().previous!.page!.holds((part: 2, progress: .2)), isTrue);
    expect(view().next!.page!.holds((part: 2, progress: .6)), isTrue);
    expect(view().previous!.exact || view().next!.exact, isFalse);
  });

  test('a place that the thumb left before its turn is never drawn', () async {
    final first = (part: 1, progress: .1);
    final passed = (part: 4, progress: .1);
    final last = (part: 8, progress: .1);
    previews.start(target(first), width: 300);
    previews.aim(target(passed));
    previews.aim(target(last));
    await drawings.finish(first);
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
      'and its card keeps the nearest finished page', () async {
    final place = (part: 2, progress: .35);
    final other = (part: 5, progress: .5);
    previews.start(target(place), width: 300);
    await drawings.fail(place);
    expect(view().front.page, isNull);
    previews.aim(target(other));
    final page = await drawings.finish(other);
    previews.aim(target(place));
    await pumpEventQueue();
    expect(drawings.asked.where((asked) => asked == place), hasLength(1));
    expect(view().front, DeckCard(page: page, exact: false));
  });

  test(
    'closing the book ends the drag, and a page drawn after that is freed',
    () async {
      final place = (part: 2, progress: .35);
      previews.start(target(place), width: 300);
      previews.close();
      expect(previews.deck.value, isNull);
      final late = await drawings.finish(place);
      expect(late.image.debugDisposed, isTrue);
      expect(previews.deck.value, isNull);
    },
  );
}
