import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';

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
class Speech {
  Speech({required this._locate, this._idle = const Duration(minutes: 2)});

  final Future<SpeechModel?> Function() _locate;
  final Duration _idle;

  /// The worker, once the model is located. Null without a model.
  late final Future<KeptWorker<_Model?>?> _worker = () async {
    final model = await _locate();
    return model == null ? null : _kept = _workerOf(model, _idle);
  }();
  KeptWorker<_Model?>? _kept;

  /// Whether the worker could not load the model.
  var _unloadable = false;

  // NOTE: The worker's closures come from static functions, so that they
  // capture only plain data and never this object, which cannot travel to
  // the worker.
  static KeptWorker<_Model?> _workerOf(SpeechModel model, Duration idle) =>
      KeptWorker(
        () => _Model.load(model),
        name: 'speech',
        idle: idle,
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
  Future<Heard?> hear(
    String path,
    int startMs,
    int lengthMs, {
    bool urgent = false,
  }) async {
    final worker = await _worker;
    if (worker == null || _unloadable) return null;
    final (:loaded, :heard) = await worker.run(
      _hearing(path, startMs, lengthMs, _threads(urgent: urgent)),
    );
    if (!loaded) {
      // The cause does not change while the app runs, so a new worker for
      // each later window would only try the same load again.
      _unloadable = true;
      unawaited(worker.close());
      return null;
    }
    return heard == null || heard.words.isEmpty ? null : heard;
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
