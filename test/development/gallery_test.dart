import 'package:bookfin/appearance/preferences.dart';
import 'package:bookfin/catalog/book_cover.dart';
import 'package:bookfin/catalog/library_view.dart'
    show BookRow, ShelfFilterChips;
import 'package:bookfin/foundation/theme.dart' show ProgressLine;
import 'package:bookfin/main.dart';
import 'package:bookfin/playback/recent.dart';
import 'package:bookfin/playback/records_screen.dart';
import 'package:bookfin/playback/screen.dart';
import 'package:bookfin/playback/timeline.dart';
import 'package:bookfin/reader/screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../appearance/preferences_test.dart' show MemoryAppearanceStore;

/// Shows the development gallery on a phone-sized screen. The gallery gets
/// no catalog, Downloads or Playback, so no action in it can reach one.
Future<void> showGallery(WidgetTester tester) async {
  tester.view.physicalSize = const Size(412, 915);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    BookfinApp(
      appearance: AppearanceController(MemoryAppearanceStore()),
      gallery: true,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> openScreen(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(TextButton, label).first);
  await tester.pumpAndSettle();
}

Finder screen(String name) => find.byKey(PageStorageKey('gallery-$name'));

/// Scrolls the gallery screen [name] until [target] shows.
Future<void> reveal(WidgetTester tester, String name, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    200,
    scrollable: find
        .descendant(of: screen(name), matching: find.byType(Scrollable))
        .first,
  );
  await tester.pumpAndSettle();
}

