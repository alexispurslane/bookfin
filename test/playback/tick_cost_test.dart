import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/foundation/theme.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:bookfin/playback/screen.dart';
import 'package:bookfin/playback/timeline.dart';
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
import 'timeline_test.dart' show other, otherFile, otherRecording;

/// A playback that counts how many places it measures, the work that a
/// player or timeline repeats per entry.
class CountingPlayback extends Playback {
  CountingPlayback({
    required super.downloads,
    required super.engine,
    required super.store,
  });
  int measured = 0;

  @override
  int? editionTime(AudioPosition position) {
    measured++;
    return super.editionTime(position);
  }
}

AudioPosition place(int milliseconds) => AudioPosition(
  editionId: recording.id,
  sourceKey: second.key,
  revision: second.revision,
  milliseconds: milliseconds,
);

void main() {
  late LocalFiles downloads;
  late TestEngine engine;
  late MemoryResume store;
  late CountingPlayback playback;
  setUp(() {
    downloads = LocalFiles()..files[otherFile.key] = Uri.file('/three.wav');
    engine = TestEngine();
    store = MemoryResume();
    playback = CountingPlayback(
      downloads: downloads,
      engine: engine,
      store: store,
    );
  });
  tearDown(() async {
    await playback.close();
    downloads.dispose();
  });

  /// One decoder sample 200 ms later, as arrives several times a second
  /// while audio plays.
  void tick() => engine.emit(engine.index, engine.milliseconds + 200);

  void useTallPhone(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
  }

  group('a long history', () {
    const entries = 600;
    setUp(() async {
      final now = DateTime.now().toUtc();
      store.values[account().scope.key] = {
        'version': 3,
        'history': [
          for (var i = 0; i < entries; i++)
            ListeningEvent(
              id: 'jump $i',
              at: now.subtract(Duration(minutes: 10 * i)),
              kind: ListeningAction.jump,
              before: place(0),
              after: place(30000),
              bookTitle: title.title,
              editionLabel: recording.label,
            ).toJson(),
        ],
        'bookmarks': [],
        'resumes': {},
      };
      await playback.bind(account(), [title]);
      await playback.open(title, recording, autoplay: false);
    });

    Future<void> openTimeline(WidgetTester tester) async {
      useTallPhone(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: bookfinTheme(Brightness.light),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    openListeningTimeline(context, playback, book: title),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
    }

    int builtRows() => find
        .descendant(
          of: find.byType(ListeningTimeline),
          matching: find.byType(InkWell),
          skipOffstage: false,
        )
        .evaluate()
        .length;

    testWidgets('opens without measuring every entry', (tester) async {
      playback.measured = 0;
      await openTimeline(tester);
      expect(builtRows(), lessThan(entries));
      expect(playback.measured, lessThan(entries));
    });

    testWidgets('does not measure every entry on a playing tick', (
      tester,
    ) async {
      await openTimeline(tester);
      playback.measured = 0;
      tick();
      await tester.pump();
      // Each entry that was derived again would be measured at least once.
      expect(playback.measured, greaterThan(0));
      expect(playback.measured, lessThan(entries));
    });

    testWidgets('scrolls to its oldest entry', (tester) async {
      await openTimeline(tester);
      await tester.dragUntilVisible(
        find.text('Yesterday'),
        find.byType(ListeningTimeline),
        const Offset(0, -600),
      );
      expect(find.text('Yesterday'), findsOneWidget);
    });
  });

  group('the position bar', () {
    setUp(() async {
      await playback.bind(account(), [title, other]);
      await playback.open(other, otherRecording, autoplay: false);
      await playback.addBookmark();
      await playback.open(title, recording, autoplay: false);
      await playback.seekEdition(75000);
      await playback.addBookmark();
      await playback.seekEdition(0);
    });

    Future<void> showPlayer(WidgetTester tester) async {
      useTallPhone(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: bookfinTheme(Brightness.light),
          home: Scaffold(body: PlayerView(playback: playback)),
        ),
      );
      await tester.pumpAndSettle();
    }

    final marks = find.byKey(const ValueKey('position marks'));
    CustomPainter painter(WidgetTester tester) =>
        tester.widget<CustomPaint>(marks).painter!;

    testWidgets('measures no bookmark on a playing tick', (tester) async {
      await showPlayer(tester);
      playback.measured = 0;
      tick();
      await tester.pump();
      expect(playback.measured, 0);
    });

    testWidgets('keeps its painted marks on a playing tick', (tester) async {
      await showPlayer(tester);
      final before = painter(tester);
      tick();
      await tester.pump();
      expect(painter(tester).shouldRepaint(before), isFalse);
    });

    testWidgets('paints its marks again for a new bookmark', (tester) async {
      await showPlayer(tester);
      final before = painter(tester);
      await tester.runAsync(() async {
        await playback.seekEdition(30000);
        await playback.addBookmark();
      });
      await tester.pump();
      expect(painter(tester).shouldRepaint(before), isTrue);
    });
  });
}
