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
      await tester.tap(find.byTooltip('Bookmarks and history'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Pause'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text('Restore bookmark'));
        await playback.flush();
      });
      await tester.pumpAndSettle();
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
      expect(find.byType(NavigationBar), findsNothing);
      await tester.scrollUntilVisible(find.text('Chapters'), 150);
      expect(find.text('Chapters'), findsOneWidget);
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
      expect(find.byTooltip('Bookmarks and history'), findsOneWidget);
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
        slider.onChanged!(40000);
        slider.onChanged!(95000);
        await playback.flush();
      });
      await tester.pump();
      expect(playback.editionMilliseconds, 0);
      expect(tester.widget<Slider>(find.byType(Slider)).value, 95000);
      slider = tester.widget<Slider>(find.byType(Slider));
      await tester.runAsync(() async {
        slider.onChangeEnd?.call(95000);
        await playback.flush();
      });
      await tester.pumpAndSettle();
      expect(playback.editionMilliseconds, 95000);
      expect(
        playback.history.where((event) => event.kind == ListeningAction.seek),
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
    'bookmarks can be added edited restored and deleted from listening history',
    (tester) async {
      phone(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: bookfinTheme(Brightness.light),
          home: Scaffold(body: PlayerView(playback: playback)),
        ),
      );
      await tester.scrollUntilVisible(find.text('Bookmark'), 150);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bookmark'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Title (optional)'),
        'Remember',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Note (optional)'),
        'A note',
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('Save bookmark'));
        await playback.flush();
      });
      await tester.pumpAndSettle();
      expect(playback.bookmarks.single.title, 'Remember');
      await tester.tap(find.byTooltip('Bookmarks and history'));
      await tester.pumpAndSettle();
      expect(find.text('Remember'), findsOneWidget);
      await tester.tap(find.byTooltip('Edit bookmark'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Title (optional)'),
        'Revised',
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('Save bookmark'));
        await playback.flush();
      });
      await tester.pumpAndSettle();
      expect(find.text('Revised'), findsOneWidget);
      await tester.runAsync(() async {
        await playback.seekEdition(70000);
        await tester.tap(find.text('Restore bookmark'));
        await playback.flush();
      });
      await tester.pumpAndSettle();
      expect(playback.editionMilliseconds, 0);
      await tester.tap(find.byTooltip('Delete bookmark'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Delete'));
        await playback.flush();
      });
      await tester.pumpAndSettle();
      expect(playback.bookmarks, isEmpty);
      expect(find.text('Revised'), findsNothing);
      expect(find.text('Bookmark restore'), findsOneWidget);
    },
  );
}

/// A Pixel 8 sized screen, so the whole player stage fits.
void phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
}
