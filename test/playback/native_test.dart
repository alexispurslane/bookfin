import 'package:audio_service/audio_service.dart';
import 'package:bookfin/playback/native.dart';
import 'package:bookfin/playback/playback.dart';
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
  late TestEngine engine;
  late LocalFiles downloads;
  late PlaybackHandler handler;
  setUp(() async {
    downloads = LocalFiles();
    engine = TestEngine();
    playback = Playback(
      downloads: downloads,
      engine: engine,
      store: MemoryResume(),
    );
    await playback.bind(account(), [title]);
    await playback.open(title, recording);
    handler = PlaybackHandler()..attach(playback);
  });
  tearDown(() async {
    await playback.close();
    downloads.dispose();
  });
  test('media controls share edition seeking and recorded-time position with the visible player', () async {
    await handler.seek(const Duration(seconds: 65));
    expect(playback.position?.sourceKey, second.key);
    expect(playback.position?.milliseconds, 5000);
    expect(
      handler.playbackState.value.updatePosition,
      const Duration(seconds: 65),
    );
    expect(handler.mediaItem.value?.duration, const Duration(seconds: 150));
    await handler.pause();
    expect(playback.playing, isFalse);
    await handler.play();
    expect(playback.playing, isTrue);
  });
  test(
    'stopped media controls stay stopped when a late paused sample arrives',
    () async {
      await handler.seek(const Duration(seconds: 75));
      await handler.stop();
      engine.emit(1, 15000);
      expect(
        handler.playbackState.value.processingState,
        AudioProcessingState.idle,
      );
      expect(playback.position?.sourceKey, second.key);
      await handler.play();
      expect(
        handler.playbackState.value.processingState,
        AudioProcessingState.ready,
      );
      expect(playback.playing, isTrue);
    },
  );
  test(
    'system seek-forward and seek-backward use the same configured short jumps',
    () async {
      await playback.setJumps(15, 45);
      await handler.seek(const Duration(seconds: 30));
      await handler.seekForward(true);
      await handler.seekForward(false);
      expect(playback.editionMilliseconds, 75000);
      await handler.seekBackward(true);
      await handler.seekBackward(false);
      expect(playback.editionMilliseconds, 60000);
    },
  );
}
