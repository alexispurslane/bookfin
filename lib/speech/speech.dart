import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import 'native.dart';
import 'words.dart';
import 'worker.dart';

/// Where the speech model lies: its [length] bytes at [offset] of the file
/// at [path]. The APK stores the model uncompressed, so on Android the file
/// is the APK itself.
typedef SpeechModel = ({String path, int offset, int length});

/// The speech model of this build, or null when it has none: the asset of
/// the APK on Android, which the platform locates, and the model of the Nix
/// shell (BOOKFIN_SPEECH_MODEL) on a development machine, for tests.
Future<SpeechModel?> findSpeechModel() async {
  if (Platform.isAndroid) {
    try {
      final info = await const MethodChannel('bookfin/speech')
          .invokeMapMethod<String, Object?>('model');
      if (info case {
        'path': final String path,
        'offset': final int offset,
        'length': final int length,
      }) {
        return (path: path, offset: offset, length: length);
      }
    } on Exception {
      // No model: speech search falls back to matched chapters.
    }
    return null;
  }
  final path = Platform.environment['BOOKFIN_SPEECH_MODEL'];
  if (path == null) return null;
  try {
    return (path: path, offset: 0, length: await File(path).length());
  } on FileSystemException {
    return null;
  }
}

/// The app's speech runtime (docs/plans/cross-edition-places.md, "Build
/// design of S2"): it hears a window of a downloaded audio file, decoded and
/// transcribed by whisper.cpp's tiny.en model.
///
/// One worker isolate keeps the model, about 100 MB of memory while it
/// runs, and hears one window at a time, in the order of the requests. The
/// native library decodes and transcribes on a thread of its own at a low
/// priority, so the UI isolate and playback never wait for it (engine rule
/// 1). The worker starts at the first window, never before, and stops after
/// [idle] without a window, which frees the model.
///
/// A model that the worker cannot load counts as no model for the rest of
/// this run: the worker stops, and no later window loads the model again.
/// The native library gives no model when it cannot read the file, and on
/// an Android phone whose CPU lacks an instruction that the library needs
/// (native/speech/bookfin_speech.c).
///
/// A native call can hang, such as a call to a codec of the phone. A window
/// that the worker does not hear within [_windowLimit] fails with
/// [WorkerStopped], and the next window starts a new worker ([KeptWorker]
/// owns that rule). When the worker gives up under its stuck-worker rule,
/// speech is off for this run, and every later window gives null.
class Speech {
  Speech({required this._locate, this._idle = const Duration(minutes: 2)});

  final Future<SpeechModel?> Function() _locate;
  final Duration _idle;

  /// The longest time that the worker has for one window before it counts
  /// as stuck.
  ///
  /// Source: docs/plans/cross-edition-places.md, "Measurements on the
  /// emulator (t2-4ci0)". One 8 s window, decode included, took 3.1 s at
  /// the median in the background (2.1 to 18.2 s over 15 windows) and
  /// 10.3 s at the median for a tap (7.4 to 16.5 s over 6 windows), on an
  /// emulator whose host had a load near 54 on 10 cores. The limit is about
  /// ten times the slower median, and more than five times the slowest
  /// window that was measured, so a slow but healthy phone stays inside
  /// it. A limit that is too long costs only a longer wait at a rare hang.
  /// A limit that is too short makes healthy workers count as stuck. The
  /// worker then turns speech off for the run under its give-up rule, and
  /// every abandoned worker leaks its model (t2-p0cc).
  ///
  /// The first window after a start also holds the start of the worker and
  /// the load of the model. The load took 106 to 253 ms on the emulator
  /// ("Timings per step"), which is small beside the limit, so the first
  /// window has no longer limit of its own.
  ///
  /// NOTE: No phone was measured yet. Compare this value with the window
  /// times of the Pixel 8 acceptance (t2-02vi).
  static const _windowLimit = Duration(seconds: 100);

  /// The worker, once the model is located. Null without a model.
  late final Future<KeptWorker<_Model?>?> _worker = () async {
    final model = await _locate();
    return model == null ? null : _kept = _workerOf(model, _idle);
  }();
  KeptWorker<_Model?>? _kept;

  // NOTE: The worker's closures come from static functions, so that they
  // capture only plain data and never this object, which cannot travel to
  // the worker.
  static KeptWorker<_Model?> _workerOf(SpeechModel model, Duration idle) =>
      KeptWorker(
        () => _Model.load(model),
        name: 'speech',
        idle: idle,
        limit: _windowLimit,
        end: (model) => model?.close(),
      );

  /// The job of one window: whether the worker holds the model, and what
  /// the model heard.
  static ({bool loaded, Heard? heard}) Function(_Model?) _hearing(
    String path,
    int startMs,
    int lengthMs,
    int threads,
  ) =>
      (model) => (
        loaded: model != null,
        heard: model?.hear(path, startMs, lengthMs, threads: threads),
      );

  /// Whether the worker runs now and keeps the model in memory.
  bool get loaded => _kept?.running ?? false;

  /// The threads that whisper uses for a window: at most two in the
  /// background, so that half of a phone's big cores stay free, and four
  /// for a window that the person waits for. Each count leaves one core of
  /// this machine free.
  static int _threads({required bool urgent}) =>
      math.max(1, math.min(urgent ? 4 : 2, Platform.numberOfProcessors - 1));

  /// The heard words of [lengthMs] of the downloaded audio file at [path]
  /// from [startMs]. Null when the window holds no words: it lies past the
  /// file's end, it holds silence or music, the file cannot be decoded, or
  /// this build has no speech model that this phone can load. [urgent]
  /// gives the window more threads, for a person who waits for it.
  /// Gives null when speech is off for this run. Otherwise it throws
  /// [WorkerStopped] when the worker stops or does not hear the window
  /// within [_windowLimit].
  Future<Heard?> hear(
    String path,
    int startMs,
    int lengthMs, {
    bool urgent = false,
  }) async {
    final worker = await _worker;
    if (worker == null || worker.closed) return null;
    try {
      final (:loaded, :heard) = await worker.run(
        _hearing(path, startMs, lengthMs, _threads(urgent: urgent)),
      );
      if (!loaded) {
        // The cause stays the same during this run. Closing the worker
        // stops later windows from trying to load the same model again.
        if (!worker.closed) {
          unawaited(worker.close());
          debugPrint(
            'Speech is off for this run: the model could not be loaded.',
          );
        }
        return null;
      }
      return heard == null || heard.words.isEmpty ? null : heard;
    } on WorkerStopped {
      if (worker.closed) return null;
      rethrow;
    }
  }

  Future<void> close() async => (await _worker)?.close();
}

/// The loaded model in the worker isolate.
class _Model {
  _Model(this._library, this._model);
  final SpeechLibrary _library;
  final Pointer<Void> _model;

  /// The model that [model] locates, or null when this build has no speech
  /// library or the model cannot be read.
  static _Model? load(SpeechModel model) {
    final library = SpeechLibrary.open();
    final loaded = library?.loadModel(model.path, model.offset, model.length);
    return loaded == null ? null : _Model(library!, loaded);
  }

  Heard? hear(String path, int startMs, int lengthMs, {required int threads}) {
    final lines = _library.hear(
      _model,
      path,
      startMs,
      lengthMs,
      threads: threads,
    );
    return lines == null ? null : Heard.fromTokens(lines);
  }

  void close() => _library.freeModel(_model);
}
