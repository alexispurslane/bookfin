import 'dart:async';

import 'package:bookfin/playback/playback.dart';

import 'playback_test.dart' show TestEngine;

enum HeldCommand { load, seek, pause }

/// Holds an audio command before the decoder confirms its result.
class HeldEngine extends TestEngine {
  HeldCommand? held;
  final entered = Completer<void>();
  final released = Completer<void>();

  Future<void> _wait(HeldCommand command) async {
    if (held != command) return;
    if (!entered.isCompleted) entered.complete();
    await released.future;
  }

  void release() {
    if (!released.isCompleted) released.complete();
  }

  @override
  Future<void> load(List<Uri> sources, int fileIndex, int position) async {
    await _wait(HeldCommand.load);
    await super.load(sources, fileIndex, position);
  }

  @override
  Future<AudioSample> seek(int fileIndex, int position) async {
    await _wait(HeldCommand.seek);
    return super.seek(fileIndex, position);
  }

  @override
  Future<void> pause() async {
    await _wait(HeldCommand.pause);
    await super.pause();
  }
}
