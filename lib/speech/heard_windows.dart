import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../catalog/model.dart';
import '../foundation/derived_store.dart';
import '../foundation/hop.dart';
import 'words.dart';

/// Hears [lengthMs] of the downloaded audio file at [path] from [startMs]:
/// [Speech.hear] in the app.
typedef Hear = Future<Heard?> Function(
  String path,
  int startMs,
  int lengthMs, {
  bool urgent,
});

/// One heard window of an audio edition: a stretch of one of its files that
/// the speech runtime transcribed, and the words that it heard. It names no
/// ebook place, so a new ebook revision or another ebook edition reuses it.
@immutable
class HeardWindow {
  const HeardWindow({
    required this.sourceKey,
    required this.revision,
    required this.startMs,
    required this.lengthMs,
    required this.heard,
  });

  /// The file of the window, by [SourceFile.key], at its [revision].
  final String sourceKey;
  final String revision;

  /// Where the window starts in its file, and its length, in milliseconds.
  final int startMs;
  final int lengthMs;

  /// The heard words, each with its time from the window's start.
  final Heard heard;

  int get endMs => startMs + lengthMs;

  /// Whether [place] lies inside this window.
  bool covers(AudioPosition place) =>
      place.sourceKey == sourceKey &&
      place.revision == revision &&
      place.milliseconds >= startMs &&
      place.milliseconds <= endMs;

  Map<String, Object?> toJson() => {
    'source': sourceKey,
    'revision': revision,
    'start': startMs,
    'length': lengthMs,
    'words': heard.words.join(' '),
    'ms': heard.ms,
  };

  /// The window that [toJson] wrote. Throws a [FormatException] when
  /// [value] is not one.
  static HeardWindow fromJson(Object? value) {
    if (value
        case {
          'source': final String sourceKey,
          'revision': final String revision,
          'start': final int startMs,
          'length': final int lengthMs,
          'words': final String words,
          'ms': final List ms,
        }
        when startMs >= 0 && lengthMs > 0) {
      final list = words.isEmpty ? const <String>[] : words.split(' ');
      if (list.length == ms.length && ms.every((value) => value is int)) {
        return HeardWindow(
          sourceKey: sourceKey,
          revision: revision,
          startMs: startMs,
          lengthMs: lengthMs,
          heard: Heard(list, ms.cast<int>()),
        );
      }
    }
    throw const FormatException('Not a heard window.');
  }
}

/// How soon a window is heard. A window for a person who waits goes first,
/// then the windows of listening, then the fill of older places.
enum _Priority { waiting, listening, fill }

/// One window to hear: [length] milliseconds of [file] of [edition] from
/// [start], and the requests that wait for it.
class _Job {
  _Job(this.edition, this.file, this.start, this.length, this.priority);
  final Edition edition;
  final SourceFile file;
  final int start;
  final int length;
  _Priority priority;
  final done = Completer<HeardWindow?>();

  bool covers(AudioPosition place) =>
      place.sourceKey == file.key &&
      place.revision == file.revision &&
      place.milliseconds >= start &&
      place.milliseconds <= start + length;
}

/// The app's one owner of heard windows (docs/plans/cross-edition-places.md,
/// "Build design of S2"): for each audio edition, the windows that this
/// phone heard, in the order of the edition. Crossings searches their words
/// in an ebook, so that a listening place lands on its sentence.
///
/// Heard windows are derived data: local, rebuildable, never synced, never
/// a personal record. One value of [DerivedStore] keeps the windows of one
/// edition, read when they are first needed, never on the path to the
/// first frame. A window of a file whose revision changed is let go. A
/// store that cannot be read starts empty, and a store that cannot be
/// written keeps the windows of this run only.
///
/// It hears one window at a time, through [Hear], from one queue: a window
/// for a person who waits ([hear]) goes before the windows of listening
/// ([hearSoon]), and those go before the fill of older places
/// ([hearLater]). A window is [windowMs] long and centered on its place, so
/// that the place's word lies in its middle, where whisper's word times are
/// surest. A place that a kept or queued window covers is not heard again.
///
/// Invariants, which [checkInvariants] checks:
/// - The windows of an edition lie in its files at their current revision,
///   in the order of the edition, each with a start of its own.
/// - Every kept window holds words.
/// - At most one window is heard at a time, and no two queued windows
///   have the same file and start.
class HeardWindows {
  HeardWindows({
    required this._hear,
    required this._store,
    required this._localPath,
    this._hop = compute,
  });

  final Hear _hear;
  final DerivedStore _store;

  /// The path of the downloaded [SourceFile], or null when this phone has
  /// no download of it.
  final Future<String?> Function(SourceFile file) _localPath;
  final IsolateHop _hop;

  /// The length of a window: the shortest that still gives a unique,
  /// confident match ("The shortest window").
  static const windowMs = 8000;

  /// The version of the kept windows. Raise it when the heard words change
  /// their form, so that kept windows are heard again.
  static const _version = 1;

  /// The windows read or heard so far, by edition id, in edition order.
  /// A change replaces a list, never changes it in place.
  final _windows = <String, List<HeardWindow>>{};

