import 'dart:ui' as ui;

import 'package:bookfin/catalog/glass.dart';
import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/page_previews.dart';
import 'package:bookfin/reader/scrub_deck.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The shown page, which counts how often it is made, so a test can tell
/// that the deck keeps it.
class ShownPage extends StatefulWidget {
  const ShownPage({super.key});
  static var made = 0;
  @override
  State<ShownPage> createState() => _ShownPageState();
}

class _ShownPageState extends State<ShownPage> {
  @override
  void initState() {
    super.initState();
    ShownPage.made++;
  }

  @override
  Widget build(BuildContext context) =>
      const ColoredBox(color: Colors.white, child: SizedBox.expand());
}

const book = Book(
  id: 'first-frost',
  title: 'First Frost',
  author: 'Mara Ellison',
  editions: [],
);

final front = find.byKey(const ValueKey('deck front card'));
final previous = find.byKey(const ValueKey('deck previous card'));
final next = find.byKey(const ValueKey('deck next card'));
final shown = find.byType(ShownPage);

/// Whether the card that [card] finds is dimmed.
bool dimmed(Finder card) => find
    .descendant(of: card, matching: find.byKey(const ValueKey('deck dim')))
    .evaluate()
    .isNotEmpty;

/// The glass pane of the card that [card] finds.
Finder glassOf(Finder card) =>
    find.descendant(of: card, matching: find.byType(CoverGlass));

/// The page image on the card that [card] finds.
Finder imageOn(Finder card) =>
    find.descendant(of: card, matching: find.byType(RawImage));

/// A drawn page [width] by [height] pixels, page [page] of ten.
PagePreview drawn(int page, {int width = 2, int height = 2}) {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder);
  return PagePreview(
    part: 0,
    start: page / 10,
    end: page / 10 + .099,
    image: recorder.endRecording().toImageSync(width, height),
  );
}

