import 'package:bookfin/catalog/glass.dart';
import 'package:bookfin/foundation/theme.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:bookfin/playback/screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'playback_test.dart'
    show
        LocalFiles,
        TestEngine,
        MemoryResume,
        account,
        title,
        recording,
        second;

void main() {
  late Playback playback;
  late LocalFiles downloads;
  setUp(() async {
    downloads = LocalFiles();
    playback = Playback(
      downloads: downloads,
      engine: TestEngine(),
      store: MemoryResume(),
    );
    await playback.bind(account(), [title]);
    await playback.open(title, recording);
  });
  tearDown(() async {
    await playback.close();
    downloads.dispose();
  });
  testWidgets('mini-player offers Undo where a forward jump occurs', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: bookfinTheme(Brightness.light),
        home: Scaffold(
          bottomNavigationBar: PlaybackMiniPlayer(playback: playback),
        ),
      ),
    );
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Forward 30 seconds'));
      await playback.flush();
    });
    await tester.pumpAndSettle();
    expect(find.text('Undo'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.text('Undo'));
      await playback.flush();
    });
    expect(playback.editionMilliseconds, 0);
  });

  testWidgets(
    'history keeps playback controls and Undo after bookmark restore',
    (tester) async {
      phone(tester);
      await tester.runAsync(() async {
        await playback.addBookmark(title: 'Beginning');
        await playback.seekEdition(75000);
      });
      playback.dismissUndo();
      await tester.pumpWidget(
        MaterialApp(
          theme: bookfinTheme(Brightness.light),
          home: Scaffold(body: PlayerView(playback: playback)),
        ),
      );
      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Beginning'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('GO TO'));
        await playback.flush();
      });
      await tester.pumpAndSettle();
      expect(find.byTooltip('Pause'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text('Undo'));
        await playback.flush();
        await tester.tap(find.byTooltip('Pause'));
        await playback.flush();
      });
      expect(playback.editionMilliseconds, 75000);
      expect(playback.playing, isFalse);
    },
  );
  testWidgets(
    'mini-player opens the same active recording and controls its position',
    (tester) async {
      phone(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: bookfinTheme(Brightness.light),
          home: Scaffold(
            bottomNavigationBar: PlaybackMiniPlayer(playback: playback),
          ),
        ),
      );
      expect(find.text('The journey'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Pause'));
        await playback.flush();
      });
      await tester.pumpAndSettle();
      expect(playback.playing, isFalse);
      await tester.tap(find.byTooltip('Open player'));
      await tester.pumpAndSettle();
      expect(find.byType(PlayerView), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Chapters'), 150);
      expect(find.text('Chapters'), findsOneWidget);
    },
  );
  testWidgets(
    'the mini player opens the player in a glass pane over the page',
    (tester) async {
      phone(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: bookfinTheme(Brightness.light),
          home: Scaffold(
            body: const Center(child: Text('Page beneath')),
            bottomNavigationBar: PlaybackMiniPlayer(playback: playback),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Open player'));
      await tester.pumpAndSettle();
      expect(
        find.ancestor(
          of: find.byType(PlayerView),
          matching: find.byType(CoverGlass),
        ),
        findsOneWidget,
      );
      expect(find.text('Page beneath'), findsOneWidget);

      await tester.tap(find.byTooltip('Close player'));
      await tester.pumpAndSettle();
      expect(find.byType(PlayerView), findsNothing);
      expect(find.text('Page beneath'), findsOneWidget);
    },
  );

  testWidgets(
    'chapter selection seeks to the actual source without losing playback',
    (tester) async {
      phone(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: bookfinTheme(Brightness.light),
          home: Scaffold(body: PlayerView(playback: playback)),
        ),
      );
      await tester.scrollUntilVisible(find.text('Chapters'), 150);
      await tester.tap(find.text('Chapters'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Return'));
        await playback.flush();
      });
      await tester.pumpAndSettle();
      expect(playback.position?.sourceKey, second.key);
      expect(playback.position?.milliseconds, 10000);
      expect(playback.playing, isTrue);
    },
  );
  testWidgets(
    'player offers speed and sleep without claiming sync completion',
    (tester) async {
      phone(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: bookfinTheme(Brightness.dark),
          home: Scaffold(body: PlayerView(playback: playback)),
        ),
      );
      await tester.scrollUntilVisible(find.text('Speed'), 150);
      await tester.tap(find.text('Speed'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('1.5×'));
      await tester.runAsync(() async {
        await tester.tap(find.text('1.5×'));
        await playback.flush();
      });
      await tester.pumpAndSettle();
      expect(playback.playbackSpeed, 1.5);
      await tester.ensureVisible(find.text('Sleep'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sleep'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('15 minutes'));
        await playback.flush();
      });
      await tester.pumpAndSettle();
      expect(playback.sleepDeadline, isNotNull);
      expect(find.textContaining('sync complete'), findsNothing);
      expect(find.text('History'), findsOneWidget);
    },
  );

  testWidgets(
    'slider previews a drag without seeking until release and offers Undo',
    (tester) async {
      phone(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: bookfinTheme(Brightness.light),
          home: Scaffold(body: PlayerView(playback: playback)),
        ),
      );
      var slider = tester.widget<Slider>(find.byType(Slider));
      await tester.runAsync(() async {
        slider.onChangeStart?.call(0);
        slider.onChanged!(40000 / 150000);
        slider.onChanged!(95000 / 150000);
        await playback.flush();
      });
      await tester.pump();
      expect(playback.editionMilliseconds, 0);
      expect(tester.widget<Slider>(find.byType(Slider)).value, 95000 / 150000);
      slider = tester.widget<Slider>(find.byType(Slider));
      await tester.runAsync(() async {
        slider.onChangeEnd?.call(95000 / 150000);
        await playback.flush();
      });
      await tester.pumpAndSettle();
      expect(playback.editionMilliseconds, 95000);
      expect(
        playback.history.where((event) => event.kind == HistoryAction.seek),
        hasLength(1),
      );
      await tester.scrollUntilVisible(find.text('Undo'), 150);
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Undo'));
        await playback.flush();
      });
      await tester.pumpAndSettle();
      expect(playback.editionMilliseconds, 0);
    },
  );

  testWidgets(
    'bookmarks can be saved named restored and deleted from the history timeline',
    (tester) async {
      phone(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: bookfinTheme(Brightness.light),
          home: Scaffold(body: PlayerView(playback: playback)),
        ),
      );
      Future<void> save(String title) async {
        await tester.enterText(
          find.widgetWithText(TextField, 'Title (optional)'),
          title,
        );
        await tester.runAsync(() async {
          await tester.tap(find.text('Save bookmark'));
          await playback.flush();
        });
        await tester.pumpAndSettle();
      }

      await tester.runAsync(() async {
        await tester.tap(find.text('Bookmark'));
        await playback.flush();
      });
      await tester.pumpAndSettle();
      // The editor returns its text, and the code that opened it saves
      // after it closes, so the opening tap runs on real time.
      await tester.runAsync(() => tester.tap(find.text('Bookmarked')));
      await tester.pumpAndSettle();
      await save('Remember');
      expect(playback.bookmarks.single.title, 'Remember');

      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remember'));
      await tester.pumpAndSettle();
      await tester.runAsync(() => tester.tap(find.byTooltip('Rename')));
      await tester.pumpAndSettle();
      await save('Revised');
      expect(find.text('Revised'), findsOneWidget);

      await tester.runAsync(() async {
        await playback.seekEdition(70000);
        await tester.tap(find.text('GO TO'));
        await playback.flush();
      });
      await tester.pumpAndSettle();
      expect(playback.editionMilliseconds, 0);

      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();
      expect(find.text('Went to a bookmark'), findsOneWidget);
      await tester.tap(find.text('Revised'));
      await tester.pumpAndSettle();
      await tester.runAsync(() => tester.tap(find.byTooltip('Delete')));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
        await Future<void>.delayed(Duration.zero);
        await playback.flush();
      });
      await tester.pumpAndSettle();
      expect(playback.bookmarks, isEmpty);
      expect(find.text('Revised'), findsNothing);
    },
  );
}

/// A Pixel 8 sized screen, so the whole player stage fits.
void phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
}