  /// The latest edition object of each edition id that was asked for.
  final _editions = <String, Edition>{};
  final _reads = <String, Future<List<HeardWindow>>>{};
  final _writes = <String, Future<void>>{};
  final _queue = <_Job>[];
  _Job? _running;
  final _changes = _Changes();

  /// Notifies when a window arrives, or when the windows of an edition are
  /// read.
  Listenable get changes => _changes;

  /// The windows of [edition] in edition order, or null until they are
  /// read. A null answer starts the read, and [changes] notifies when it
  /// ends.
  List<HeardWindow>? windowsNow(Edition edition) {
    _editions[edition.id] = edition;
    final kept = _windows[edition.id];
    if (kept == null) unawaited(windowsOf(edition));
    return kept == null ? null : _current(edition, kept);
  }

  /// The windows of [edition] in edition order, read first when needed.
  Future<List<HeardWindow>> windowsOf(Edition edition) async {
    _editions[edition.id] = edition;
    final kept =
        _windows[edition.id] ??
        await (_reads[edition.id] ??= _read(edition.id).whenComplete(() {
          // A block, so that the callback does not give back this future.
          _reads.remove(edition.id);
        }));
    return _current(edition, kept);
  }

  /// [windows] that lie in [edition]'s files at their current revision, in
  /// edition order. The same list when all of them do.
  List<HeardWindow> _current(Edition edition, List<HeardWindow> windows) {
    final order = {
      for (final (index, file) in edition.files.indexed)
        (file.key, file.revision): index,
    };
    if (windows.every((window) => order.containsKey(window.key))) {
      return windows;
    }
    return List.unmodifiable(
      windows.where((window) => order.containsKey(window.key)),
    );
  }

  /// The window that covers [place] of [edition]: a kept one, else one
  /// heard now, before the windows of listening. Null when this phone has no
  /// download of the place's file, or the window holds no words.
  Future<HeardWindow?> hear(Edition edition, AudioPosition place) =>
      _request(edition, place, _Priority.waiting);

  /// Queues the window of [place] of [edition] behind the windows that
  /// wait, unless a kept or queued window covers it.
  void hearSoon(Edition edition, AudioPosition place) =>
      unawaited(_request(edition, place, _Priority.listening));

  /// The window that covers [place] of [edition]: a kept one, else one
  /// heard behind every other window, for the fill of older places. Null as
  /// for [hear].
  Future<HeardWindow?> hearLater(Edition edition, AudioPosition place) =>
      _request(edition, place, _Priority.fill);

  Future<HeardWindow?> _request(
    Edition edition,
    AudioPosition place,
    _Priority priority,
  ) async {
    final file = edition.files
        .where(
          (file) =>
              file.key == place.sourceKey && file.revision == place.revision,
        )
        .firstOrNull;
    if (place.editionId != edition.id || file == null) {
      throw ArgumentError('Give a place of the edition.');
    }
    final windows = await windowsOf(edition);
    for (final window in windows) {
      if (window.covers(place)) return window;
    }
    // A file that this phone streams is refused at once, not after the
    // windows in the queue. Its job asks again, as the download can go.
    if (await _localPath(file) == null) return null;
    final queued = [?_running, ..._queue]
        .where((job) => job.edition.id == edition.id && job.covers(place))
        .firstOrNull;
    if (queued != null) {
      if (priority.index < queued.priority.index) queued.priority = priority;
      return queued.done.future;
    }
    final (start, length) = _span(file, place.milliseconds);
    if (length <= 0) return null;
    final job = _Job(edition, file, start, length, priority);
    _queue.add(job);
    assert(_queueUnique(), 'No two queued windows have one file and start.');
    _pump();
    return job.done.future;
  }

  /// The start and length of the window centered on [milliseconds] of
  /// [file], kept inside the file.
  static (int, int) _span(SourceFile file, int milliseconds) {
    final end = file.durationMs;
    var start = milliseconds - windowMs ~/ 2;
    if (end != null && start + windowMs > end) start = end - windowMs;
    if (start < 0) start = 0;
    final length = end == null ? windowMs : (end - start).clamp(0, windowMs);
    return (start, length);
  }

  /// Hears the first window of the queue, unless one is heard now.
  void _pump() {
    if (_running != null || _queue.isEmpty) return;
    // The most pressing priority first, and the oldest request among equals.
    var next = _queue.first;
    for (final job in _queue) {
      if (job.priority.index < next.priority.index) next = job;
    }
    assert(
      _queue.every((job) => job.priority.index >= next.priority.index),
      'The next window has the most pressing priority.',
    );
    _queue.remove(next);
    final job = _running = next;
    unawaited(
      _run(job)
          .then(
            job.done.complete,
            onError: (Object _) {
              job.done.complete(null);
            },
          )
          .whenComplete(() {
            _running = null;
            _pump();
          }),
    );
  }

