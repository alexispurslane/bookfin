import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../catalog/jellyfin.dart';
import '../catalog/model.dart';
import '../downloads/downloads.dart';
import 'reporting.dart';

class AudioSample {
  const AudioSample(
    this.fileIndex,
    this.milliseconds, {
    this.playing = false,
    this.completed = false,
  });
  final int fileIndex;
  final int milliseconds;
  final bool playing;
  final bool completed;
}

abstract class AudioEngine {
  Stream<AudioSample> get samples;
  Future<void> load(List<Uri> files, int fileIndex, int milliseconds);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(int fileIndex, int milliseconds);
  Future<void> speed(double value);
  Future<void> close();
}

abstract class ResumeStore {
  Future<Map<String, dynamic>?> read(String accountKey);
  Future<void> write(String accountKey, Map<String, dynamic> value);
}

class Playback extends ChangeNotifier {
  Playback({
    required this.downloads,
    required this.engine,
    required this.store,
    this.reports,
  }) {
    _samples = engine.samples.listen(
      _accept,
      onError: (Object error) {
        unawaited(_enqueue(_audioFailed));
      },
    );
  }
  final Downloads downloads;
  final AudioEngine engine;
  final ResumeStore store;
  final LiveReports? reports;
  late final StreamSubscription<AudioSample> _samples;
  JellyfinSession? _session;
  List<Book> _books = [];
  Book? _book;
  Edition? _edition;
  AudioPosition? _position;
  bool _playing = false;
  bool _active = false;
  bool _closed = false;
  bool _loading = false;
  bool _restored = false;
  String? _message;
  double _speed = 1;
  int _backward = 10;
  int _forward = 30;
  int _generation = 0;
  Map<String, dynamic> _resumes = {};
  String? _selected;
  Timer? _sleep;
  DateTime? _sleepDeadline;
  Future<void> _operations = Future.value();
  Future<void> _writes = Future.value();
  Future<void> _binding = Future.value();

  Book? get book => _book;
  Edition? get edition => _edition;
  AudioPosition? get position => _position;
  bool get playing => _playing;
  bool get active => _active;
  bool get pendingOfflineResume =>
      _resumes[_edition?.id]?['pendingOffline'] == true;
  String? get message => _message;
  double get playbackSpeed => _speed;
  int get backwardSeconds => _backward;
  int get forwardSeconds => _forward;
  DateTime? get sleepDeadline => _sleepDeadline;

  int? get durationMilliseconds {
    final files = _edition?.files;
    if (files == null || files.any((file) => file.durationMs == null)) {
      return null;
    }
    return files.fold<int>(0, (total, file) => total + file.durationMs!);
  }

  int? get editionMilliseconds {
    final position = _position;
    if (position == null) return null;
    var total = 0;
    for (final file in _edition!.files) {
      if (file.key == position.sourceKey) return total + position.milliseconds;
      if (file.durationMs == null) return null;
      total += file.durationMs!;
    }
    return null;
  }

  List<PlaybackChapter> get chapters => [
    for (final file in _edition?.files ?? <SourceFile>[]) ...[
      if (!file.chapters.any((chapter) => chapter.startMs == 0))
        PlaybackChapter(file.displayName, file.key, 0),
      for (final chapter in file.chapters)
        if (chapter.startMs >= 0 &&
            (file.durationMs == null || chapter.startMs < file.durationMs!))
          PlaybackChapter(chapter.name, file.key, chapter.startMs),
    ],
  ];

  Future<void> _enqueue(Future<void> Function() action) {
    final generation = _generation;
    final binding = _binding;
    final operation = _operations
        .then<void>((_) async {
          await binding;
          if (!_closed && generation == _generation) await action();
        })
        .onError<Exception>((error, stack) => _audioFailed());
    _operations = operation.onError<ArgumentError>((error, stack) {});
    return operation;
  }

  Future<void> _audioFailed() async {
    _message = 'Cannot play this local audio file. Download it again or choose another edition.';
    try {
      await engine.pause();
    } on Exception {
      _message =
          'The audio device failed. Restart Bookfin before listening again.';
    }
    _playing = false;
    _active = false;
    reports?.stop();
    _save();
    _notify();
  }

