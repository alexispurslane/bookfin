// The page settings that this phone's reader showed its last EPUB page
// with, which the next open of a book starts its work with (boo-yjq6).
import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'epub/prepare.dart';

/// The place where [LastPageSettings] keeps its settings: one short text
/// value.
abstract interface class PageSettingsStore {
  /// The saved value, or null when none was saved.
  Future<String?> read();

  /// Replaces the saved value with [value].
  Future<void> write(String value);
}

/// The app's preferences. The platform writes each value atomically.
class LocalPageSettingsStore implements PageSettingsStore {
  final _preferences = SharedPreferencesAsync();

  @override
  Future<String?> read() => _preferences.getString(_key);

  @override
  Future<void> write(String value) => _preferences.setString(_key, value);

  static const _key = 'bookfin.page-settings.v1';
}

/// The page settings of the last EPUB page that this phone's reader
/// showed, kept between launches.
///
/// The pager of the next open book starts to prepare the section of its
/// saved place with them, before the reader's first layout presents the
/// settings, and it uses that work only when the presented settings are
/// equal (see [EpubPager]'s expected settings). The settings are derived
/// data with a store of their own: a lost or unreadable value costs one
/// open its head start.
class LastPageSettings {
  /// The settings that [store] keeps, after [restore].
  LastPageSettings(this._store);

  final PageSettingsStore _store;

  /// The settings of the last shown page, or null before the first page
  /// and before [restore] reads a kept value.
  PageSettings? get value => _value;
  PageSettings? _value;

  /// The writes in order, so that the last kept settings are written last.
  Future<void> _queue = Future.value();

  /// Reads the settings that the store keeps, once at the app's start. A
  /// page that shows before it completes wins. A value that cannot be read
  /// gives no settings, and the next kept settings replace it.
  Future<void> restore() async {
    final PageSettings? kept;
    try {
      kept = _decode(await _store.read());
    } on Object {
      return;
    }
    _value ??= kept;
  }

  /// Notes that a page shows with [settings], and keeps them when they
  /// changed. A failed write loses only a head start.
  void keep(PageSettings settings) {
    if (settings == _value) return;
    _value = settings;
    // NOTE: The value is five numbers, far less work than a hop to another
    // isolate.
    final value = jsonEncode({
      'version': 1,
      'width': settings.width,
      'height': settings.height,
      'fontSize': settings.fontSize,
      'night': settings.night,
      'sizesMainText': settings.sizesMainText,
    });
    _queue = _queue.then((_) => _store.write(value).catchError((Object _) {}));
  }

  /// The settings of a kept [value], or null for none. Throws when it is
  /// not a kept value.
  static PageSettings? _decode(String? value) {
    if (value == null) return null;
    final json = jsonDecode(value);
    if (json is! Map ||
        json['version'] != 1 ||
        json['width'] is! num ||
        json['height'] is! num ||
        json['fontSize'] is! num ||
        json['night'] is! bool ||
        json['sizesMainText'] is! bool) {
      throw const FormatException('These are not kept page settings.');
    }
    bool positive(num value) => value > 0 && value.isFinite;
    final (width, height, fontSize) = (
      json['width'] as num,
      json['height'] as num,
      json['fontSize'] as num,
    );
    if (!positive(width) || !positive(height) || !positive(fontSize)) {
      throw const FormatException('The kept page has no page area.');
    }
    return PageSettings(
      width: width.toDouble(),
      height: height.toDouble(),
      fontSize: fontSize.toDouble(),
      night: json['night'] as bool,
      sizesMainText: json['sizesMainText'] as bool,
    );
  }
}