  Future<HeardWindow?> _run(_Job job) async {
    final path = await _localPath(job.file);
    if (path == null) return null;
    final heard = await _hear(
      path,
      job.start,
      job.length,
      urgent: job.priority == _Priority.waiting,
    );
    if (heard == null || heard.words.isEmpty) return null;
    final window = HeardWindow(
      sourceKey: job.file.key,
      revision: job.file.revision,
      startMs: job.start,
      lengthMs: job.length,
      heard: heard,
    );
    _add(job.edition, window);
    return window;
  }

  /// Keeps [window] among the windows of [edition], in edition order, and
  /// writes them.
  void _add(Edition edition, HeardWindow window) {
    assert(window.heard.words.isNotEmpty, 'A kept window holds words.');
    final order = {
      for (final (index, file) in edition.files.indexed) file.key: index,
    };
    int compare(HeardWindow a, HeardWindow b) {
      final byFile = (order[a.sourceKey] ?? -1).compareTo(
        order[b.sourceKey] ?? -1,
      );
      return byFile != 0 ? byFile : a.startMs.compareTo(b.startMs);
    }

    final windows = [
      for (final kept in _current(edition, _windows[edition.id] ?? const []))
        if (kept.sourceKey != window.sourceKey ||
            kept.startMs != window.startMs)
          kept,
      window,
    ]..sort(compare);
    _windows[edition.id] = List.unmodifiable(windows);
    assert(
      _keptInOrder(edition, _windows[edition.id]!),
      'The windows of an edition hold words, in its order.',
    );
    _changes.notify();
    _write(edition.id);
  }

  /// Reads the windows of the edition [id], or none when the store keeps
  /// none or keeps a value that cannot be read.
  Future<List<HeardWindow>> _read(String id) async {
    List<HeardWindow> windows = const [];
    try {
      final value = await _store.read(id);
      if (value != null) windows = await _hop(_decode, (id, value));
    } on Exception {
      // Derived data: start again from no windows.
    }
    // A window heard during the read wins over the kept ones.
    final heard = _windows[id];
    if (heard == null) {
      final edition = _editions[id];
      _windows[id] = edition == null ? windows : _current(edition, windows);
      _changes.notify();
    }
    return _windows[id]!;
  }

  /// Writes the windows of the edition [id], after its earlier writes.
  void _write(String id) {
    final windows = _windows[id]!;
    _writes[id] = (_writes[id] ?? Future.value()).then((_) async {
      // A later write of the same edition holds these windows too.
      if (!identical(_windows[id], windows)) return;
      try {
        await _store.write(id, await _hop(_encode, (id, windows)));
      } on Exception {
        // A lost write costs only windows to hear again.
      }
    });
  }

  /// Completes when the writes in flight end, such as before the app stops.
  Future<void> flush() => Future.wait(_writes.values.toList());

  /// Throws a [StateError] when an invariant of the class comment does not
  /// hold. It runs on demand, in every build.
  void checkInvariants() {
    for (final MapEntry(key: id, value: windows) in _windows.entries) {
      final edition = _editions[id];
      if (edition != null && !_keptInOrder(edition, windows)) {
        throw StateError('The windows of an edition hold words, in its order.');
      }
    }
    if (!_queueUnique()) {
      throw StateError('No two queued windows have one file and start.');
    }
  }

  /// Whether each of [windows] holds words, and they lie in the order of
  /// [edition], each with a start of its own.
  static bool _keptInOrder(Edition edition, List<HeardWindow> windows) {
    final order = {
      for (final (index, file) in edition.files.indexed)
        (file.key, file.revision): index,
    };
    for (final (index, window) in windows.indexed) {
      if (window.heard.words.isEmpty) return false;
      if (index == 0) continue;
      final previous = windows[index - 1];
      final (a, b) = (order[previous.key], order[window.key]);
      if (a != null &&
          b != null &&
          (a > b || a == b && previous.startMs >= window.startMs)) {
        return false;
      }
    }
    return true;
  }

  /// Whether no two queued windows have the same file and start.
  bool _queueUnique() =>
      {for (final job in _queue) (job.edition.id, job.file.key, job.start)}
          .length ==
      _queue.length;
}

extension on HeardWindow {
  (String, String) get key => (sourceKey, revision);
}

/// The windows of the kept value [input] of an edition, for a worker
/// isolate. Throws a [FormatException] when it is not one.
List<HeardWindow> _decode((String, String) input) {
  final (id, value) = input;
  final json = jsonDecode(value);
  if (json
      case {
        'version': HeardWindows._version,
        'edition': final String edition,
        'windows': final List windows,
      }
      when edition == id) {
    return List.unmodifiable(windows.map(HeardWindow.fromJson));
  }
  throw const FormatException('Not the heard windows of this edition.');
}

/// The kept value of the windows of an edition, for a worker isolate.
String _encode((String, List<HeardWindow>) input) => jsonEncode({
  'version': HeardWindows._version,
  'edition': input.$1,
  'windows': [for (final window in input.$2) window.toJson()],
});

/// The change signal of [HeardWindows.changes].
class _Changes extends ChangeNotifier {
  void notify() => notifyListeners();
}