  Future<void> bind(JellyfinSession? session, List<Book> books) async {
    if (_closed) return;
    final changed = _session?.scope.key != session?.scope.key;
    _books = books;
    if (!changed) {
      _session = session;
      if (_edition != null) {
        final current = books
            .expand((book) => book.editions)
            .where((edition) => edition.id == _edition!.id)
            .firstOrNull;
        if (current == null ||
            _position?.fits(current) != true ||
            current.files
                    .map((file) => '${file.key}:${file.revision}')
                    .join('|') !=
                _edition!.files
                    .map((file) => '${file.key}:${file.revision}')
                    .join('|')) {
          await bind(null, []);
          await bind(session, books);
        } else {
          _edition = current;
          _book = books.firstWhere((book) => book.editions.contains(current));
          _notify();
        }
      }
      await _binding;
      return;
    }
    _save();
    reports?.stop();
    final generation = ++_generation;
    _session = session;
    _restored = false;
    _book = null;
    _edition = null;
    _position = null;
    _playing = false;
    _active = false;
    _resumes = {};
    _selected = null;
    _speed = 1;
    _backward = 10;
    _forward = 30;
    _message = null;
    _cancelSleep();
    _notify();
    final previousBinding = _binding;
    final previousOperations = _operations;
    final ready = Completer<void>();
    _binding = ready.future;
    try {
      await previousBinding;
      await previousOperations;
      await engine.pause();
      await _writes;
      if (session == null || generation != _generation) return;
      try {
        final saved = await store.read(session.scope.key);
        if (generation != _generation) return;
        if (saved != null && saved['version'] != 1) {
          throw const FormatException('Unsupported listening record');
        }
        if (saved != null) {
          _resumes = Map<String, dynamic>.from(saved['resumes'] as Map? ?? {});
          _selected = saved['selected'] as String?;
          final speed = (saved['speed'] as num?)?.toDouble() ?? 1;
          if (speed.isFinite && speed >= 0.5 && speed <= 3) _speed = speed;
          final backward = saved['backward'] as int? ?? 10;
          final forward = saved['forward'] as int? ?? 30;
          if (backward > 0 && backward <= 300) _backward = backward;
          if (forward > 0 && forward <= 300) _forward = forward;
        }
        _restored = true;
        final book = _books
            .where(
              (book) => book.editions.any((edition) => edition.id == _selected),
            )
            .firstOrNull;
        final edition = book?.editions
            .where((edition) => edition.id == _selected)
            .firstOrNull;
        if (book != null && edition != null) {
          final resume = _readPosition(edition.id);
          if (resume == null || !resume.fits(edition)) {
            _message = 'The saved audio source changed. Its resume is kept but was not applied.';
          } else {
            await _open(book, edition, autoplay: false);
          }
        }
      } on Exception {
        _message = 'Cannot restore listening position. Saved listening data was not removed.';
      } on TypeError {
        _message = 'Cannot restore listening position. Saved listening data was not removed.';
      }
      _notify();
    } finally {
      ready.complete();
    }
  }

  AudioPosition? _readPosition(String editionId) {
    final value = _resumes[editionId];
    if (value is! Map) return null;
    if (value['source'] is! String ||
        value['revision'] is! String ||
        value['milliseconds'] is! int) {
      return null;
    }
    return AudioPosition(
      editionId: editionId,
      sourceKey: value['source'] as String,
      revision: value['revision'] as String,
      milliseconds: value['milliseconds'] as int,
    );
  }

  Future<void> open(Book book, Edition edition, {bool autoplay = true}) =>
      _enqueue(() => _open(book, edition, autoplay: autoplay));