/// Scrolls [target] into view, then taps it.
Future<void> tapShown(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

PositionSlider slider(WidgetTester tester) => tester.widget<PositionSlider>(
  find.byType(PositionSlider, skipOffstage: false),
);

Finder jump({required bool forward}) => find.byWidgetPredicate(
  (widget) => widget is JumpButton && widget.forward == forward,
  skipOffstage: false,
);

Finder stagePlayButton() => find.byWidgetPredicate(
  (widget) => widget is PlayPauseButton && widget.large,
  skipOffstage: false,
);

void main() {
  testWidgets('the library shows each sample book as a production book row', (
    tester,
  ) async {
    await showGallery(tester);
    final rows = find.descendant(
      of: screen('library'),
      matching: find.byType(BookRow),
    );
    expect(rows, findsNWidgets(3));
    for (final row in rows.evaluate()) {
      expect(
        find.descendant(
          of: find.byWidget(row.widget),
          matching: find.byType(BookCover),
        ),
        findsOneWidget,
      );
    }
  });

  testWidgets('the production filter row filters the sample books', (
    tester,
  ) async {
    await showGallery(tester);
    final chips = find.descendant(
      of: screen('library'),
      matching: find.byType(ShelfFilterChips),
    );
    expect(chips, findsOneWidget);
    expect(
      find.descendant(of: screen('library'), matching: find.byType(ChoiceChip)),
      findsNWidgets(
        find
            .descendant(of: chips, matching: find.byType(ChoiceChip))
            .evaluate()
            .length,
      ),
      reason: 'the gallery shows no filter chips of its own',
    );
    final rows = find.descendant(
      of: screen('library'),
      matching: find.byType(BookRow),
    );
    Future<void> choose(String filter) async {
      await tester.tap(find.descendant(of: chips, matching: find.text(filter)));
      await tester.pumpAndSettle();
    }

    await choose('Ebooks');
    expect(rows, findsOneWidget);
    expect(find.widgetWithText(BookRow, 'The Time Machine'), findsOneWidget);
    await choose('Downloaded');
    expect(rows, findsOneWidget);
    expect(find.widgetWithText(BookRow, 'The Time Machine'), findsOneWidget);
    await choose('Audio');
    expect(rows, findsNWidgets(3));
  });

  testWidgets('a tap on a library book opens it in the sample player', (
    tester,
  ) async {
    await showGallery(tester);
    await tester.tap(find.widgetWithText(BookRow, 'The Lost World'));
    await tester.pumpAndSettle();
    expect(screen('player').hitTestable(), findsOneWidget);
    expect(
      find.descendant(
        of: screen('player'),
        matching: find.text('The Lost World'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'the production mini player shows the sample book and opens the player',
    (tester) async {
      await showGallery(tester);
      expect(find.byType(MiniPlayerCard), findsOneWidget);
      await tester.tap(find.byTooltip('Open player'));
      await tester.pumpAndSettle();
      expect(screen('player').hitTestable(), findsOneWidget);
      expect(find.byType(MiniPlayerCard), findsNothing);
    },
  );

  testWidgets('the player stage is built from the production player leaves', (
    tester,
  ) async {
    await showGallery(tester);
    await openScreen(tester, 'Player & history');
    // From the top of the stage down, in the order that the stage shows them.
    for (final type in [BookCover, RecordSaveNotice, PositionSlider]) {
      final part = find.descendant(
        of: screen('player'),
        matching: find.byType(type),
      );
      await reveal(tester, 'player', part);
      expect(part, findsWidgets);
    }
    expect(jump(forward: false), findsOneWidget);
    expect(jump(forward: true), findsWidgets);
    expect(stagePlayButton(), findsOneWidget);
  });

  testWidgets('a forward jump moves the sample place and Undo returns it', (
    tester,
  ) async {
    await showGallery(tester);
    await openScreen(tester, 'Player & history');
    final start = slider(tester).position;
    await tapShown(tester, jump(forward: true));
    expect(slider(tester).position, start + 30000);
    expect(find.byType(UndoNotice, skipOffstage: false), findsOneWidget);
    await tapShown(
      tester,
      find.widgetWithText(FilledButton, 'Undo', skipOffstage: false),
    );
    expect(slider(tester).position, start);
    expect(find.byType(UndoNotice, skipOffstage: false), findsNothing);
  });

  testWidgets('a forward jump in the mini player moves its progress line', (
    tester,
  ) async {
    await showGallery(tester);
    final miniPlayer = find.byType(MiniPlayerCard);
    double shown() => tester
        .widget<ProgressLine>(
          find.descendant(of: miniPlayer, matching: find.byType(ProgressLine)),
        )
        .value!;
    final start = shown();
    await tapShown(
      tester,
      find.descendant(of: miniPlayer, matching: jump(forward: true)),
    );
    // Thirty seconds of the 3 h 28 min sample recording.
    expect(shown(), closeTo(start + 30000 / 12480000, 1e-9));
  });

  testWidgets('play and pause switch the sample button without a ticker', (
    tester,
  ) async {
    await showGallery(tester);
    await openScreen(tester, 'Player & history');
    await tapShown(tester, stagePlayButton());
    expect(tester.widget<PlayPauseButton>(stagePlayButton()).playing, isTrue);
    expect(tester.binding.transientCallbackCount, 0);
    await tapShown(tester, stagePlayButton());
    expect(tester.widget<PlayPauseButton>(stagePlayButton()).playing, isFalse);
  });

  testWidgets('a chapter in the production chapter sheet moves the sample', (
    tester,
  ) async {
    await showGallery(tester);
    await openScreen(tester, 'Player & history');
    await tester.tap(
      find.descendant(
        of: screen('player'),
        matching: find.textContaining('of 12'),
      ),
    );
    await tester.pumpAndSettle();
    final list = find.byType(ChapterList);
    // The sample place, 1 h 27 min in, is in chapter 6.
    expect(tester.widget<ChapterList>(list).current, 5);
    await tester.tap(
      find.descendant(of: list, matching: find.text('Chapter 3')),
    );
    await tester.pumpAndSettle();
    expect(list, findsNothing);
    // Each of the 12 sample chapters is a twelfth of 3 h 28 min.
    expect(slider(tester).position, 2 * 12480000 ~/ 12);
  });

  testWidgets('Go back in the production timeline restores the sample place', (
    tester,
  ) async {
    await showGallery(tester);
    await openScreen(tester, 'Player & history');
    await reveal(tester, 'player', find.textContaining('Jumped ahead'));
    expect(find.byType(ListeningTimeline), findsOneWidget);
    await tester.tap(find.textContaining('Jumped ahead'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Go back to'));
    await tester.pumpAndSettle();
    expect(slider(tester).position, 62 * 60000 + 9000);
  });

  testWidgets('Delete in the timeline asks first, then removes the entry', (
    tester,
  ) async {
    await showGallery(tester);
    await openScreen(tester, 'Player & history');
    await reveal(tester, 'player', find.textContaining('Jumped ahead'));
    expect(find.byType(ListeningTimeline), findsOneWidget);
    await tester.tap(find.textContaining('Jumped ahead'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete history action?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Jumped ahead'), findsNothing);
  });

  testWidgets('Start replacement starts the sample from the beginning', (
    tester,
  ) async {
    await showGallery(tester);
    await openScreen(tester, 'Player & history');
    await reveal(tester, 'player', find.byType(ReplacementOffer));
    await tester.tap(find.text('Start replacement'));
    await tester.pumpAndSettle();
    expect(find.byType(ReplacementOffer), findsNothing);
    expect(slider(tester).position, 0);
  });

  testWidgets('Retry saving clears the sample save failure', (tester) async {
    await showGallery(tester);
    await openScreen(tester, 'Player & history');
    await reveal(tester, 'player', find.text('Retry saving'));
    await tester.tap(find.text('Retry saving'));
    await tester.pumpAndSettle();
    expect(find.text('Retry saving'), findsNothing);
  });

  testWidgets('resuming a book in the production recent list opens it', (
    tester,
  ) async {
    await showGallery(tester);
    await openScreen(tester, 'Player & history');
    final row = find.widgetWithText(RecentListeningRow, 'The Poison Belt');
    await reveal(tester, 'player', row);
    expect(
      find.ancestor(of: row, matching: find.byType(RecentListeningList)),
      findsOneWidget,
    );
    expect(find.byType(RecentListeningRow), findsNWidgets(2));
    await tester.tap(row);
    await tester.pumpAndSettle();
    // As in the app, the recent books leave out the open book.
    expect(row, findsNothing);
    expect(
      find.widgetWithText(RecentListeningRow, 'The Time Machine'),
      findsOneWidget,
    );
  });

  testWidgets('the reader sample uses the production dock and tools', (
    tester,
  ) async {
    await showGallery(tester);
    await openScreen(tester, 'Reader');
    final bar = find.descendant(
      of: screen('reader'),
      matching: find.descendant(
        of: find.byType(ReaderDock),
        matching: find.byType(ReaderTools),
      ),
    );
    await reveal(tester, 'reader', bar);
    expect(bar, findsOneWidget);
    expect(
      find.descendant(of: screen('reader'), matching: find.byType(TextButton)),
      findsNothing,
      reason: 'the gallery has no reader control buttons of its own',
    );
  });

  testWidgets(
    'Smaller text shrinks the sample text, then turns off at its smallest',
    (tester) async {
      await showGallery(tester);
      await openScreen(tester, 'Reader');
      await reveal(tester, 'reader', find.byTooltip('Reading settings'));
      await tester.tap(find.byTooltip('Reading settings'));
      await tester.pumpAndSettle();
      double size() => tester
          .widget<Text>(
            find.textContaining(
              'The Time Traveller (for so',
              skipOffstage: false,
            ),
          )
          .style!
          .fontSize!;
      bool on(String control) =>
          tester
              .widget<IconButton>(
                find.byWidgetPredicate(
                  (widget) => widget is IconButton && widget.tooltip == control,
                ),
              )
              .onPressed !=
          null;
      final start = size();
      await tester.tap(find.byTooltip('Smaller text'));
      await tester.pumpAndSettle();
      expect(size(), lessThan(start));
      while (on('Smaller text')) {
        await tester.tap(find.byTooltip('Smaller text'));
        await tester.pumpAndSettle();
      }
      expect(on('Larger text'), isTrue);
    },
  );

  testWidgets('the theme control turns the sample page to the night theme', (
    tester,
  ) async {
    await showGallery(tester);
    await openScreen(tester, 'Reader');
    await reveal(tester, 'reader', find.byTooltip('Reading settings'));
    await tester.tap(find.byTooltip('Reading settings'));
    await tester.pumpAndSettle();
    Brightness page() => Theme.of(
      tester.element(
        find.textContaining('The Time Traveller (for so', skipOffstage: false),
      ),
    ).brightness;
    expect(page(), Brightness.light);
    await tester.tap(find.byTooltip('Night reading theme'));
    await tester.pumpAndSettle();
    expect(page(), Brightness.dark);
    await tester.tap(find.byTooltip('Cream reading theme'));
    await tester.pumpAndSettle();
    expect(page(), Brightness.light);
  });

  testWidgets('a contents entry in the production panel moves the sample', (
    tester,
  ) async {
    await showGallery(tester);
    await openScreen(tester, 'Reader');
    await reveal(tester, 'reader', find.byTooltip('Contents'));
    await tester.tap(find.byTooltip('Contents'));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderContentsPanel), findsOneWidget);
    await tester.tap(find.text('III · The Time Traveller Returns'));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderContentsPanel), findsNothing);
    expect(find.text('CHAPTER III'), findsOneWidget);
  });

  testWidgets('the production search panel finds words in the sample text', (
    tester,
  ) async {
    await showGallery(tester);
    await openScreen(tester, 'Reader');
    await reveal(tester, 'reader', find.byTooltip('Search book'));
    await tester.tap(find.byTooltip('Search book'));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderSearchPanel), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'radiance');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    final hit = find.ancestor(
      of: find.textContaining('radiance'),
      matching: find.byType(ListTile),
    );
    expect(hit, findsOneWidget);
    await tester.tap(hit);
    await tester.pumpAndSettle();
    expect(find.byType(ReaderSearchPanel), findsNothing);
  });

  testWidgets(
    'a bookmark renamed in the shared editor shows in the bookmarks panel',
    (tester) async {
      await showGallery(tester);
      await openScreen(tester, 'Reader');
      await reveal(tester, 'reader', find.byTooltip('Bookmark this place'));
      await tester.tap(find.byTooltip('Bookmark this place'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Contents'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(Tab, 'Bookmarks'));
      await tester.pumpAndSettle();
      final panel = find.byType(ReaderContentsPanel);
      expect(
        find.descendant(of: panel, matching: find.text('Saved reading place')),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Edit reading bookmark'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit title and note'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Title (optional)'),
        'By the fire',
      );
      await tester.tap(find.text('Save bookmark'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: panel, matching: find.text('By the fire')),
        findsOneWidget,
      );
    },
  );
}
