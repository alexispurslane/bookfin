import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'heard_windows.dart' show Hear;
import 'speech.dart';

/// The speech runtime's hearing on Android, the one platform whose app
/// carries the speech model and its native library. Null elsewhere: the
/// macOS app does not bundle them yet (t2-0kl0).
Hear? createHear() =>
    Platform.isAndroid ? Speech(locate: findSpeechModel).hear : null;

/// Whether the phone allows the fill of heard windows: it is on power and
/// battery saver is off, as Android reports at each change. Off elsewhere,
/// and off when Android cannot report it.
ValueListenable<bool> watchFillAllowed() {
  final allowed = ValueNotifier(false);
  if (Platform.isAndroid) {
    const EventChannel('bookfin/power')
        .receiveBroadcastStream()
        .listen((event) {
          if (event case {
            'charging': final bool charging,
            'saver': final bool saver,
          }) {
            allowed.value = charging && !saver;
          }
        }, onError: (Object _) => allowed.value = false);
  }
  return allowed;
}
