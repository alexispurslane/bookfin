import 'dart:async';

import 'package:bookfin/playback/playback.dart';
import 'package:flutter_test/flutter_test.dart';

import 'playback_test.dart';

/// An audio engine whose next pause or seek fails with [failure].
class _FailingEngine extends TestEngine {
  Object? failure;

  void _failOnce() {
    final failure = this.failure;
    this.failure = null;
    if (failure != null) throw failure;
  }

  @override
  Future<void> pause() async {
    _failOnce();
    return super.pause();
  }

  @override
  Future<AudioSample> seek(int fileIndex, int position) async {
    _failOnce();
    return super.seek(fileIndex, position);
  }
}

// How Playback's command queue treats a command that fails. A bug (an Error
// that is not an Exception) stays visible and never stops later commands. An
// Exception goes where the kind of the command says: an engine failure stops
// the audio with a message, and a records failure goes to the caller.
void main() {
  late LocalFiles downloads;
  late _FailingEngine engine;
  late MemoryResume store;
  late Playback playback;
  setUp(() async {
    downloads = LocalFiles();
    engine = _FailingEngine();
    store = MemoryResume();
    playback = Playback(downloads: downloads, engine: engine, store: store);
    await playback.bind(account(), [title]);
    await playback.open(title, recording);
  });
  tearDown(() async {
    await playback.close();
    downloads.dispose();
  });

  group('after a command that failed with a bug', () {
    test('a later command still runs', () async {
      engine.failure = StateError('A bug in the seek.');
      await expectLater(playback.seekEdition(75000), throwsStateError);

      await playback.seekEdition(30000);

      expect(playback.editionMilliseconds, 30000);
    });

    test('Playback still flushes and closes', () async {
      engine.failure = StateError('A bug in the pause.');
      await expectLater(playback.pause(), throwsStateError);

      await playback.flush();
      await playback.close();

      expect(engine.closed, isTrue);
    });
  });

  test('the future of a command that failed with a bug carries the bug', () async {
    engine.failure = StateError('A bug in the seek.');

    await expectLater(playback.seekEdition(75000), throwsStateError);
  });

  test('a bug in a command that nothing awaits is reported once', () async {
    // The pause at the end of a recording is a command that Playback starts
    // for itself, so no caller holds its future.
    final uncaught = <Object>[];
    final done = Completer<void>();
    runZonedGuarded(() async {
      final downloads = LocalFiles();
      final engine = _FailingEngine();
      final playback = Playback(
        downloads: downloads,
        engine: engine,
        store: MemoryResume(),
      );
      try {
        await playback.bind(account(), [title]);
        await playback.open(title, recording);
        engine.failure = StateError('A bug in the pause.');
        engine.emit(1, 90000, playing: true, completed: true);
        await pumpEventQueue();
        await playback.close();
        downloads.dispose();
      } finally {
        done.complete();
      }
    }, (error, stack) => uncaught.add(error));
    await done.future;

    expect(uncaught, [isStateError]);
  });

  group('a records refresh that cannot read the store, while audio plays', () {
    /// Refreshes the records while the store cannot be read.
    Future<void> failedRefresh() async {
      await playback.flush();
      store.failRead = true;
      await playback.refreshPersonalRecords().onError<Exception>((_, _) {});
    }

    test('leaves the audio playing', () async {
      await failedRefresh();

      expect(engine.isPlaying, isTrue);
      expect(playback.playing, isTrue);
      expect(playback.active, isTrue);
      playback.checkInvariants();
    });

    test('shows no message about the audio', () async {
      await failedRefresh();

      expect(playback.message, isNull);
      expect(playback.statusNotifier.value.message, isNull);
    });

    test('tells its caller that the refresh failed', () async {
      await playback.flush();
      store.failRead = true;

      await expectLater(playback.refreshPersonalRecords(), throwsException);
    });

    test('does not stop a later command', () async {
      await failedRefresh();

      await playback.seekEdition(30000);

      expect(playback.editionMilliseconds, 30000);
      expect(playback.playing, isTrue);
    });
  });

  test('an audio command whose engine call fails stops the audio and says that the file cannot play', () async {
    engine.failure = Exception('The decoder failed.');

    await playback.seekEdition(75000);

    expect(engine.isPlaying, isFalse);
    expect(playback.active, isFalse);
    expect(playback.message, contains('Cannot play'));
  });
}
