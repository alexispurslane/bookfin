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

class AppearanceController extends ChangeNotifier {
  AppearanceController(this._store);

  final AppearanceStore _store;
  AppearanceSettings _settings = const AppearanceSettings();
  PreferenceSaveState _saveState = PreferenceSaveState.saved;
  String? _warning;
  Future<void> _writes = Future.value();
  bool _disposed = false;

  AppearanceSettings get settings => _settings;
  PreferenceSaveState get saveState => _saveState;
  String? get warning => _warning;

  void checkInvariants() {
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
