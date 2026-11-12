import 'package:flutter/foundation.dart';

import 'heard_windows.dart' show Hear;

/// This platform carries no speech model, so it hears nothing.
Hear? createHear() => null;

/// This platform has no fill of heard windows.
ValueListenable<bool> watchFillAllowed() => ValueNotifier(false);
