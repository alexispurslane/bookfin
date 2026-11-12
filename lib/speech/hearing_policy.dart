import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../catalog/model.dart';
import '../playback/playback.dart';
import 'heard_windows.dart';

/// The decision of when the heard windows of listening are heard
/// (docs/plans/cross-edition-places.md, "When a window is heard"). It
/// follows what [Playback] publishes, its position and its records, and
/// asks [HeardWindows] for windows:
///
/// - After each [listeningMs] of listening on this phone: the 8 s heard
///   last. A report that moved more than [_stepMs] from the one before, or
///   went back, is a move, not listening.
/// - At each new move, pause or bookmark of this phone: one window centered
///   on each place that it names. A record counts as this phone's when it
///   is of the open edition and newer than [_freshMs] at its arrival. Any
///   other new record came from another device, and waits for the fill.
/// - The fill: each place that the listening timeline names and no window
///   covers, newest first, one at a time behind every other window, while
///   [mayFill] allows it: in the app, while the phone charges with battery
///   saver off. The fill starts again when [mayFill] turns on. A place that
///   heard nothing is not tried again in this run.
///
/// It hears nothing before [start], which the app calls after the first
/// useful frame.
class HearingPolicy {
  HearingPolicy({
    required this._playback,
    required this._heard,
    required this._mayFill,
  });

  final Playback _playback;
  final HeardWindows _heard;

  /// Whether the fill may hear a window now.
  final ValueListenable<bool> _mayFill;

  /// The listening between two windows of listening: 5 minutes, as the
  /// user decided ("Decision on speech search", item 2).
  static const listeningMs = 300000;

  /// The longest step between two decoder reports that still counts as
  /// listening. Reports come about once a second, and at a speed of 3 a
  /// second moves 3 s.
  static const _stepMs = 5000;

  /// How old a new record can be at its arrival and still count as this
  /// phone's.
  static const _freshMs = 60000;

  var _started = false;
  var _disposed = false;
  AudioPosition? _last;
  var _listened = 0;

  /// The ids of the records that were seen, so that only new ones count.
  final _seen = <String>{};

  /// The fill places that heard nothing in this run.
  final _tried = <String>{};
  var _filling = false;

  /// Starts to follow playback. The records that exist now wait for the
  /// fill.
  void start() {
    if (_started || _disposed) return;
    _started = true;
    _seen.addAll([
      for (final event in _playback.history) event.id,
      for (final bookmark in _playback.bookmarks) bookmark.id,
    ]);
    _last = _playback.position;
    _playback.positionNotifier.addListener(_moved);
    _playback.recordsNotifier.addListener(_recorded);
    _mayFill.addListener(recheck);
    recheck();
  }

  /// Tries the fill again, such as after a new record.
  void recheck() {
    if (_started && !_disposed && !_filling) unawaited(_fill());
  }

  void _moved() {
    final position = _playback.position;
    final last = _last;
    _last = position;
    if (position == null || last == null || !_playback.playing) return;
    if (position.editionId != last.editionId ||
        position.sourceKey != last.sourceKey) {
      return;
    }
    final step = position.milliseconds - last.milliseconds;
    if (step <= 0 || step > _stepMs) return;
    _listened += step;
    if (_listened < listeningMs) return;
    _listened = 0;
    final edition = _playback.edition;
    if (edition == null || edition.id != position.editionId) return;
    // The window ends at the place, so it holds the 8 s heard last.
    _heard.hearSoon(edition, _shifted(position, -HeardWindows.windowMs ~/ 2));
  }

  void _recorded() {
    final edition = _playback.edition;
    final now = DateTime.now().toUtc();
    bool fresh(DateTime at) => now.difference(at).inMilliseconds < _freshMs;
    final places = <AudioPosition>[];
    for (final event in _playback.history) {
      if (!_seen.add(event.id)) continue;
      if (edition == null || event.after.editionId != edition.id) continue;
      if (!fresh(event.at)) continue;
      places.add(event.after);
      if (event.moved) places.add(event.before);
    }
    for (final bookmark in _playback.bookmarks) {
      if (!_seen.add(bookmark.id)) continue;
      if (edition == null || bookmark.position.editionId != edition.id) {
        continue;
      }
      if (fresh(bookmark.createdAt)) places.add(bookmark.position);
    }
    for (final place in places) {
      if (place.fits(edition!)) _heard.hearSoon(edition, place);
    }
    recheck();
  }

  /// Hears the newest place without a window, one at a time, while the fill
  /// is allowed.
  Future<void> _fill() async {
    _filling = true;
    try {
      while (!_disposed && _mayFill.value) {
        final next = await _nextFill();
        if (next == null || _disposed) return;
        final (edition, place) = next;
        final window = await _heard.hearLater(edition, place);
        if (window == null) _tried.add(_key(place));
      }
    } finally {
      _filling = false;
    }
  }

  /// The newest place that the listening timeline names, that no window
  /// covers and that was not tried, with its edition.
  Future<(Edition, AudioPosition)?> _nextFill() async {
    for (final entry in _playback.timeline(null)) {
      final places = switch (entry) {
        ActionEntry(:final event) => [
          event.after,
          if (event.moved) event.before,
        ],
        BookmarkEntry(:final bookmark) => [bookmark.position],
      };
      for (final place in places.whereType<AudioPosition>()) {
        if (_tried.contains(_key(place))) continue;
        final edition = _playback.editionOf(place.editionId);
        if (edition == null || !place.fits(edition)) continue;
        final windows = await _heard.windowsOf(edition);
        if (windows.any((window) => window.covers(place))) continue;
        return (edition, place);
      }
    }
    return null;
  }

  static String _key(AudioPosition place) =>
      '${place.editionId}\n${place.sourceKey}\n${place.revision}\n'
      '${place.milliseconds}';

  static AudioPosition _shifted(AudioPosition place, int milliseconds) =>
      AudioPosition(
        editionId: place.editionId,
        sourceKey: place.sourceKey,
        revision: place.revision,
        milliseconds: math.max(0, place.milliseconds + milliseconds),
      );

  void dispose() {
    _disposed = true;
    if (!_started) return;
    _playback.positionNotifier.removeListener(_moved);
    _playback.recordsNotifier.removeListener(_recorded);
    _mayFill.removeListener(recheck);
  }
}
