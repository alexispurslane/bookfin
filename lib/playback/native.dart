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

Future<Playback?> createPlayback(
  Downloads downloads, {
  ListeningStore? store,
}) async {
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
    store: store ?? LocalResumeStore(),
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
  final AudioPlayer _player;
  final _events = StreamController<AudioSample>.broadcast(sync: true);
  final _subscriptions = <StreamSubscription<dynamic>>[];
  bool _changingPosition = false;
  AudioSample? _confirmed;
  LocalAudioEngine({AudioPlayer? player}) : _player = player ?? AudioPlayer() {
    _subscriptions.add(_player.playerStateStream.listen((_) => _publish()));
    _subscriptions.add(_player.currentIndexStream.listen((_) => _publish()));
    _subscriptions.add(_player.positionStream.listen((_) => _publish()));
    _subscriptions.add(_player.errorStream.listen(_events.addError));
  }
  AudioSample? _confirmPosition({bool settledSeek = false}) {
    final event = _player.playbackEvent;
    if (event.processingState == ProcessingState.loading ||
        (event.processingState == ProcessingState.idle && !settledSeek)) {
      return null;
    }
    return _confirmed = AudioSample(
      event.currentIndex ?? 0,
      _player.position.inMilliseconds,
      playing: _player.playing,
      completed: event.processingState == ProcessingState.completed,
    );
  }

  void _publish({bool settledSeek = false}) {
    if (_events.isClosed || _changingPosition) return;
    final sample = _confirmPosition(settledSeek: settledSeek);
    if (sample != null) _events.add(sample);
  }

  @override
  Stream<AudioSample> get samples => _events.stream;
  @override
  Future<void> load(List<Uri> files, int fileIndex, int milliseconds) async {
    if (files.isEmpty || files.any((file) => file.scheme != 'file')) {
      throw ArgumentError('Only verified local audio is supported.');
    }
    _confirmed = null;
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
  // just_audio.pause returns early during an interruption. stop also clears
  // pending interruption recovery while retaining the selected sources.
  Future<void> pause() async {
    final confirmed = _confirmPosition() ?? _confirmed;
    _changingPosition = true;
    try {
      await _player.stop();
      // Decoder release can expose a placeholder position. Restore the same
      // confirmed source and time before a later Play reactivates it.
      if (confirmed != null &&
          (_player.playbackEvent.currentIndex != confirmed.fileIndex ||
              _player.position.inMilliseconds != confirmed.milliseconds)) {
        await _player.seek(
          Duration(milliseconds: confirmed.milliseconds),
          index: confirmed.fileIndex,
        );
      }
    } finally {
      _changingPosition = false;
    }
    if (confirmed != null && !_events.isClosed) {
      final paused = AudioSample(
        confirmed.fileIndex,
        confirmed.milliseconds,
        playing: false,
        completed: confirmed.completed,
      );
      _confirmed = paused;
      _events.add(paused);
    }
  }

  @override
  Future<AudioSample> seek(int fileIndex, int milliseconds) async {
    _changingPosition = true;
    try {
      await _player.seek(
        Duration(milliseconds: milliseconds),
        index: fileIndex,
      );
    } finally {
      _changingPosition = false;
    }
    final confirmed = _confirmPosition(settledSeek: true);
    if (confirmed == null) {
      throw Exception('The decoder did not confirm the seek.');
    }
    if (!_events.isClosed) _events.add(confirmed);
    return confirmed;
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
