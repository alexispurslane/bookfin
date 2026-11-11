// Tool code for the boo-snng speech prototype, not part of Bookfin.
// Dart FFI to libspeech_probe (native/speech_probe.c), which wraps
// whisper.cpp on the CPU.
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'text.dart';

typedef _InitC = Pointer<Void> Function(Pointer<Utf8>, Int32);
typedef _Init = Pointer<Void> Function(Pointer<Utf8>, int);
typedef _FreeC = Void Function(Pointer<Void>);
typedef _Free = void Function(Pointer<Void>);
typedef _CpuC = Long Function();
typedef _Cpu = int Function();
typedef _TranscribeC = Int32 Function(
    Pointer<Void>, Pointer<Float>, Int32, Int32, Int32, Pointer<Utf8>, Int32);
typedef _Transcribe = int Function(
    Pointer<Void>, Pointer<Float>, int, int, int, Pointer<Utf8>, int);

/// The CPU time of this process so far, in milliseconds.
int cpuMs(DynamicLibrary library) =>
    library.lookupFunction<_CpuC, _Cpu>('sp_cpu_ms')();

/// The library at [path], or the Android one by its file name.
DynamicLibrary openProbe([String? path]) => DynamicLibrary.open(
    path ?? (Platform.isAndroid ? 'libspeech_probe.so' : 'libspeech_probe.dylib'));

/// One loaded whisper model.
class Whisper {
  Whisper._(this.library, this._context);

  /// Loads the model at [model]. Throws when whisper cannot load it.
  factory Whisper.open(DynamicLibrary library, String model, {bool flash = true}) {
    final path = model.toNativeUtf8();
    try {
      final context = library.lookupFunction<_InitC, _Init>('sp_init')(path, flash ? 1 : 0);
      if (context == nullptr) throw StateError('whisper could not load $model');
      return Whisper._(library, context);
    } finally {
      malloc.free(path);
    }
  }

  final DynamicLibrary library;
  final Pointer<Void> _context;
  late final _transcribe =
      library.lookupFunction<_TranscribeC, _Transcribe>('sp_transcribe');

  /// The words of [pcm], 16 kHz mono samples, with [threads] threads and
  /// an encoder context of [audioCtx] frames of 20 ms (0: the full 30 s).
  Heard transcribe(Float32List pcm, {int threads = 4, int audioCtx = 0}) {
    final samples = malloc<Float>(pcm.length);
    const cap = 1 << 16;
    final out = malloc<Uint8>(cap);
    try {
      samples.asTypedList(pcm.length).setAll(0, pcm);
      final used = _transcribe(
          _context, samples, pcm.length, threads, audioCtx, out.cast(), cap);
      if (used < 0) throw StateError('whisper failed: $used');
      // A token can end inside a character of several bytes.
      return Heard.fromTokens(
          utf8.decode(out.asTypedList(used), allowMalformed: true));
    } finally {
      malloc.free(samples);
      malloc.free(out);
    }
  }

  void close() =>
      library.lookupFunction<_FreeC, _Free>('sp_free')(_context);
}
