import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../downloads/downloads.dart';
import '../catalog/jellyfin.dart';
import '../catalog/model.dart';
import '../catalog/store.dart';
import 'apple_audio_files.dart';
import 'playback.dart';
import 'reporting.dart';
import 'store.dart';

/// The platforms where just_audio and audio_service both have a native
/// implementation. Elsewhere Bookfin offers no listening.
const _playingPlatforms = {
  TargetPlatform.android,
  TargetPlatform.iOS,
  TargetPlatform.macOS,
};

/// [art] gives the blurred cover that the system media player draws, as
/// [PlaybackHandler.art] describes.
Future<Playback?> createPlayback(
  Downloads downloads, {
  ListeningStore? store,
  Future<Uri?> Function(JellyfinSession session, CoverRef cover)? art,
}) async {
  if (kIsWeb || !_playingPlatforms.contains(defaultTargetPlatform)) {
    return null;
  }
  final engine = LocalAudioEngine(
    // AVFoundation picks its decoder by the file extension.
    links:
        defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS
        ? Directory('${Directory.systemTemp.path}/bookfin-audio')
        : null,
  );
  final handler = await AudioService.init(
    builder: () => PlaybackHandler(art: art),
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
  final Directory? _links;
  final _events = StreamController<AudioSample>.broadcast(sync: true);
  final _subscriptions = <StreamSubscription<dynamic>>[];
  bool _changingPosition = false;
  AudioSample? _confirmed;

  /// Plays with [player]. With [links], it plays each file through a link
  /// in that directory whose extension names the file's audio format, as
  /// [playableAudioFile] makes it.
  LocalAudioEngine({AudioPlayer? player, this._links})
    : _player = player ?? AudioPlayer() {
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
    final links = _links;
    final playable = links == null
        ? files
        : await Future.wait(
            files.map((file) => playableAudioFile(file, links: links)),
          );
    await _player.setAudioSources(
      playable.map(AudioSource.uri).toList(),
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

/// Publishes the open book and its playback state to Android's media session,
/// which drives the notification and the lock screen.
///
/// The handler follows only Playback's selection, position and settings,
/// which hold everything that it shows. Each published value costs a
/// platform call, and the position notifies on every player tick. The
/// session projects the shown position from the last published position, its
/// update time and its speed. So a state is published only when a shown field
/// changes or when that projection drifts from the player by more than
/// [_drift]: after a seek, a jump, a stall or a restore.
class PlaybackHandler extends BaseAudioHandler {
  PlaybackHandler({this.art});

  /// Gives the file of [cover]'s blurred copy, which the system media player
  /// draws behind the book, or null when there is none. The handler asks once
  /// for each book that opens, and shows the book at once, without art, until
  /// the file arrives.
  final Future<Uri?> Function(JellyfinSession session, CoverRef cover)? art;
  static const _drift = Duration(seconds: 1);
  Playback? _playback;
  Listenable? _changes;
  ({
    String id,
    String title,
    String artist,
    String album,
    int? duration,
    CoverRef? cover,
  })?
  _shown;

  /// The blurred cover of the shown book, once [art] gives it.
  Uri? _art;

  void attach(Playback playback) {
    _changes?.removeListener(_publish);
    _playback = playback;
    _changes = Listenable.merge([
      playback.selectionNotifier,
      playback.positionNotifier,
      playback.settingsNotifier,
    ])..addListener(_publish);
    _publish();
  }

  void _publish() {
    final playback = _playback!;
    final book = playback.book;
    final shown = book == null
        ? null
        : (
            id: playback.edition!.id,
            title: book.title,
            artist: book.author,
            album: playback.edition!.label,
            duration: playback.durationMilliseconds,
            cover: book.cover,
          );
    if (shown != _shown) {
      final cover = shown?.cover;
      final session = playback.session;
      if (cover != _shown?.cover) {
        _art = null;
        if (art != null && cover != null && session != null) {
          unawaited(
            art!(session, cover).then((file) {
              if (file == null || _shown?.cover != cover) return;
              _art = file;
              _publishItem();
            }),
          );
        }
      }
      _shown = shown;
      _publishItem();
    }
    final next = PlaybackState(
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
    );
    final last = playbackState.value;
    if (next.playing == last.playing &&
        next.processingState == last.processingState &&
        next.speed == last.speed &&
        listEquals(next.controls, last.controls) &&
        (next.updatePosition - last.position).abs() <= _drift) {
      return;
    }
    playbackState.add(next);
  }

  void _publishItem() {
    final shown = _shown;
    mediaItem.add(
      shown == null
          ? null
          : MediaItem(
              id: shown.id,
              title: shown.title,
              artist: shown.artist,
              album: shown.album,
              duration: shown.duration == null
                  ? null
                  : Duration(milliseconds: shown.duration!),
              artUri: _art,
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
