import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/foundation/theme.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:bookfin/playback/recent.dart';
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
        first,
        second;
import 'timeline_test.dart' show other, otherFile, otherRecording;

// recentProgress reads the recent books and their progress from a Playback.
// These tests drive a real Playback, so they show which of its changes reach
// the recently listened list.

/// [title] after a refresh that finds part two ten minutes longer.
final _longer = Book(
  id: title.id,
  title: title.title,
  author: title.author,
  editions: [
    Edition(
      id: recording.id,
      kind: recording.kind,
      label: recording.label,
      files: [
        first,
        SourceFile(
          itemId: second.itemId,
          displayName: second.displayName,
          mediaSourceId: second.mediaSourceId,
          revision: second.revision,
          durationMs: second.durationMs! + 600000,
          container: second.container,
          sizeBytes: second.sizeBytes,
          chapters: second.chapters,
        ),
      ],
      memberIds: recording.memberIds,
    ),
  ],
);

void main() {
  late LocalFiles downloads;
  late TestEngine engine;
  late MemoryResume store;
  setUp(() {
    downloads = LocalFiles()..files[otherFile.key] = Uri.file('/three.wav');
    store = MemoryResume();
  });
  tearDown(() => downloads.dispose());

  /// A new Playback on [store]. Each one gets its own engine, because a
  /// closed Playback closes its engine.
  Playback playbackOn(MemoryResume store) => Playback(
    downloads: downloads,
    engine: engine = TestEngine(),
    store: store,
  );

  testWidgets('with no book open, a library refresh that changes the length '
      'of a listened edition updates the time left in its recent row', (
    tester,
  ) async {
    late Playback playback;
    await tester.runAsync(() async {
      // Thirty seconds into the journey, then the other book, which stays
      // the open book of this account.
      final earlier = playbackOn(store);
      await earlier.bind(account(), [title, other]);
      await earlier.open(title, recording, autoplay: false);
      await earlier.jump(forward: true);
      await earlier.open(other, otherRecording, autoplay: false);
      await earlier.jump(forward: true);
      await earlier.flush();
      await earlier.close();
      // A library without the other book opens nothing.
      playback = playbackOn(store);
      await playback.bind(account(), [title]);
    });
    addTearDown(() => tester.runAsync(playback.close));
    expect(playback.book, isNull);
    await tester.pumpWidget(
      MaterialApp(
        theme: bookfinTheme(Brightness.light),
        home: Scaffold(
          body: RecentListeningList(
            recent: recentProgress(playback),
            open: null,
            onResume: (_) {},
          ),
        ),
      ),
    );
    final journey = find.widgetWithText(RecentListeningRow, title.title);
    expect(
      find.descendant(of: journey, matching: find.textContaining('2 m left')),
      findsOneWidget,
    );

    await tester.runAsync(() => playback.bind(account(), [_longer]));
    await tester.pump();

    expect(playback.book, isNull);
    expect(
      find.descendant(of: journey, matching: find.textContaining('12 m left')),
      findsOneWidget,
    );
  });

  test('a playing tick does not reach the recent books', () async {
    final playback = playbackOn(store);
    addTearDown(playback.close);
    await playback.bind(account(), [title, other]);
    await playback.open(other, otherRecording, autoplay: false);
    await playback.jump(forward: true);
    await playback.open(title, recording, autoplay: false);
    await playback.play();
    final recent = recentProgress(playback);
    var notices = 0;
    void heard() => notices++;
    recent.addListener(heard);
    addTearDown(() => recent.removeListener(heard));
    for (var step = 0; step < 10; step++) {
      engine.emit(engine.index, engine.milliseconds + 200, playing: true);
    }
    await playback.flush();
    expect(notices, 0);
  });
}
