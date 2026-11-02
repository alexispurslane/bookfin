import 'dart:async';

import 'package:just_audio/just_audio.dart';
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
  test(
    'native Pause retains the recorded position while releasing the decoder',
    () async {
      final decoder = TransitionDecoder();
      final audio = LocalAudioEngine(player: decoder);
      final samples = <AudioSample>[];
      final subscription = audio.samples.listen(samples.add);
      await audio.pause();
      expect(samples, isNotEmpty);
      expect(samples.every((sample) => sample.milliseconds == 90000), isTrue);
      expect(samples.last.playing, isFalse);
      await subscription.cancel();
      await audio.close();
    },
  );

  test('a paused seek publishes the confirmed position while the decoder is stopped', () async {
    final decoder = TransitionDecoder();
    decoder.event = decoder.event.copyWith(
      processingState: ProcessingState.idle,
    );
    final audio = LocalAudioEngine(player: decoder);
    final samples = <AudioSample>[];
    final subscription = audio.samples.listen(samples.add);
    await audio.seek(1, 30000);
    expect(samples, isNotEmpty);
    expect(samples.last.fileIndex, 1);
    expect(samples.last.milliseconds, 30000);
    expect(samples.last.playing, isFalse);
    await subscription.cancel();
    await audio.close();
  });

  test(
    'decoder reactivation does not publish placeholder loading positions',
    () async {
      final decoder = TransitionDecoder();
      final audio = LocalAudioEngine(player: decoder);
      final samples = <AudioSample>[];
      final subscription = audio.samples.listen(samples.add);
      for (final state in [ProcessingState.idle, ProcessingState.loading]) {
        decoder.event = PlaybackEvent(
          currentIndex: 0,
          processingState: state,
          updatePosition: Duration.zero,
        );
        decoder.states.add(PlayerState(true, state));
      }
      expect(samples, isEmpty);
      decoder.event = PlaybackEvent(
        currentIndex: 0,
        processingState: ProcessingState.ready,
        updatePosition: const Duration(seconds: 170),
      );
      decoder.states.add(PlayerState(true, ProcessingState.ready));
      expect(samples.single.milliseconds, 170000);
      await subscription.cancel();
      await audio.close();
    },
  );

  test('a cross-file seek never publishes its target time under the previous source', () async {
    final decoder = TransitionDecoder();
    final audio = LocalAudioEngine(player: decoder);
    final samples = <AudioSample>[];
    final subscription = audio.samples.listen(samples.add);
    await audio.seek(1, 30000);
    expect(samples, isNotEmpty);
    expect(samples.every((sample) => sample.fileIndex == 1), isTrue);
    expect(samples.every((sample) => sample.milliseconds == 30000), isTrue);
    await subscription.cancel();
    await audio.close();
  });

  test('native samples keep source identity with its recorded position during a file transition', () async {
    final decoder = TransitionDecoder();
    final audio = LocalAudioEngine(player: decoder);
    final samples = <AudioSample>[];
    final subscription = audio.samples.listen(samples.add);
    decoder.transition();
    expect(samples, hasLength(1));
    expect(samples.single.fileIndex, 1);
    expect(samples.single.milliseconds, 0);
    await subscription.cancel();
    await audio.close();
  });

  test(
    'owner pause cancels decoder recovery even when already interrupted',
    () async {
      final decoder = InterruptedDecoder();
      final audio = LocalAudioEngine(player: decoder);
      await audio.pause();
      decoder.endInterruption();
      expect(decoder.playing, isFalse);
      await audio.close();
    },
  );
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

class TransitionDecoder implements AudioPlayer {
  final states = StreamController<PlayerState>.broadcast(sync: true);
  PlaybackEvent event = PlaybackEvent(
    currentIndex: 0,
    processingState: ProcessingState.ready,
    updatePosition: const Duration(seconds: 90),
  );
  void transition() {
    event = PlaybackEvent(
      currentIndex: 1,
      processingState: ProcessingState.ready,
      updatePosition: Duration.zero,
    );
    states.add(PlayerState(false, ProcessingState.ready));
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {
    event = event.copyWith(updatePosition: position);
    states.add(PlayerState(false, ProcessingState.ready));
    await Future<void>.value();
    event = event.copyWith(currentIndex: index);
    states.add(PlayerState(false, ProcessingState.ready));
  }

  @override
  Future<void> stop() async {
    event = event.copyWith(updatePosition: Duration.zero);
    states.add(PlayerState(false, ProcessingState.ready));
    await Future<void>.value();
    event = event.copyWith(processingState: ProcessingState.idle);
    states.add(PlayerState(false, ProcessingState.idle));
  }

  @override
  PlaybackEvent get playbackEvent => event;
  @override
  int? get currentIndex => 0;
  @override
  Duration get position => event.updatePosition;
  @override
  bool get playing => false;
  @override
  ProcessingState get processingState => ProcessingState.ready;
  @override
  Stream<PlayerState> get playerStateStream => states.stream;
  @override
  Stream<int?> get currentIndexStream => const Stream.empty();
  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  Stream<PlayerException> get errorStream => const Stream.empty();
  @override
  Future<void> dispose() => states.close();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Models the pinned decoder's documented interruption flag: pause on an already
// paused decoder returns early; stop always revokes automatic recovery.
class InterruptedDecoder implements AudioPlayer {
  bool recover = true;
  bool active = false;
  void endInterruption() {
    if (recover) active = true;
  }

  @override
  bool get playing => active;
  @override
  PlaybackEvent get playbackEvent => PlaybackEvent(
    currentIndex: 0,
    processingState: ProcessingState.ready,
    updatePosition: Duration.zero,
  );
  @override
  Duration get position => Duration.zero;
  @override
  Stream<PlayerState> get playerStateStream => const Stream.empty();
  @override
  Stream<int?> get currentIndexStream => const Stream.empty();
  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  Stream<PlayerException> get errorStream => const Stream.empty();
  @override
  Future<void> pause() async {
    if (!active) return;
    active = false;
    recover = false;
  }

  @override
  Future<void> stop() async {
    active = false;
    recover = false;
  }

  @override
  Future<void> dispose() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