  Future<void> _open(
    Book book,
    Edition edition, {
    required bool autoplay,
  }) async {
    if (_session == null ||
        !_books.any(
          (candidate) =>
              candidate.id == book.id && candidate.editions.contains(edition),
        ) ||
        edition.kind != EditionKind.audio ||
        edition.files.isEmpty) {
      throw ArgumentError('Choose an audio edition from the current account.');
    }
    final generation = _generation;
    final files = <Uri>[];
    for (final file in edition.files) {
      final uri = await downloads.localFile(file);
      if (generation != _generation) return;
      if (uri == null || uri.scheme != 'file') {
        _message =
            'Download every file in this audio edition before listening.';
        _notify();
        return;
      }
      files.add(uri);
    }
    final resume = _readPosition(edition.id);
    if (resume != null && !resume.fits(edition)) {
      _message = 'The saved audio source changed. Its resume is kept but was not applied.';
      _notify();
      return;
    }
    _loading = true;
    try {
      await engine.pause();
      _save();
      reports?.stop();
      final fileIndex = resume == null
          ? 0
          : edition.files.indexWhere((file) => file.key == resume.sourceKey);
      await engine.load(files, fileIndex, resume?.milliseconds ?? 0);
      await engine.speed(_speed);
      if (generation != _generation) {
        await engine.pause();
        return;
      }
      _book = book;
      _edition = edition;
      _selected = edition.id;
      _playing = false;
      _active = autoplay;
      _position = AudioPosition(
        editionId: edition.id,
        sourceKey: edition.files[fileIndex].key,
        revision: edition.files[fileIndex].revision,
        milliseconds: resume?.milliseconds ?? 0,
      );
      _message = null;
      _cancelSleep();
    } finally {
      _loading = false;
    }
    _save();
    _notify();
    if (autoplay) await engine.play();
  }

  void _accept(AudioSample sample) {
    if (_closed ||
        _loading ||
        _edition == null ||
        sample.fileIndex < 0 ||
        sample.fileIndex >= _edition!.files.length) {
      return;
    }
    final file = _edition!.files[sample.fileIndex];
    final milliseconds = file.durationMs == null
        ? max(0, sample.milliseconds)
        : sample.milliseconds.clamp(0, file.durationMs!);
    final previous = _position;
    final wasPlaying = _playing;
    _position = AudioPosition(
      editionId: _edition!.id,
      sourceKey: file.key,
      revision: file.revision,
      milliseconds: milliseconds,
    );
    _playing = _active && sample.playing && !sample.completed;
    reports?.observe(
      _session!,
      file,
      milliseconds,
      playing: _playing,
      speed: _speed,
      completed: sample.completed,
    );
    if (previous?.sourceKey != file.key ||
        previous!.milliseconds ~/ 1000 != milliseconds ~/ 1000 ||
        wasPlaying != _playing) {
      _save();
    }
    if (sample.completed && _active) {
      _active = false;
      _cancelSleep();
      unawaited(_enqueue(engine.pause));
    }
    _notify();
  }

  Future<void> play() => _enqueue(() async {
    if (_edition == null) return;
    final generation = _generation;
    for (final file in _edition!.files) {
      final local = await downloads.localFile(file);
      if (generation != _generation) return;
      if (local == null) {
        _message =
            'Download every file in this audio edition before listening.';
        _notify();
        return;
      }
    }
    if (durationMilliseconds != null &&
        editionMilliseconds == durationMilliseconds) {
      await engine.seek(0, 0);
    }
    _active = true;
    await engine.play();
  });

  Future<void> pause() => _enqueue(() async {
    await engine.pause();
    _playing = false;
    _save();
    await _writes;
    _notify();
  });

  Future<void> stop() => _enqueue(() async {
    await engine.pause();
    _playing = false;
    _active = false;
    _cancelSleep();
    reports?.stop();
    _save();
    await _writes;
    _notify();
  });

  Future<void> seekEdition(int milliseconds) =>
      _enqueue(() => _seekEdition(milliseconds));

  Future<void> _seekEdition(int milliseconds) async {
    if (_edition == null) return;
    final duration = durationMilliseconds;
    if (duration == null) {
      _message =
          'Choose a chapter or file. The recording length is not available.';
      _notify();
      return;
    }
    var remaining = milliseconds.clamp(0, duration);
    for (var index = 0; index < _edition!.files.length; index++) {
      final length = _edition!.files[index].durationMs!;
      if (remaining < length || index == _edition!.files.length - 1) {
        await engine.seek(index, remaining);
        _save();
        return;
      }
      remaining -= length;
    }
  }

  Future<void> seekSource(String sourceKey, int milliseconds) =>
      _enqueue(() => _seekSource(sourceKey, milliseconds));

