import 'dart:ffi';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

typedef _DecodeC = Int32 Function(
  Pointer<Utf8>,
  Int32,
  Int32,
  Pointer<Float>,
  Int32,
);
typedef _Decode = int Function(Pointer<Utf8>, int, int, Pointer<Float>, int);
typedef _OpenC = Pointer<Void> Function(Pointer<Utf8>, Int64, Int64);
typedef _Open = Pointer<Void> Function(Pointer<Utf8>, int, int);
typedef _CloseC = Void Function(Pointer<Void>);
typedef _Close = void Function(Pointer<Void>);
typedef _HearC = Int32 Function(
  Pointer<Void>,
  Pointer<Utf8>,
  Int32,
  Int32,
  Int32,
  Pointer<Uint8>,
  Int32,
);
typedef _Hear = int Function(
  Pointer<Void>,
  Pointer<Utf8>,
  int,
  int,
  int,
  Pointer<Uint8>,
  int,
);

/// Bookfin's native speech library, bookfin_speech (native/speech): the
/// decoder of audio windows and whisper.cpp. Its calls block, so only the
/// speech worker isolate makes them.
class SpeechLibrary {
  SpeechLibrary._(this._library);

  /// The library of this build: bundled on Android, and the host build of
  /// the Nix shell (BOOKFIN_SPEECH_LIBRARY) in tests. Null when this build
  /// has none, as the macOS app and the web do not.
  static SpeechLibrary? open() {
    final path = Platform.isAndroid
        ? 'libbookfin_speech.so'
        : Platform.environment['BOOKFIN_SPEECH_LIBRARY'];
    if (path == null) return null;
    try {
      return SpeechLibrary._(DynamicLibrary.open(path));
    } on ArgumentError {
      return null;
    }
  }

  final DynamicLibrary _library;
  late final _decode = _library.lookupFunction<_DecodeC, _Decode>('bs_decode');

  /// The mono 16 kHz samples of [lengthMs] of the audio file at [path] from
  /// [startMs], or fewer when the file ends sooner. Null when the file
  /// cannot be read or decoded.
  Float32List? decode(String path, int startMs, int lengthMs) {
    final capacity = (lengthMs * 16 + 16000).clamp(0, 1 << 26);
    final samples = malloc<Float>(capacity);
    final nativePath = path.toNativeUtf8();
    try {
      final count = _decode(nativePath, startMs, lengthMs, samples, capacity);
      if (count < 0) return null;
      return Float32List.fromList(samples.asTypedList(count));
    } finally {
      malloc.free(nativePath);
      malloc.free(samples);
    }
  }

  late final _open = _library.lookupFunction<_OpenC, _Open>('bs_open');
  late final _close = _library.lookupFunction<_CloseC, _Close>('bs_close');
  late final _hear = _library.lookupFunction<_HearC, _Hear>('bs_hear');

  /// The whisper model in the [length] bytes at [offset] of the file at
  /// [path], or null when it cannot be read. Free it with [freeModel].
  Pointer<Void>? loadModel(String path, int offset, int length) {
    final nativePath = path.toNativeUtf8();
    try {
      final model = _open(nativePath, offset, length);
      return model == nullptr ? null : model;
    } finally {
      malloc.free(nativePath);
    }
  }

  void freeModel(Pointer<Void> model) => _close(model);

  /// Whisper's token lines for [lengthMs] of the audio file at [path] from
  /// [startMs], heard with [model] and [threads] threads at a low priority:
  /// `<start ms>\t<text>` for each text token. Empty when the window holds
  /// less than half a second of audio. Null when the file cannot be
  /// decoded or whisper fails.
  String? hear(
    Pointer<Void> model,
    String path,
    int startMs,
    int lengthMs, {
    required int threads,
  }) {
    const capacity = 1 << 16;
    final out = malloc<Uint8>(capacity);
    final nativePath = path.toNativeUtf8();
    try {
      final used = _hear(
        model,
        nativePath,
        startMs,
        lengthMs,
        threads,
        out,
        capacity,
      );
      if (used < 0) return null;
      // A token can end inside a character of several bytes.
      return utf8.decode(out.asTypedList(used), allowMalformed: true);
    } finally {
      malloc.free(nativePath);
      malloc.free(out);
    }
  }
}
