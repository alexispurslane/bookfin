import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'appearance.dart';

abstract interface class AppearanceStore {
  Future<String?> read();
  Future<void> write(String value);
}

class LocalAppearanceStore implements AppearanceStore {
  final _preferences = SharedPreferencesAsync();

  @override
  Future<String?> read() => _preferences.getString('bookfin.appearance.v1');

  @override
  Future<void> write(String value) =>
      _preferences.setString('bookfin.appearance.v1', value);
}

enum PreferenceSaveState { saved, saving, failed }

/// The saved appearance choice, and the theme that it gives now.
///
/// Listeners hear every change of the choice, its save state and its
/// warning. [decision] changes only when the theme changes: at a sunrise or a
/// sunset, on a new choice, or on a new platform brightness.
///
/// Invariants, checked by [checkInvariants]:
/// - A pending save has no warning, and a failed save has one.
/// - A timer for the next theme change runs only while the app is in front.
class AppearanceController extends ChangeNotifier {
  AppearanceController(this._store, {this.clock = DateTime.now});

  final AppearanceStore _store;

  /// The current instant, for sunrise and sunset.
  final DateTime Function() clock;
  AppearanceSettings _settings = const AppearanceSettings();
  PreferenceSaveState _saveState = PreferenceSaveState.saved;
  String? _warning;
  Future<void> _writes = Future.value();
  bool _disposed = false;
  Brightness _platformBrightness = Brightness.light;

  /// Whether the app is in front, so that the theme must follow the sun.
  bool _inFront = false;

  /// Fires when [decision] must be worked out again.
  Timer? _nextCheck;

  late final _decision = ValueNotifier(_resolve(clock()));

  /// The theme of the app now. It changes only when its brightness or its
  /// description changes.
  ValueListenable<AppearanceDecision> get decision => _decision;

  AppearanceSettings get settings => _settings;
  PreferenceSaveState get saveState => _saveState;
  String? get warning => _warning;

  /// Tells the controller the brightness that the phone's own appearance
  /// asks for. Automatic appearance without a location follows it.
  void platformBrightnessChanged(Brightness brightness) {
    _platformBrightness = brightness;
    _decide();
  }

  /// The app came to the front. The theme follows the sun again, and catches
  /// up at once with any sunrise or sunset that passed in the background.
  void resume() {
    _inFront = true;
    _decide();
  }

  /// The app left the front. No timer wakes the phone for the theme until
  /// [resume].
  void suspend() {
    _inFront = false;
    _nextCheck?.cancel();
    _nextCheck = null;
  }

  void checkInvariants() {
    if (!_inFront && _nextCheck != null) {
      throw StateError('Only an app in front waits for the next theme.');
    }
    if (_saveState == PreferenceSaveState.saving && _warning != null) {
      throw StateError('A pending save cannot already have a save warning.');
    }
    if (_saveState == PreferenceSaveState.failed && _warning == null) {
      throw StateError(
        'A failed save must explain that the choice is not saved.',
      );
    }
  }

  Future<void> restore() async {
    try {
      final raw = await _store.read();
      if (raw != null) _settings = _decode(raw);
    } catch (_) {
      _warning =
          'Saved appearance could not be read. Using automatic appearance.';
    }
    _decide();
    _notify();
  }

  Future<void> selectMode(AppearanceMode mode) =>
      _select(AppearanceSettings(mode: mode, location: _settings.location));

  Future<void> selectLocation(SelectedLocation? location) =>
      _select(AppearanceSettings(mode: _settings.mode, location: location));

  Future<void> _select(AppearanceSettings next) {
    _settings = next;
    _saveState = PreferenceSaveState.saving;
    _warning = null;
    _decide();
    _notify();
    _writes = _writes.then((_) async {
      try {
        await _store.write(_encode(next));
        if (identical(next, _settings)) _saveState = PreferenceSaveState.saved;
      } catch (_) {
        if (identical(next, _settings)) {
          _saveState = PreferenceSaveState.failed;
          _warning = 'Appearance not saved. Choose again to retry.';
        }
      }
      _notify();
    });
    return _writes;
  }

  AppearanceDecision _resolve(DateTime now) =>
      resolveAppearance(_settings, now, _platformBrightness);

  /// Works out the theme now, and sets a timer for its next change while the
  /// app is in front.
  void _decide() {
    if (_disposed) return;
    final now = clock();
    _decision.value = _resolve(now);
    _nextCheck?.cancel();
    _nextCheck = null;
    if (!_inFront) return;
    if (nextAppearanceCheck(_settings, now) case final next?) {
      _nextCheck = Timer(next.difference(now), _decide);
    }
  }

  void _notify() {
    assert(() {
      checkInvariants();
      return true;
    }());
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    suspend();
    _decision.dispose();
    super.dispose();
  }
}

String _encode(AppearanceSettings settings) {
  final location = settings.location;
  return jsonEncode({
    'version': 1,
    'mode': settings.mode.name,
    'location': location == null
        ? null
        : {
            'name': location.name,
            'latitude': location.latitude,
            'longitude': location.longitude,
          },
  });
}

AppearanceSettings _decode(String raw) {
  final data = jsonDecode(raw);
  if (data is! Map<String, dynamic> || data['version'] != 1) {
    throw const FormatException('Unsupported appearance record');
  }
  final mode = AppearanceMode.values
      .where((mode) => mode.name == data['mode'])
      .firstOrNull;
  if (mode == null) throw const FormatException('Unsupported appearance mode');
  final location = data['location'];
  if (location == null) return AppearanceSettings(mode: mode);
  if (location is! Map<String, dynamic> ||
      location['name'] is! String ||
      location['latitude'] is! num ||
      location['longitude'] is! num) {
    throw const FormatException('Invalid location');
  }
  return AppearanceSettings(
    mode: mode,
    location: SelectedLocation(
      location['name'] as String,
      (location['latitude'] as num).toDouble(),
      (location['longitude'] as num).toDouble(),
    ),
  );
}
