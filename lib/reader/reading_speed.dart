// How fast the person on this phone reads, which the reader turns into the
// time left in the chapter and in the book (boo-02sx).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The place where [ReadingSpeed] keeps its counted pages: one short text
/// value.
abstract interface class ReadingSpeedStore {
  /// The saved value, or null when none was saved.
  Future<String?> read();

  /// Replaces the saved value with [value].
  Future<void> write(String value);
}

/// The app's preferences, which keep the speed apart from the record
/// database that holds reading places, bookmarks and listening history. The
/// platform writes each value atomically: Android's DataStore writes a new
/// file and renames it, and Apple's user defaults do the same.
class LocalReadingSpeedStore implements ReadingSpeedStore {
  final _preferences = SharedPreferencesAsync();

  @override
  Future<String?> read() => _preferences.getString(_key);

  @override
  Future<void> write(String value) => _preferences.setString(_key, value);

  static const _key = 'bookfin.reading-speed.v1';
}

/// How fast the person on this phone reads, in visible characters per
/// minute, white space left out, as the reader counts characters. A count
/// of characters, unlike a count of pages, does not change with the text
/// size or the book.
///
/// The speed belongs to the reader, not to one book: it is the median speed
/// of the latest [window] counted pages, in any book. A person mostly reads
/// one book at a time, so the window moves to the speed of a new book
/// within about [window] / 2 pages. Before that, the speed of the last
/// books is a better guess than nothing, and a separate speed for each book
/// would show nothing at the start of every book.
///
/// A page counts when the person turned forward from it ([pageShown]) and
/// it held at least [_fewest] visible characters, so a picture or a
/// chapter title, where a person looks rather than reads, does not count.
/// Its speed must also lie between [_slowest] and [_fastest]: a faster
/// page was flipped or skimmed, and a slower one held a pause, such as the
/// phone put down. The median leaves out the shorter pauses that remain.
///
/// The speed is derived data. It has a store of its own, which knows
/// nothing of reading places or history, so a lost or unreadable speed
/// costs only the speed: the next counted pages build it again.
class ReadingSpeed {
  /// The speed of the pages that [store] keeps, after [restore]. [clock]
  /// gives the current time.
  ReadingSpeed(this._store, {this._clock = DateTime.now});

  final ReadingSpeedStore _store;
  final DateTime Function() _clock;

  /// The number of latest counted pages that the speed follows.
  static const window = 40;

  /// The number of counted pages before a speed shows, and between two
  /// changes of the shown speed.
  static const enough = 5;

  /// The fewest visible characters of a page that counts.
  static const _fewest = 250;

  /// The slowest and the fastest speed of a page that counts, in visible
  /// characters per minute. A slow reader of English reads about 600, a
  /// fast one about 2500, and Chinese or Japanese runs about 300 to 600.
  static const _slowest = 100.0;
  static const _fastest = 4000.0;

  /// The speed of each counted page, the latest last, at most [window].
  final _pages = <double>[];

  /// When the shown page showed, or null before the first page.
  DateTime? _shownAt;

  /// The pages counted since the shown speed last changed.
  var _sinceShown = 0;

  /// The reading speed, or null before [enough] pages count. It changes
  /// once [enough] pages count, and then after every [enough] more, so an
  /// estimate built on it does not move on every page.
  ValueListenable<double?> get charactersPerMinute => _shown;
  final _shown = ValueNotifier<double?>(null);

  /// Completes when the counted pages are written, or the write failed. A
  /// failed write loses nothing that the next write does not carry.
  Future<void> get saved => _queue;
  Future<void> _queue = Future.value();

  /// Reads the counted pages that the store keeps, once at the app's start.
  /// Pages that counted before it completes come after them. A value that
  /// cannot be read is left until the next counted page replaces it.
  Future<void> restore() => _queue = _queue.then((_) async {
    final List<double> kept;
    try {
      kept = _decode(await _store.read());
    } on Object {
      return;
    }
    _pages.insertAll(0, kept);
    if (_pages.length > window) _pages.removeRange(0, _pages.length - window);
    if (_pages.length >= enough) _show();
  });

  /// Notes that a new page shows. [read] is the number of visible
  /// characters of the page before, when the person turned forward from
  /// it, and null after any other move: an opening, a jump, a turn back or
  /// new page settings. The time on a page runs from when it showed.
  void pageShown({int? read}) {
    final now = _clock();
    final since = _shownAt;
    _shownAt = now;
    if (read == null || since == null || read < _fewest) return;
    final minutes =
        now.difference(since).inMicroseconds / Duration.microsecondsPerMinute;
    final speed = minutes > 0 ? read / minutes : double.infinity;
    if (speed < _slowest || speed > _fastest) return;
    _pages.add(speed);
    if (_pages.length > window) _pages.removeAt(0);
    if (++_sinceShown >= enough && _pages.length >= enough) _show();
    // NOTE: The value holds at most [window] numbers, far less work than a
    // hop to another isolate.
    _queue = _queue.then(
      (_) => _store
          .write(jsonEncode({'version': 1, 'pages': _pages}))
          .catchError((Object _) {}),
    );
  }

  void dispose() => _shown.dispose();

  /// Shows the median speed of the counted pages.
  void _show() {
    _sinceShown = 0;
    final sorted = List.of(_pages)..sort();
    final middle = sorted.length ~/ 2;
    _shown.value = sorted.length.isOdd
        ? sorted[middle]
        : (sorted[middle - 1] + sorted[middle]) / 2;
  }

  /// The page speeds of a saved [value]. Throws when it is not one.
  static List<double> _decode(String? value) {
    if (value == null) return const [];
    final json = jsonDecode(value);
    if (json is! Map || json['version'] != 1 || json['pages'] is! List) {
      throw const FormatException('This is not a saved reading speed.');
    }
    return [
      for (final page in json['pages'] as List)
        if (page is num && page >= _slowest && page <= _fastest)
          page.toDouble()
        else
          throw const FormatException('A page speed is not a number.'),
    ];
  }
}
