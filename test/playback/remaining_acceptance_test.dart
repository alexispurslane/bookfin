import 'package:bookfin/foundation/theme.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:bookfin/playback/screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'playback_test.dart'
    show LocalFiles, MemoryResume, TestEngine, account, title, recording;

void main() {
  late LocalFiles downloads;
  late MemoryResume store;
  late Playback playback;

  setUp(() async {
    downloads = LocalFiles();
    store = MemoryResume();
    playback = Playback(
      downloads: downloads,
      engine: TestEngine(),
      store: store,
    );
    await playback.bind(account(), [title]);
    await playback.open(title, recording, autoplay: false);
  });

  tearDown(() async {
    await playback.close();
    downloads.dispose();
  });

  Future<void> showPlayer(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      theme: bookfinTheme(Brightness.light),
      home: Scaffold(body: PlayerView(playback: playback)),
    ),
  );

  /// Opens the History tool and the choices of the bookmark named [name].
  Future<void> showHistory(WidgetTester tester) async {
    await tester.ensureVisible(find.text('History'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
  }

  Future<void> restart(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      await playback.close();
      playback = Playback(
        downloads: downloads,
        engine: TestEngine(),
        store: store,
      );
      await playback.bind(account(), [title]);
    });
  }

  testWidgets(
    'canceling bookmark deletion preserves its title note and restorable position after restart',
    (tester) async {
      await tester.runAsync(() async {
        await playback.seekEdition(75000);
        await playback.addBookmark(title: 'Arrival', note: 'Keep this place');
        await playback.seekEdition(12000);
      });
      final bookmark = playback.bookmarks.single;
      final historyCount = playback.history.length;
      await showPlayer(tester);
      await showHistory(tester);
      await tester.fling(find.text('Arrival'), const Offset(-400, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.text('Delete bookmark?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Arrival'), findsOneWidget);
      expect(playback.bookmarks.single.id, bookmark.id);
      expect(playback.history, hasLength(historyCount));
      await restart(tester);
      expect(playback.bookmarks.single.id, bookmark.id);
      expect(playback.bookmarks.single.title, 'Arrival');
      expect(playback.bookmarks.single.note, 'Keep this place');
      await tester.runAsync(() => playback.restoreBookmark(bookmark.id));
      expect(playback.editionMilliseconds, 75000);
      playback.checkInvariants();
    },
  );

  testWidgets(
    'confirmed bookmark deletion survives restart without deleting another bookmark or history',
    (tester) async {
      await tester.runAsync(() async {
        await playback.seekEdition(45000);
        await playback.addBookmark(title: 'Remove this');
        await playback.seekEdition(75000);
        await playback.addBookmark(title: 'Keep this', note: 'Other place');
      });
      final kept = playback.bookmarks.firstWhere(
        (bookmark) => bookmark.title == 'Keep this',
      );
      final historyIds = playback.history.map((event) => event.id).toList();
      await showPlayer(tester);
      await showHistory(tester);
      // The delete saves in real time, so it starts outside the fake clock,
      // from the row's Delete action for a screen reader.
      final semantics = tester.ensureSemantics();
      await tester.runAsync(
        () async => tester.semantics.customAction(
          find.semantics.byLabel(RegExp('Remove this')),
          const CustomSemanticsAction(label: 'Delete'),
        ),
      );
      semantics.dispose();
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
        await Future<void>.delayed(Duration.zero);
        await playback.flush();
      });
      await tester.pumpAndSettle();
      expect(find.text('Remove this'), findsNothing);
      expect(playback.bookmarks.single.title, 'Keep this');
      await restart(tester);
      expect(playback.bookmarks.single.id, kept.id);
      expect(playback.bookmarks.single.note, 'Other place');
      expect(playback.history.map((event) => event.id), historyIds);
      await tester.runAsync(() => playback.restoreBookmark(kept.id));
      expect(playback.editionMilliseconds, 75000);
      playback.checkInvariants();
    },
  );
}
