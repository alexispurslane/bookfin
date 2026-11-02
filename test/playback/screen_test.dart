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
  testWidgets(
    'mini-player opens the same active recording and controls its position',
    (tester) async {
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
      await tester.pumpWidget(
        MaterialApp(
          theme: bookfinTheme(Brightness.light),
          home: Scaffold(body: PlayerView(playback: playback)),
        ),
      );
      await tester.tap(find.widgetWithText(OutlinedButton, 'Chapters'));
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
    'player offers speed and sleep without pretending history or sync exists',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: bookfinTheme(Brightness.dark),
          home: Scaffold(body: PlayerView(playback: playback)),
        ),
      );
      await tester.tap(find.text('1× speed'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('1.5×'));
      await tester.runAsync(() async {
        await tester.tap(find.text('1.5×'));
        await playback.flush();
      });
      await tester.pumpAndSettle();
      expect(playback.playbackSpeed, 1.5);
      await tester.tap(find.text('Sleep timer'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('15 minutes'));
        await playback.flush();
      });
      await tester.pumpAndSettle();
      expect(playback.sleepDeadline, isNotNull);
      expect(find.textContaining('sync complete'), findsNothing);
      expect(find.text('History'), findsNothing);
    },
  );
}
