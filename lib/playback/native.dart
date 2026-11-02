import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../downloads/downloads.dart';
import '../catalog/jellyfin.dart';
import '../catalog/store.dart';
import 'playback.dart';
import 'reporting.dart';
import 'store.dart';

Future<Playback?> createPlayback(Downloads downloads) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
  final engine = LocalAudioEngine();
  final handler = await AudioService.init(
    builder: PlaybackHandler.new,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'dev.bookfin.playback',
      androidNotificationChannelName: 'Bookfin listening',
      androidNotificationIcon: 'drawable/bookfin_launcher',
      androidStopForegroundOnPause: false,
    ),
  );
  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.speech());
  final deviceId = await SecureCredentialStore().deviceId();
  final playback = Playback(
    downloads: downloads,
    engine: engine,
    store: LocalResumeStore(),
    reports: LiveReports(
      downloads.policy,
      clientFactory: (session) =>
          JellyfinClient(session.scope.server, deviceId: deviceId),
    ),
  );
  handler.attach(playback);
  return playback;
}

class LocalAudioEngine implements AudioEngine {
  final _player = AudioPlayer();
  final _events = StreamController<AudioSample>.broadcast(sync: true);
  final _subscriptions = <StreamSubscription<dynamic>>[];
  LocalAudioEngine() {
    _subscriptions.add(_player.playerStateStream.listen((_) => _publish()));
    _subscriptions.add(_player.currentIndexStream.listen((_) => _publish()));
    _subscriptions.add(_player.positionStream.listen((_) => _publish()));
    _subscriptions.add(_player.errorStream.listen(_events.addError));
  }
  void _publish() {
    if (_events.isClosed) return;
    _events.add(
      AudioSample(
        _player.currentIndex ?? 0,
        _player.position.inMilliseconds,
        playing: _player.playing,
        completed: _player.processingState == ProcessingState.completed,
      ),
    );
  }

  @override
  Stream<AudioSample> get samples => _events.stream;
  @override
  Future<void> load(List<Uri> files, int fileIndex, int milliseconds) async {
    if (files.isEmpty || files.any((file) => file.scheme != 'file')) {
      throw ArgumentError('Only verified local audio is supported.');
    }
    await _player.setAudioSources(
      files.map(AudioSource.uri).toList(),
      initialIndex: fileIndex,
      initialPosition: Duration(milliseconds: milliseconds),
    );
  }

  @override
  Future<void> play() async {
    unawaited(
      _player.play().catchError((Object error) => _events.addError(error)),
    );
  }

  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> seek(int fileIndex, int milliseconds) async {
    await _player.seek(Duration(milliseconds: milliseconds), index: fileIndex);
    _publish();
  }

  @override
  Future<void> speed(double value) => _player.setSpeed(value);
  @override
  Future<void> close() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _player.dispose();
    await _events.close();
  }
}

class PlaybackHandler extends BaseAudioHandler {
  Playback? _playback;
  void attach(Playback playback) {
    _playback?.removeListener(_publish);
    _playback = playback;
    playback.addListener(_publish);
    _publish();
  }

  void _publish() {
    final playback = _playback!;
    final book = playback.book;
    mediaItem.add(
      book == null
          ? null
          : MediaItem(
              id: playback.edition!.id,
              title: book.title,
              artist: book.author,
              album: playback.edition!.label,
              duration: playback.durationMilliseconds == null
                  ? null
                  : Duration(milliseconds: playback.durationMilliseconds!),
            ),
    );
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.rewind,
          playback.playing ? MediaControl.pause : MediaControl.play,
          MediaControl.fastForward,
          MediaControl.stop,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.setSpeed,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: book == null || !playback.active
            ? AudioProcessingState.idle
            : AudioProcessingState.ready,
        playing: playback.playing,
        updatePosition: Duration(
          milliseconds:
              playback.editionMilliseconds ??
              playback.position?.milliseconds ??
              0,
        ),
        speed: playback.playbackSpeed,
      ),
    );
  }

  @override
  Future<void> play() async => _playback?.play();
  @override
  Future<void> pause() async => _playback?.pause();
  @override
  Future<void> seek(Duration position) async =>
      _playback?.seekEdition(position.inMilliseconds);
  @override
  Future<void> setSpeed(double speed) async => _playback?.setSpeed(speed);
  @override
  Future<void> rewind() async => _playback?.jump(forward: false);
  @override
  Future<void> fastForward() async => _playback?.jump(forward: true);
  @override
  Future<void> seekForward(bool begin) async {
    if (begin) await _playback?.jump(forward: true);
  }

  @override
  Future<void> seekBackward(bool begin) async {
    if (begin) await _playback?.jump(forward: false);
  }

  @override
  Future<void> stop() async {
    await _playback?.stop();
  }
}
