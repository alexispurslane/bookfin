import 'dart:async';

import 'package:bookfin/playback/playback.dart';

/// Observes an automatic change, which has no command future for a caller.
Future<void> waitForPlayback(Playback playback, bool Function() ready) async {
  final changed = Completer<void>();
  void observe() {
    if (ready() && !changed.isCompleted) changed.complete();
  }

  playback.addListener(observe);
  try {
    observe();
    await changed.future.timeout(const Duration(seconds: 5));
  } finally {
    playback.removeListener(observe);
  }
}
