import 'dart:ffi';
import 'dart:io';
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
}