void main() {
  late ValueNotifier<DeckView?> deck;
  setUp(() {
    deck = ValueNotifier(null);
    ShownPage.made = 0;
  });
  tearDown(() => deck.dispose());

  Future<void> show(WidgetTester tester, {bool reducedMotion = false}) =>
      tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(400, 800),
              disableAnimations: reducedMotion,
            ),
            child: ScrubDeck(
              deck: deck,
              paper: const Color(0xfff6efe2),
              book: book,
              page: const ShownPage(),
            ),
          ),
        ),
      );

  /// The page area.
  Rect area(WidgetTester tester) => tester.getRect(find.byType(ScrubDeck));

  testWidgets('without a drag, the page area shows only the page', (
    tester,
  ) async {
    await show(tester);
    expect(shown, findsOneWidget);
    expect(front, findsNothing);
    expect(previous, findsNothing);
    expect(next, findsNothing);
  });

  testWidgets('a drag opens a deck of glass cards over the shown page, which '
      'stays where it is, with smaller dimmed cards for the pages before and '
      'after the front card', (tester) async {
    await show(tester);
    deck.value = DeckView(
      front: const DeckCard.blank(),
      previous: DeckCard(page: drawn(2)),
      next: const DeckCard.blank(),
    );
    await tester.pumpAndSettle();
    final card = tester.getRect(front);
    expect(
      card.width,
      moreOrLessEquals(area(tester).width * ScrubDeck.frontScale, epsilon: 1),
    );
    expect(
      card.center.dx,
      moreOrLessEquals(area(tester).center.dx, epsilon: 1),
    );
    for (final each in [front, previous, next]) {
      expect(glassOf(each), findsOneWidget);
    }
    expect(tester.getRect(previous).width, lessThan(card.width));
    expect(tester.getRect(next).width, lessThan(card.width));
    expect(tester.getRect(previous).left, lessThan(card.left));
    expect(tester.getRect(next).right, greaterThan(card.right));
    expect(dimmed(previous) && dimmed(next), isTrue);
    expect(dimmed(front), isFalse);
    expect(
      tester.getRect(shown),
      area(tester),
      reason: 'The shown page does not move or scale.',
    );
    expect(
      ShownPage.made,
      1,
      reason: 'The shown page is kept, not made again.',
    );
  });

  testWidgets('a blank card is an empty glass card of the open book', (
    tester,
  ) async {
    await show(tester);
    deck.value = const DeckView(front: DeckCard.blank());
    await tester.pumpAndSettle();
    expect(glassOf(front), findsOneWidget);
    expect(tester.widget<CoverGlass>(glassOf(front)).book, book);
    expect(imageOn(front), findsNothing);
  });

  testWidgets('a drawn card shows its page inside the glass frame, with a '
      'margin around it, whole and at its own shape', (tester) async {
    await show(tester);
    final page = drawn(3, width: 300, height: 600);
    deck.value = DeckView(front: DeckCard(page: page));
    await tester.pumpAndSettle();
    expect(
      tester.widget<RawImage>(imageOn(front)).image!.isCloneOf(page.image),
      isTrue,
    );
    final card = tester.getRect(glassOf(front));
    final image = tester.getRect(imageOn(front));
    expect(image.width / image.height, moreOrLessEquals(.5, epsilon: .01));
    final margin = card.width * .04;
    expect(image.left - card.left, greaterThanOrEqualTo(margin));
    expect(card.right - image.right, greaterThanOrEqualTo(margin));
    expect(image.top - card.top, greaterThanOrEqualTo(margin));
    expect(card.bottom - image.bottom, greaterThanOrEqualTo(margin));
    expect(
      tester.widget<RawImage>(imageOn(front)).fit,
      anyOf(isNull, BoxFit.contain, BoxFit.fill),
      reason: 'No part of the page is cropped.',
    );
  });

  testWidgets('a wide drawn page fits the width of its card', (tester) async {
    await show(tester);
    deck.value = DeckView(
      front: DeckCard(page: drawn(3, width: 600, height: 300)),
    );
    await tester.pumpAndSettle();
    final card = tester.getRect(glassOf(front));
    final image = tester.getRect(imageOn(front));
    expect(image.width / image.height, moreOrLessEquals(2, epsilon: .02));
    expect(image.width, greaterThan(card.width * .8));
  });

  testWidgets('a settling deck holds still while the reader lands, then '
      'closes onto the front card, which covers the page until the deck goes', (
    tester,
  ) async {
    await show(tester);
    final page = drawn(3);
    deck.value = DeckView(front: DeckCard(page: page));
    await tester.pumpAndSettle();
    deck.value = DeckView(front: DeckCard(page: page), settling: true);
    await tester.pumpAndSettle();
    expect(
      tester.getRect(front).width,
      moreOrLessEquals(area(tester).width * ScrubDeck.frontScale, epsilon: 1),
      reason: 'Nothing moves while the reader draws its new page.',
    );
    deck.value = null;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(
      tester.getRect(front).width,
      greaterThan(area(tester).width * ScrubDeck.frontScale + 1),
      reason: 'The front card grows back toward the full page.',
    );
    final cover = find.ancestor(of: front, matching: find.byType(Opacity));
    expect(tester.widget<Opacity>(cover.first).opacity, 1);
    await tester.pumpAndSettle();
    expect(front, findsNothing);
    expect(shown, findsOneWidget);
    expect(ShownPage.made, 1);
  });

  testWidgets('a drag that ends without settling fades the deck away', (
    tester,
  ) async {
    await show(tester);
    deck.value = DeckView(front: DeckCard(page: drawn(3)));
    await tester.pumpAndSettle();
    deck.value = null;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    final cover = find.ancestor(of: front, matching: find.byType(Opacity));
    expect(tester.widget<Opacity>(cover.first).opacity, lessThan(1));
    await tester.pumpAndSettle();
    expect(front, findsNothing);
  });

  testWidgets('with reduced motion, the deck opens and closes without a zoom', (
    tester,
  ) async {
    await show(tester, reducedMotion: true);
    final page = drawn(3);
    deck.value = DeckView(front: DeckCard(page: page));
    await tester.pump();
    expect(
      tester.getRect(front).width,
      moreOrLessEquals(area(tester).width * ScrubDeck.frontScale, epsilon: 1),
    );
    deck.value = DeckView(front: DeckCard(page: page), settling: true);
    await tester.pump();
    expect(
      tester.getRect(front).width,
      moreOrLessEquals(area(tester).width * ScrubDeck.frontScale, epsilon: 1),
    );
    deck.value = null;
    await tester.pump();
    expect(front, findsNothing);
  });
}
