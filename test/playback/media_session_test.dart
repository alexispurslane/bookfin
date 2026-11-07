import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/playback/native.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:flutter_test/flutter_test.dart';

import 'playback_test.dart'
    show LocalFiles, TestEngine, MemoryResume, account, title, recording;

/// A playback that tells whether anything follows its broad notifications,
/// which fire for every change, including each player tick.
class WatchedPlayback extends Playback {
  WatchedPlayback({
    required super.downloads,
    required super.engine,
    required super.store,
  });
  bool get followedBroadly => hasListeners;
}

// Android's media session projects the shown position from the last published
// position, its update time and its speed. These tests run in fake time, so
// the projection and the player ticks share one clock.
void main() {
  /// Runs fake and real time until [work] ends. Playback work starts in fake
  /// time, so the media session stamps its states with the fake clock, but the
  /// work also waits on real IO.
  Future<void> finish(WidgetTester tester, Future<void> work) async {
    var done = false;
    unawaited(work.whenComplete(() => done = true));
    for (var step = 0; !done && step < 100; step++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(Duration.zero);
    }
    expect(done, isTrue);
  }

  Future<(Playback, TestEngine, PlaybackHandler)> listen(
    WidgetTester tester,
  ) async {
    final downloads = LocalFiles();
    final engine = TestEngine();
    final playback = Playback(
      downloads: downloads,
      engine: engine,
      store: MemoryResume(),
    );
    addTearDown(downloads.dispose);
    await finish(tester, playback.bind(account(), [title]));
    await finish(tester, playback.open(title, recording, autoplay: false));
    final handler = PlaybackHandler()..attach(playback);
    await finish(tester, playback.seekEdition(10000));
    await finish(tester, playback.play());
    return (playback, engine, handler);
  }

  // Five player ticks per second, as the decoder reports while playing.
  Future<void> play(
    WidgetTester tester,
    TestEngine engine, {
    required int ticks,
    int advance = 200,
  }) async {
    for (var tick = 0; tick < ticks; tick++) {
      await tester.pump(const Duration(milliseconds: 200));
      engine.emit(0, engine.milliseconds + advance, playing: true);
    }
  }

  testWidgets('steady playback publishes nothing new to the media session', (
    tester,
  ) async {
    final (playback, engine, handler) = await listen(tester);
    final state = handler.playbackState.value;
    final item = handler.mediaItem.value;
    await play(tester, engine, ticks: 25);
    expect(playback.editionMilliseconds, 15000);
    expect(handler.playbackState.value, same(state));
    expect(handler.mediaItem.value, same(item));
    expect(handler.playbackState.value.position, const Duration(seconds: 15));
    await finish(tester, playback.close());
  });

  testWidgets(
    'the session position stays within a second of a stalled player',
    (tester) async {
      final (playback, engine, handler) = await listen(tester);
      for (var tick = 0; tick < 20; tick++) {
        await play(tester, engine, ticks: 1, advance: 0);
        final shown = handler.playbackState.value.position.inMilliseconds;
        expect(
          (shown - playback.editionMilliseconds!).abs(),
          lessThanOrEqualTo(1000),
        );
      }
      expect(handler.playbackState.value.updatePosition.inMilliseconds, 10000);
      await finish(tester, playback.close());
    },
  );

  testWidgets(
    'a seek, a jump and a speed change during playback reach the session',
    (tester) async {
      final (playback, engine, handler) = await listen(tester);
      await play(tester, engine, ticks: 5);
      await finish(tester, handler.seek(const Duration(seconds: 100)));
      expect(
        handler.playbackState.value.updatePosition,
        const Duration(seconds: 100),
      );
      await finish(tester, handler.fastForward());
      expect(
        handler.playbackState.value.updatePosition,
        Duration(seconds: 100 + playback.forwardSeconds),
      );
      await finish(tester, handler.setSpeed(1.5));
      expect(handler.playbackState.value.speed, 1.5);
      await finish(tester, handler.pause());
      expect(handler.playbackState.value.playing, isFalse);
      expect(handler.playbackState.value.controls, contains(MediaControl.play));
      await finish(tester, playback.close());
    },
  );

  testWidgets('a pause from the player reaches the session at once', (
    tester,
  ) async {
    final (playback, engine, handler) = await listen(tester);
    await play(tester, engine, ticks: 2);
    expect(handler.playbackState.value.playing, isTrue);
    // An interruption: the decoder stops without a pause command.
    engine.emit(0, engine.milliseconds);
    expect(handler.playbackState.value.playing, isFalse);
    expect(handler.playbackState.value.controls, contains(MediaControl.play));
    await finish(tester, playback.close());
  });

  test(
    'the session follows only the selection, the position and the settings',
    () async {
      final downloads = LocalFiles();
      final playback = WatchedPlayback(
        downloads: downloads,
        engine: TestEngine(),
        store: MemoryResume(),
      );
      addTearDown(() async {
        await playback.close();
        downloads.dispose();
      });
      await playback.bind(account(), [title]);
      await playback.open(title, recording, autoplay: false);
      final handler = PlaybackHandler()..attach(playback);
      expect(playback.followedBroadly, isFalse);
      final state = handler.playbackState.value;
      await playback.addBookmark(title: 'Here');
      expect(handler.playbackState.value, same(state));
    },
  );

  test(
    'a library refresh that renames the open book retitles the session',
    () async {
      final downloads = LocalFiles();
      final playback = Playback(
        downloads: downloads,
        engine: TestEngine(),
        store: MemoryResume(),
      );
      addTearDown(() async {
        await playback.close();
        downloads.dispose();
      });
      await playback.bind(account(), [title]);
      await playback.open(title, recording, autoplay: false);
      final handler = PlaybackHandler()..attach(playback);
      expect(handler.mediaItem.value?.title, 'The journey');
      const renamed = Book(
        id: 'book',
        title: 'The long journey',
        author: 'A. Writer',
        editions: [recording],
      );
      await playback.bind(account(), [renamed]);
      expect(handler.mediaItem.value?.title, 'The long journey');
    },
  );
}