  Future<void> _seekSource(String sourceKey, int milliseconds) async {
    if (_edition == null) return;
    final index = _edition!.files.indexWhere((file) => file.key == sourceKey);
    if (index < 0 || milliseconds < 0) {
      throw ArgumentError('Choose a chapter in this edition.');
    }
    final duration = _edition!.files[index].durationMs;
    await engine.seek(
      index,
      duration == null ? milliseconds : milliseconds.clamp(0, duration),
    );
    _save();
  }

  Future<void> jump({required bool forward}) => _enqueue(() async {
    final current = editionMilliseconds;
    final amount = (forward ? _forward : -_backward) * 1000;
    if (current != null && durationMilliseconds != null) {
      await _seekEdition(current + amount);
    } else if (_position != null) {
      await _seekSource(
        _position!.sourceKey,
        max(0, _position!.milliseconds + amount),
      );
    }
  });

  Future<void> setSpeed(double value) => _enqueue(() async {
    if (!value.isFinite || value < 0.5 || value > 3) {
      throw ArgumentError('Playback speed must be between 0.5 and 3.');
    }
    await engine.speed(value);
    _speed = value;
    _save();
    _notify();
  });

  Future<void> setJumps(int backward, int forward) => _enqueue(() async {
    if (backward < 1 || forward < 1 || backward > 300 || forward > 300) {
      throw ArgumentError('Short jumps must be between 1 and 300 seconds.');
    }
    _backward = backward;
    _forward = forward;
    _save();
    _notify();
  });

  Future<void> setSleep(Duration? duration) => _enqueue(() async {
    if (duration != null && duration <= Duration.zero) {
      throw ArgumentError('Choose a future sleep time.');
    }
    _cancelSleep();
    if (duration != null) {
      _sleepDeadline = DateTime.now().add(duration);
      _sleep = Timer(duration, () {
        _cancelSleep();
        unawaited(pause());
      });
    }
    _notify();
  });

  void _cancelSleep() {
    _sleep?.cancel();
    _sleep = null;
    _sleepDeadline = null;
  }

  void _save() {
    final accountKey = _session?.scope.key;
    if (accountKey == null || !_restored) return;
    final position = _position;
    if (position != null) {
      _resumes[position.editionId] = {
        'source': position.sourceKey,
        'revision': position.revision,
        'milliseconds': position.milliseconds,
        'pendingOffline':
            pendingOfflineResume ||
            downloads.policy.network == MediaNetwork.disconnected ||
            downloads.policy.network == MediaNetwork.unknown,
      };
    }
    final value = <String, dynamic>{
      'version': 1,
      'selected': _selected,
      'resumes': Map<String, dynamic>.from(_resumes),
      'speed': _speed,
      'backward': _backward,
      'forward': _forward,
    };
    _writes = _writes.then((_) async {
      try {
        await store.write(accountKey, value);
      } catch (_) {
        if (_session?.scope.key == accountKey) {
          _message = 'Listening position could not be saved. Free storage and try again.';
          _notify();
        }
      }
    });
  }

  Future<void> flush() async {
    final generation = _generation;
    await _binding;
    await _operations;
    if (generation != _generation) return;
    _save();
    await _writes;
    await reports?.idle;
  }

  Future<void> close() async {
    if (_closed) return;
    await stop();
    reports?.stop();
    await reports?.idle;
    reports?.close();
    _closed = true;
    _cancelSleep();
    await _samples.cancel();
    await engine.close();
    super.dispose();
  }

  void _notify() {
    if (!_closed) notifyListeners();
  }

  void checkInvariants() {
    if ((_edition == null) != (_position == null) ||
        (_edition == null) != (_book == null) ||
        _playing && _position == null ||
        _position != null &&
            (!_edition!.files.any((file) => file.key == _position!.sourceKey) ||
                _session == null)) {
      throw StateError(
        'Playback selection, source position, and account must agree.',
      );
    }
  }
}

class PlaybackChapter {
  const PlaybackChapter(this.name, this.sourceKey, this.milliseconds);
  final String name;
  final String sourceKey;
  final int milliseconds;
}
