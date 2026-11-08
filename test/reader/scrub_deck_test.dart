import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/page_previews.dart';
import 'package:bookfin/reader/scrub_deck.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'page_previews_test.dart' show picture;

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

final front = find.byKey(const ValueKey('deck front card'));
final previous = find.byKey(const ValueKey('deck previous card'));
final next = find.byKey(const ValueKey('deck next card'));
final shown = find.byType(ShownPage);

/// Whether the card that [card] finds is dimmed.
bool dimmed(Finder card) => find
    .descendant(of: card, matching: find.byKey(const ValueKey('deck dim')))
    .evaluate()
    .isNotEmpty;

PagePreview drawn(int page) => PagePreview(
  part: 0,
  start: page / 10,
  end: page / 10 + .099,
  image: picture(),
);

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

  testWidgets('a drag zooms the shown page out into the front card, with '
      'smaller dimmed cards for the pages before and after it', (tester) async {
    await show(tester);
    deck.value = DeckView(
      front: const DeckCard(page: null, exact: true),
      previous: DeckCard(page: drawn(2), exact: true),
      next: DeckCard(page: drawn(4), exact: true),
    );
    await tester.pump();
    expect(
      tester.getRect(front).width,
      moreOrLessEquals(area(tester).width, epsilon: 1),
      reason: 'The zoom starts at the full page.',
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
    expect(
      tester.getRect(shown),
      card,
      reason: 'The shown page fills the card.',
    );
    expect(tester.getRect(previous).width, lessThan(card.width));
    expect(tester.getRect(next).width, lessThan(card.width));
    expect(tester.getRect(previous).left, lessThan(card.left));
    expect(tester.getRect(next).right, greaterThan(card.right));
    expect(dimmed(previous) && dimmed(next), isTrue);
    expect(dimmed(front), isFalse);
    expect(
      ShownPage.made,
      1,
      reason: 'The shown page is kept, not made again.',
    );
  });

  testWidgets('the front card shows the drawn page under the thumb, and '
      'dims a page that stands in for it', (tester) async {
    await show(tester);
    final page = drawn(3);
    deck.value = DeckView(front: DeckCard(page: page, exact: true));
    await tester.pumpAndSettle();
    final image = find.descendant(of: front, matching: find.byType(RawImage));
    expect(tester.widget<RawImage>(image).image!.isCloneOf(page.image), isTrue);
    expect(dimmed(front), isFalse);
    deck.value = DeckView(front: DeckCard(page: page, exact: false));
    await tester.pumpAndSettle();
    expect(dimmed(front), isTrue);
  });

  testWidgets('a settling deck closes onto the front card, and goes when the '
      'drag ends', (tester) async {
    await show(tester);
    final page = drawn(3);
    deck.value = DeckView(front: DeckCard(page: page, exact: true));
    await tester.pumpAndSettle();
    deck.value = DeckView(
      front: DeckCard(page: page, exact: true),
      settling: true,
    );
    await tester.pumpAndSettle();
    expect(
      tester.getRect(front).width,
      moreOrLessEquals(area(tester).width, epsilon: 1),
    );
    deck.value = null;
    await tester.pumpAndSettle();
    expect(front, findsNothing);
    expect(shown, findsOneWidget);
    expect(ShownPage.made, 1);
  });

  testWidgets('with reduced motion, the deck opens and closes without a zoom', (
    tester,
  ) async {
    await show(tester, reducedMotion: true);
    final page = drawn(3);
    deck.value = DeckView(front: DeckCard(page: page, exact: true));
    await tester.pump();
    expect(
      tester.getRect(front).width,
      moreOrLessEquals(area(tester).width * ScrubDeck.frontScale, epsilon: 1),
    );
    deck.value = DeckView(
      front: DeckCard(page: page, exact: true),
      settling: true,
    );
    await tester.pump();
    expect(
      tester.getRect(front).width,
      moreOrLessEquals(area(tester).width, epsilon: 1),
    );
    deck.value = null;
    await tester.pump();
    expect(front, findsNothing);
  });
}
