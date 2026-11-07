import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How the library tab arranges books.
enum LibraryView { grid, list }

/// How large library entries are, in both the grid and the list.
enum LibraryDensity { spacious, compact }

abstract interface class LayoutStore {
  Future<String?> read();
  Future<void> write(String value);
}

class LocalLayoutStore implements LayoutStore {
  final _preferences = SharedPreferencesAsync();
  @override
  Future<String?> read() => _preferences.getString('bookfin.library-layout.v1');
  @override
  Future<void> write(String value) =>
      _preferences.setString('bookfin.library-layout.v1', value);
}

/// The library view and density the user chose. Each change is saved.
class LibraryLayout extends ChangeNotifier {
  LibraryLayout(this._store);
  final LayoutStore _store;
  LibraryView _view = LibraryView.grid;
  LibraryDensity _density = LibraryDensity.spacious;

  /// Completes when the latest change is written.
  Future<void> saved = Future.value();

  LibraryView get view => _view;
  set view(LibraryView value) {
    if (value == _view) return;
    _view = value;
    _changed();
  }

  LibraryDensity get density => _density;
  set density(LibraryDensity value) {
    if (value == _density) return;
    _density = value;
    _changed();
  }

  Future<void> restore() async {
    try {
      final raw = await _store.read();
      if (raw == null) return;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      _view = LibraryView.values.byName(json['view'] as String);
      _density = LibraryDensity.values.byName(json['density'] as String);
    } catch (_) {
      _view = LibraryView.grid;
      _density = LibraryDensity.spacious;
    }
    notifyListeners();
  }

  void _changed() {
    notifyListeners();
    final value = jsonEncode({'view': _view.name, 'density': _density.name});
    saved = saved.then((_) => _store.write(value)).catchError((_) {});
  }
}
