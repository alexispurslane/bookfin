import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/playback/native.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:flutter_test/flutter_test.dart';

import 'playback_test.dart'
    show LocalFiles, TestEngine, MemoryResume, account, title, recording, first;

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

  group('the system media player shows the blurred cover', () {
    const covered = Book(
      id: 'book',
      title: 'The journey',
      author: 'A. Writer',
      editions: [recording],
      cover: CoverRef('book', 'v1'),
    );
    const sequelRecording = Edition(
      id: 'sequel-recording',
      kind: EditionKind.audio,
      label: 'Reader',
      files: [first],
      memberIds: ['one:m1'],
    );
    const sequel = Book(
      id: 'sequel',
      title: 'The return',
      author: 'A. Writer',
      editions: [sequelRecording],
      cover: CoverRef('sequel', 'v1'),
    );
    Uri blurredFile(CoverRef cover) =>
        Uri.file('/covers/${cover.itemId}@${cover.tag}.blur.png');

    late LocalFiles downloads;
    late Playback playback;

    /// Each cover asked for, and the art that answers it, which the test
    /// gives when it chooses.
    late Map<CoverRef, Completer<Uri?>> asked;
    late List<String> accounts;
    PlaybackHandler handler() => PlaybackHandler(
      art: (session, cover) {
        accounts.add(session.scope.key);
        return (asked[cover] = Completer<Uri?>()).future;
      },
    )..attach(playback);

    setUp(() async {
      asked = {};
      accounts = [];
      downloads = LocalFiles();
      playback = Playback(
        downloads: downloads,
        engine: TestEngine(),
        store: MemoryResume(),
      );
      await playback.bind(account(), [covered, sequel]);
    });
    tearDown(() async {
      await playback.close();
      downloads.dispose();
    });

    test(
      'once it is ready, without holding back the book or playback',
      () async {
        await playback.open(covered, recording, autoplay: false);
        final session = handler();
        expect(session.mediaItem.value?.title, 'The journey');
        expect(session.mediaItem.value?.artUri, isNull);
        await playback.play();
        expect(session.playbackState.value.playing, isTrue);
        asked[covered.cover]!.complete(blurredFile(covered.cover!));
        await pumpEventQueue();
        expect(session.mediaItem.value?.artUri, blurredFile(covered.cover!));
        expect(session.mediaItem.value?.title, 'The journey');
        expect(accounts, [account().scope.key]);
      },
    );

    test('of the new book after a book change', () async {
      await playback.open(covered, recording, autoplay: false);
      final session = handler();
      asked[covered.cover]!.complete(blurredFile(covered.cover!));
      await pumpEventQueue();
      await playback.open(sequel, sequelRecording, autoplay: false);
      expect(session.mediaItem.value?.title, 'The return');
      expect(
        session.mediaItem.value?.artUri,
        isNull,
        reason: 'the old book cover does not show behind the new book',
      );
      asked[sequel.cover]!.complete(blurredFile(sequel.cover!));
      await pumpEventQueue();
      expect(session.mediaItem.value?.artUri, blurredFile(sequel.cover!));
    });

    test('of the open book, not of a book that was left first', () async {
      await playback.open(covered, recording, autoplay: false);
      final session = handler();
      await playback.open(sequel, sequelRecording, autoplay: false);
      asked[sequel.cover]!.complete(blurredFile(sequel.cover!));
      asked[covered.cover]!.complete(blurredFile(covered.cover!));
      await pumpEventQueue();
      expect(session.mediaItem.value?.title, 'The return');
      expect(session.mediaItem.value?.artUri, blurredFile(sequel.cover!));
    });

    test('asked for once for each book, not on each playback change', () async {
      await playback.open(covered, recording, autoplay: false);
      final session = handler();
      asked[covered.cover]!.complete(blurredFile(covered.cover!));
      await playback.play();
      await playback.seekEdition(20000);
      await playback.setSpeed(1.5);
      await playback.pause();
      const renamed = Book(
        id: 'book',
        title: 'The long journey',
        author: 'A. Writer',
        editions: [recording],
        cover: CoverRef('book', 'v1'),
      );
      await playback.bind(account(), [renamed, sequel]);
      await pumpEventQueue();
      expect(asked.keys, [covered.cover]);
      expect(session.mediaItem.value?.title, 'The long journey');
      expect(
        session.mediaItem.value?.artUri,
        blurredFile(covered.cover!),
        reason: 'a retitled book keeps its cover',
      );
    });

    test('nowhere for a book without a cover image', () async {
      await playback.bind(account(), [title, sequel]);
      await playback.open(title, recording, autoplay: false);
      final session = handler();
      await pumpEventQueue();
      expect(asked, isEmpty);
      expect(session.mediaItem.value?.title, 'The journey');
      expect(session.mediaItem.value?.artUri, isNull);
    });
  });

  // A headset button or the system's resume player can start Bookfin's
  // process. The play command then reaches the handler before Playback has
  // restored the book that it last played (t0-wedg).
  group('a system play that comes before the book', () {
    /// Lets queued playback work run, in fake and real time.
    Future<void> settle(WidgetTester tester) async {
      for (var step = 0; step < 20; step++) {
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump(Duration.zero);
      }
    }

    Future<(Playback, TestEngine)> unopened(WidgetTester tester) async {
      final downloads = LocalFiles();
      final engine = TestEngine();
      final playback = Playback(
        downloads: downloads,
        engine: engine,
        store: MemoryResume(),
      );
      addTearDown(downloads.dispose);
      await finish(tester, playback.bind(account(), [title]));
      return (playback, engine);
    }

    testWidgets('plays the book that a new process restores', (tester) async {
      final downloads = LocalFiles();
      addTearDown(downloads.dispose);
      final store = MemoryResume();
      final before = Playback(
        downloads: downloads,
        engine: TestEngine(),
        store: store,
      );
      await finish(tester, before.bind(account(), [title]));
      await finish(tester, before.open(title, recording, autoplay: false));
      await finish(tester, before.close());

      final handler = PlaybackHandler();
      await handler.play();
      final engine = TestEngine();
      final playback = Playback(
        downloads: downloads,
        engine: engine,
        store: store,
      );
      handler.attach(playback);
      await finish(tester, playback.bind(account(), [title]));
      await settle(tester);
      expect(engine.isPlaying, isTrue);
      expect(playback.edition, recording);
      await finish(tester, playback.close());
    });

    testWidgets('plays the book that opens after the play', (tester) async {
      final (playback, engine) = await unopened(tester);
      final handler = PlaybackHandler()..attach(playback);
      await handler.play();
      expect(engine.isPlaying, isFalse);
      await finish(tester, playback.open(title, recording, autoplay: false));
      await settle(tester);
      expect(engine.isPlaying, isTrue);
      await finish(tester, playback.close());
    });

    testWidgets('is forgotten when no book opens within ten seconds', (
      tester,
    ) async {
      final (playback, engine) = await unopened(tester);
      final handler = PlaybackHandler()..attach(playback);
      await handler.play();
      await tester.pump(const Duration(seconds: 11));
      await finish(tester, playback.open(title, recording, autoplay: false));
      await settle(tester);
      expect(engine.isPlaying, isFalse);
      await finish(tester, playback.close());
    });

    testWidgets('still plays a book that opens within ten seconds', (
      tester,
    ) async {
      final (playback, engine) = await unopened(tester);
      final handler = PlaybackHandler()..attach(playback);
      await handler.play();
      await tester.pump(const Duration(seconds: 9));
      await finish(tester, playback.open(title, recording, autoplay: false));
      await settle(tester);
      expect(engine.isPlaying, isTrue);
      await finish(tester, playback.close());
    });

    for (final (name, cancel)
        in <(String, Future<void> Function(AudioHandler))>[
          ('pause', (handler) => handler.pause()),
          ('stop', (handler) => handler.stop()),
        ]) {
      testWidgets('is cancelled by a $name before the book opens', (
        tester,
      ) async {
        final (playback, engine) = await unopened(tester);
        final handler = PlaybackHandler()..attach(playback);
        await handler.play();
        await cancel(handler);
        await finish(tester, playback.open(title, recording, autoplay: false));
        await settle(tester);
        expect(engine.isPlaying, isFalse);
        await finish(tester, playback.close());
      });
    }
  });
}
