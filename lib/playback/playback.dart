import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../catalog/jellyfin.dart';
import '../catalog/model.dart';
import '../downloads/downloads.dart';
import 'reporting.dart';
import 'records.dart';

export 'records.dart';

class AudioSample {
  const AudioSample(
    this.fileIndex,
    this.milliseconds, {
    this.playing = false,
    this.completed = false,
  });
  final int fileIndex;
  final int milliseconds;
  final bool playing;
  final bool completed;
}

abstract class AudioEngine {
  Stream<AudioSample> get samples;
  Future<void> load(List<Uri> files, int fileIndex, int milliseconds);
  Future<void> play();
  Future<void> pause();
  Future<AudioSample> seek(int fileIndex, int milliseconds);
  Future<void> speed(double value);
  Future<void> close();
}

abstract class ResumeStore {
  Future<Map<String, dynamic>?> read(String accountKey);
  Future<void> write(String accountKey, Map<String, dynamic> value);
  void acceptSnapshot(String accountKey, Map<String, dynamic>? value) {}
}

// The revision is a gesture-cancellation counter, not a media-source revision.
typedef _SliderGesture = ({AudioPosition origin, int revision});

class AudioReplacement {
  const AudioReplacement(this.book, this.edition, this.previous);
  final Book book;
  final Edition edition;
  final AudioPosition previous;
}

typedef RecentListening = ({Book book, Edition edition, DateTime at});

class Playback extends ChangeNotifier {
  Playback({
    required this.downloads,
    required this.engine,
    required this.store,
    this.reports,
  }) {
    _samples = engine.samples.listen(
      _accept,
      onError: (Object error) {
        unawaited(_enqueue(_audioFailed));
      },
    );
  }
  final Downloads downloads;
  final AudioEngine engine;
  final ResumeStore store;
  final LiveReports? reports;
  late final StreamSubscription<AudioSample> _samples;
  JellyfinSession? _session;
  List<Book> _books = [];
  Book? _book;
  Edition? _edition;
  AudioPosition? _position;
  bool _playing = false;
  bool _active = false;
  bool _closed = false;
  bool _loading = false;
  // A failed load can leave the decoder on another edition. Ignore its
  // samples until the retained selection is successfully loaded again.
  bool _decoderReady = false;
  bool _restored = false;
  String? _message;
  double _speed = 1;
  int _backward = 10;
  int _forward = 30;
  int _generation = 0;
  Map<String, List<Map<String, dynamic>>> _resumes = {};
  String? _selected;
  Timer? _sleep;
  DateTime? _sleepDeadline;
  Future<void> _operations = Future.value();
  Future<void> _writes = Future.value();
  Future<void> _binding = Future.value();
  // The personal records. A change replaces a whole list, never changes it
  // in place, so the lists derived from them can be cached by the identity
  // of these lists (see [_Memo]). Debug builds enforce this contract with
  // unmodifiable lists. Release builds skip it, so that a broken contract
  // can only show a stale list, never throw in a path that saves records.
  List<ListeningEvent> _historyList = const [];
  List<AudioBookmark> _bookmarkList = const [];
  List<ListeningEvent> get _history => _historyList;
  set _history(List<ListeningEvent> value) =>
      _historyList = kDebugMode ? List.unmodifiable(value) : value;
  List<AudioBookmark> get _bookmarks => _bookmarkList;
  set _bookmarks(List<AudioBookmark> value) =>
      _bookmarkList = kDebugMode ? List.unmodifiable(value) : value;
  final _historyNewestFirst =
      _Memo<List<ListeningEvent>, List<ListeningEvent>>();
  final _bookmarksNewestFirst =
      _Memo<List<AudioBookmark>, List<AudioBookmark>>();
  final _editionIndex = _Memo<List<Book>, Map<String, (Book, Edition)>>();
  final _recent =
      _Memo<(List<ListeningEvent>, List<Book>), List<RecentListening>>();
  final _chapters = _Memo<Edition?, List<PlaybackChapter>>();
  final _timeline =
      _Memo<
        (List<ListeningEvent>, List<AudioBookmark>, Book?),
        List<TimelineEntry>
      >();
  final _editionBookmarks =
      _Memo<(List<AudioBookmark>, Edition?), List<EditionBookmark>>();
  ListeningEvent? _undo;
  _SliderGesture? _sliderStart;
  int _sliderRevision = 0;
  bool _seeking = false;
  ListeningAction? _commandAction;
  final _pendingWrites = <String, Map<String, dynamic>>{};
  final _failedAccounts = <String>{};
  int _recordRevision = 0;
  String? _recordedDecoderAnchor;
  AudioReplacement? _replacementStart;

  /// The listening actions, newest first. The list stays the same object
  /// until the history changes.
  List<ListeningEvent> get history => _historyNewestFirst.of(
    _history,
    () => List.unmodifiable(_history.reversed),
  );

  /// The books of this account that were listened to, newest first, each with
  /// the audio edition and time of its latest listening. The list stays the
  /// same object until the history or the library changes.
  List<RecentListening> get recent => _recent.of((_history, _books), () {
    // One pass over the history finds each book's latest listening, so only
    // the few listened books are sorted.
    final latest = <String, RecentListening>{};
    for (final event in _history) {
      final found = _editions[event.after.editionId];
      if (found == null) continue;
      final (book, edition) = found;
      if (latest[book.id] case final known? when !event.at.isAfter(known.at)) {
        continue;
      }
      latest[book.id] = (book: book, edition: edition, at: event.at);
    }
    return List.unmodifiable(
      latest.values.toList()..sort((a, b) => b.at.compareTo(a.at)),
    );
  });

  /// The actions and bookmarks of [book], or of every book, newest first.
  /// The list stays the same object until the records change or another
  /// book is asked for.
  List<TimelineEntry> timeline(Book? book) =>
      _timeline.of((_history, _bookmarks, book), () {
        bool belongs(AudioPosition place) =>
            book == null ||
            book.editions.any((edition) => edition.id == place.editionId);
        final entries = <TimelineEntry>[
          for (final event in history)
            if (belongs(event.after)) ActionEntry(event),
          for (final bookmark in bookmarks)
            if (belongs(bookmark.position)) BookmarkEntry(bookmark),
        ];
        // NOTE: This sort stays on the UI isolate. It runs once per records
        // change, and an isolate hop copies every entry there and back,
        // which measured about ten times the cost of the sort itself.
        entries.sort((a, b) => b.at.compareTo(a.at));
        return List.unmodifiable(entries);
      });

  /// Each bound edition by its id, with its book.
  Map<String, (Book, Edition)> get _editions => _editionIndex.of(_books, () {
    final editions = <String, (Book, Edition)>{};
    for (final book in _books) {
      for (final edition in book.editions) {
        editions.putIfAbsent(edition.id, () => (book, edition));
      }
    }
    return editions;
  });

  /// The bookmarks, newest first. The list stays the same object until a
  /// bookmark changes.
  List<AudioBookmark> get bookmarks => _bookmarksNewestFirst.of(
    _bookmarks,
    () => List.unmodifiable(_bookmarks.reversed),
  );
  ListeningEvent? get undoAction => _undo;
  bool get unsavedChanges => _pendingWrites.containsKey(_session?.scope.key);
  bool get saveFailed => _failedAccounts.contains(_session?.scope.key);
  AudioReplacement? get replacementStart => _replacementStart;

  Future<void> confirmReplacement(AudioReplacement request) =>
      _enqueue(() async {
        if (!identical(request, _replacementStart)) return;
        if (request.edition.files.any(
          (file) => file.revision.isEmpty || file.mediaSourceId.isEmpty,
        )) {
          _message = 'The replacement audio source cannot be identified. Refresh the library before starting it.';
          _notify();
          return;
        }
        await _open(
          request.book,
          request.edition,
          autoplay: true,
          replacement: request,
        );
      });

  void cancelReplacement(AudioReplacement request) {
    if (!identical(request, _replacementStart)) return;
    _replacementStart = null;
    _message = null;
    _notify();
  }

  String sourceName(AudioPosition position) =>
      _books
          .expand((book) => book.editions)
          .where((edition) => edition.id == position.editionId)
          .expand((edition) => edition.files)
          .where((file) => file.key == position.sourceKey)
          .firstOrNull
          ?.displayName ??
      'Source ${position.sourceKey}';

  void dismissUndo() {
    _undo = null;
    _notify();
  }

  /// Capture the gesture's origin now, even while a disk write blocks commands.
  /// Selection changes and intervening position commands invalidate this origin.
  Future<void> beginSliderSeek() {
    _sliderStart =
        !_closed && _restored && !_loading && !_seeking && _position != null
        ? (origin: _position!, revision: _sliderRevision)
        : null;
    return Future.value();
  }

  /// Queue this completed gesture with its own origin. Later gestures cannot
  /// replace it; a selection change or non-slider seek still invalidates it.
  Future<void> finishSliderSeek(int milliseconds) {
    final start = _sliderStart;
    _sliderStart = null;
    return _enqueue(() async {
      if (start != null &&
          start.revision == _sliderRevision &&
          _edition != null &&
          start.origin.fits(_edition!)) {
        await _seekEdition(milliseconds, gesture: start);
      }
    });
  }

  void _invalidateSlider() {
    _sliderStart = null;
    _sliderRevision++;
  }

  Future<void> undoSeek() => _enqueue(() async {
    final event = _undo;
    if (event == null) return;
    if (await _restorePosition(event.before, ListeningAction.undo)) {
      _undo = null;
    }
    _notify();
  });

  Future<void> restoreHistory(String id, {bool previous = true}) =>
      _enqueue(() async {
        final event = _history.where((event) => event.id == id).firstOrNull;
        if (event == null) {
          throw ArgumentError('Choose history from the current account.');
        }
        await _restorePosition(
          previous ? event.before : event.after,
          ListeningAction.historyRestore,
        );
      });

  Future<void> addBookmark({
    AudioPosition? position,
    String? title,
    String? note,
  }) => _enqueue(() async {
    if (!_restored || _position == null) return;
    final target = position ?? _position!;
    if (!target.fits(_edition!)) {
      throw ArgumentError('Choose a bookmark position in this audio edition.');
    }
    _bookmarks = [
      ..._bookmarks,
      AudioBookmark(
        id: recordId(),
        position: target,
        createdAt: DateTime.now().toUtc(),
        bookTitle: _book!.title,
        editionLabel: _edition!.label,
        title: _optionalText(title),
        note: _optionalText(note),
      ),
    ];
    await _saveRecords();
  });

  Future<void> editBookmark(String id, {String? title, String? note}) =>
      _enqueue(() async {
        if (!_restored) return;
        final index = _bookmarks.indexWhere((bookmark) => bookmark.id == id);
        if (index < 0) {
          throw ArgumentError('Choose a bookmark from the current account.');
        }
        final bookmark = _bookmarks[index];
        _bookmarks = [..._bookmarks]
          ..[index] = AudioBookmark(
            id: bookmark.id,
            position: bookmark.position,
            createdAt: bookmark.createdAt,
            bookTitle: bookmark.bookTitle,
            editionLabel: bookmark.editionLabel,
            title: _optionalText(title),
            note: _optionalText(note),
          );
        await _saveRecords();
      });

  Future<void> deleteBookmark(String id) => _enqueue(() async {
    if (!_restored) return;
    _bookmarks = [..._bookmarks]..removeWhere((bookmark) => bookmark.id == id);
    await _saveRecords();
  });

  Future<void> deleteHistory(String id) => _enqueue(() async {
    if (!_restored) return;
    _history = [..._history]..removeWhere((event) => event.id == id);
    if (_undo?.id == id) _undo = null;
    await _saveRecords();
  });

  Future<void> refreshPersonalRecords() => _enqueue(() async {
    final account = _session?.scope.key;
    await _writes;
    if (account == null || !_restored || _pendingWrites.containsKey(account)) {
      return;
    }
    final revision = _recordRevision;
    final saved = await store.read(account);
    if (saved == null ||
        account != _session?.scope.key ||
        revision != _recordRevision) {
      return;
    }
    final history = (saved['history'] as List)
        .map(
          (value) =>
              ListeningEvent.fromJson(Map<String, dynamic>.from(value as Map)),
        )
        .toList();
    final bookmarks = (saved['bookmarks'] as List)
        .map(
          (value) =>
              AudioBookmark.fromJson(Map<String, dynamic>.from(value as Map)),
        )
        .toList();
    final resumes = <String, List<Map<String, dynamic>>>{
      for (final entry in (saved['resumes'] as Map<String, dynamic>).entries)
        entry.key: (entry.value as List).cast<Map<String, dynamic>>(),
    };
    _history = history;
    _bookmarks = bookmarks;
    _resumes = resumes;
    store.acceptSnapshot(account, saved);
    if (_undo != null && !_history.any((event) => event.id == _undo!.id)) {
      _undo = null;
    }
    _notify();
  });

  Future<void> restoreBookmark(String id) => _enqueue(() async {
    final bookmark = _bookmarks
        .where((bookmark) => bookmark.id == id)
        .firstOrNull;
    if (bookmark == null) {
      throw ArgumentError('Choose a bookmark from the current account.');
    }
    await _restorePosition(bookmark.position, ListeningAction.bookmarkRestore);
  });

  String? _optionalText(String? value) =>
      value == null || value.trim().isEmpty ? null : value.trim();

  Future<void> _saveRecords() async {
    _save();
    await _writes;
    _notify();
  }

  Future<bool> _restorePosition(
    AudioPosition target,
    ListeningAction kind,
  ) async {
    if (!_restored) return false;
    final book = _books
        .where(
          (book) =>
              book.editions.any((edition) => edition.id == target.editionId),
        )
        .firstOrNull;
    final edition = book?.editions
        .where((edition) => edition.id == target.editionId)
        .firstOrNull;
    if (edition == null || !target.fits(edition)) {
      _message = 'The saved audio source changed or is unavailable. Its personal records were kept but were not applied.';
      _notify();
      return false;
    }
    final generation = _generation;
    for (final file in edition.files) {
      final local = await downloads.localFile(file);
      if (generation != _generation) return false;
      if (local == null || local.scheme != 'file') {
        _message = 'Download every file in this audio edition before restoring a position.';
        _notify();
        return false;
      }
    }
    final before = _position;
    final wasPlaying = _playing;
    if (_edition?.id != edition.id) {
      return _open(
        book!,
        edition,
        autoplay: wasPlaying,
        target: target,
        action: kind,
      );
    }
    final applied = await _seekPosition(
      edition.files.indexWhere((file) => file.key == target.sourceKey),
      target.milliseconds,
      kind,
      before: before,
    );
    if (!applied || generation != _generation) return false;
    if (wasPlaying && !_active) {
      _active = true;
      await engine.play();
    }
    return true;
  }

  Book? get book => _book;
  Edition? get edition => _edition;
  AudioPosition? get position => _position;
  bool get playing => _playing;
  bool get active => _active;
  bool get pendingOfflineResume =>
      _edition != null &&
      _resumeFits(_edition!, _resumeRecord(_edition!)) &&
      _resumeRecord(_edition!)?['pendingOffline'] == true;
  String? get message => _message;
  double get playbackSpeed => _speed;
  int get backwardSeconds => _backward;
  int get forwardSeconds => _forward;
  DateTime? get sleepDeadline => _sleepDeadline;

  int? get durationMilliseconds {
    final files = _edition?.files;
    if (files == null || files.any((file) => file.durationMs == null)) {
      return null;
    }
    return files.fold<int>(0, (total, file) => total + file.durationMs!);
  }

  /// Where [position] is in its audio edition, in milliseconds from the
  /// edition's start. Null when the edition is not in the library, or when a
  /// file before the position has no known length.
  int? editionTime(AudioPosition position) {
    final edition = _edition?.id == position.editionId
        ? _edition
        : _editions[position.editionId]?.$2;
    return edition == null ? null : _editionTime(edition, position);
  }

  static int? _editionTime(Edition edition, AudioPosition position) {
    final start = _fileStarts(edition)[position.sourceKey];
    return start == null ? null : start + position.milliseconds;
  }

  static final _starts = Expando<Map<String, int?>>();

  /// Where each file of [edition] starts in the edition, in milliseconds, by
  /// file key. A start is null when an earlier file has no known length. An
  /// edition never changes, so its starts are found once.
  static Map<String, int?> _fileStarts(Edition edition) =>
      _starts[edition] ??= () {
        final starts = <String, int?>{};
        int? offset = 0;
        for (final file in edition.files) {
          starts.putIfAbsent(file.key, () => offset);
          offset = offset == null || file.durationMs == null
              ? null
              : offset + file.durationMs!;
        }
        return starts;
      }();

  /// The bookmarks of the open edition, newest first, each with where it is
  /// in the edition. A bookmark whose place cannot be measured is left out.
  /// The list stays the same object until a bookmark or the open edition
  /// changes.
  List<EditionBookmark> get editionBookmarks =>
      _editionBookmarks.of((_bookmarks, _edition), () {
        final edition = _edition;
        return List.unmodifiable([
          if (edition != null)
            for (final bookmark in bookmarks)
              if (bookmark.position.editionId == edition.id)
                if (_editionTime(edition, bookmark.position) case final at?)
                  (bookmark: bookmark, at: at),
        ]);
      });

  /// How long after a bookmark the open place still counts as at it.
  static const bookmarkReach = Duration(seconds: 15);

  /// The newest bookmark of the open edition that lies at most
  /// [bookmarkReach] before the open place, if any.
  AudioBookmark? get bookmarkHere {
    final edition = _edition;
    final now = editionMilliseconds;
    if (edition == null || now == null) return null;
    for (final (:bookmark, :at) in editionBookmarks) {
      if (bookmark.position.fits(edition) &&
          now >= at &&
          now - at < bookmarkReach.inMilliseconds) {
        return bookmark;
      }
    }
    return null;
  }

  int? get editionMilliseconds {
    final position = _position;
    return position == null ? null : _editionTime(_edition!, position);
  }

  /// Where the open or saved position is in the edition, in milliseconds
  /// from its start. Null before any listening, or when a file length is
  /// unknown.
  ({int elapsedMs, int totalMs})? progress(Edition edition) {
    final position = _edition?.id == edition.id
        ? _position
        : _readPosition(edition);
    if (position == null || !position.fits(edition)) return null;
    int? elapsed;
    var total = 0;
    for (final file in edition.files) {
      if (file.key == position.sourceKey) {
        elapsed = total + position.milliseconds;
      }
      if (file.durationMs == null) return null;
      total += file.durationMs!;
    }
    return elapsed == null ? null : (elapsedMs: elapsed, totalMs: total);
  }

  /// The chapters of the open edition in order. A file without a chapter at
  /// its start counts as a chapter named after the file. The list stays the
  /// same object until the open edition changes.
  List<PlaybackChapter> get chapters => _chapters.of(_edition, () {
    final edition = _edition;
    if (edition == null) return const [];
    final chapters = <PlaybackChapter>[];
    final starts = _fileStarts(edition);
    for (final file in edition.files) {
      final offset = starts[file.key];
      if (!file.chapters.any((chapter) => chapter.startMs == 0)) {
        chapters.add(PlaybackChapter(file.displayName, file.key, 0, offset));
      }
      for (final chapter in file.chapters) {
        if (chapter.startMs >= 0 &&
            (file.durationMs == null || chapter.startMs < file.durationMs!)) {
          chapters.add(
            PlaybackChapter(
              chapter.name,
              file.key,
              chapter.startMs,
              offset == null ? null : offset + chapter.startMs,
            ),
          );
        }
      }
    }
    return List.unmodifiable(chapters);
  });

  /// The index in [chapters] of the chapter that holds the position.
  int? get chapterIndex {
    final position = _position;
    if (position == null) return null;
    final chapters = this.chapters;
    int? found;
    for (final (index, chapter) in chapters.indexed) {
      if (chapter.sourceKey == position.sourceKey &&
          chapter.milliseconds <= position.milliseconds &&
          (found == null ||
              chapter.milliseconds >= chapters[found].milliseconds)) {
        found = index;
      }
    }
    return found;
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final generation = _generation;
    final binding = _binding;
    final operation = _operations
        .then<void>((_) async {
          await binding;
          if (!_closed && generation == _generation) await action();
        })
        .onError<Exception>((error, stack) async {
          if (!_closed && generation == _generation) await _audioFailed();
        });
    _operations = operation.onError<ArgumentError>((error, stack) {});
    return operation;
  }

  Future<void> _audioFailed() async {
    _message = 'Cannot play this local audio file. Download it again or choose another edition.';
    try {
      await engine.pause();
    } on Exception {
      _message =
          'The audio device failed. Restart Bookfin before listening again.';
    }
    _playing = false;
    _active = false;
    reports?.stop();
    _save();
    _notify();
  }

  Future<void> bind(JellyfinSession? session, List<Book> books) async {
    if (_closed) return;
    _replacementStart = null;
    final changed = _session?.scope.key != session?.scope.key;
    _books = List.unmodifiable(books);
    if (!changed) {
      final generation = _generation;
      _session = session;
      if (_edition != null) {
        final current = books
            .expand((book) => book.editions)
            .where((edition) => edition.id == _edition!.id)
            .firstOrNull;
        if (current == null ||
            _position?.fits(current) != true ||
            !listEquals(
              current.files.map((file) => file.key).toList(),
              _edition!.files.map((file) => file.key).toList(),
            ) ||
            _editionSources(current) != _editionSources(_edition!)) {
          await bind(null, []);
          await bind(session, books);
        } else {
          _edition = current;
          _book = books.firstWhere((book) => book.editions.contains(current));
          _notify();
        }
      }
      await _binding;
      if (generation != _generation) return;
      // The library can arrive after the account, so the saved book may
      // only now be in [books].
      if (_edition == null && _restored) {
        final (book, edition) = _selectedEdition();
        if (book != null && edition != null) {
          final resume = _readPosition(edition);
          if (resume != null && !_resumeFits(edition, _resumeRecord(edition))) {
            _offerReplacement(book, edition, resume);
          } else if (resume != null) {
            unawaited(
              _enqueue(() async {
                if (_edition == null &&
                    _selected == edition.id &&
                    _currentEdition(book, edition)) {
                  await _open(book, edition, autoplay: false);
                }
              }),
            );
          }
        }
      }
      _notify();
      return;
    }
    _save();
    reports?.stop();
    final generation = ++_generation;
    _session = session;
    _restored = false;
    _book = null;
    _edition = null;
    _position = null;
    _recordedDecoderAnchor = null;
    _playing = false;
    _active = false;
    _decoderReady = false;
    _resumes = {};
    _history = [];
    _bookmarks = [];
    _undo = null;
    _invalidateSlider();
    _selected = null;
    _speed = 1;
    _backward = 10;
    _forward = 30;
    _message = null;
    _cancelSleep();
    _notify();
    final previousBinding = _binding;
    final previousOperations = _operations;
    final ready = Completer<void>();
    _binding = ready.future;
    try {
      await previousBinding;
      await previousOperations;
      await engine.pause();
      await _writes;
      if (session == null || generation != _generation) return;
      try {
        final pending = _pendingWrites[session.scope.key];
        final saved = pending ?? await store.read(session.scope.key);
        if (generation != _generation) return;
        if (saved != null &&
            saved['version'] != 1 &&
            saved['version'] != 2 &&
            saved['version'] != 3) {
          throw const FormatException('Unsupported listening record');
        }
        if (saved != null) {
          if (saved['version'] != 1) {
            _history = (saved['history'] as List)
                .map(
                  (value) => ListeningEvent.fromJson(
                    Map<String, dynamic>.from(value as Map),
                  ),
                )
                .toList();
            _bookmarks = (saved['bookmarks'] as List)
                .map(
                  (value) => AudioBookmark.fromJson(
                    Map<String, dynamic>.from(value as Map),
                  ),
                )
                .toList();
            if (_history.map((event) => event.id).toSet().length !=
                    _history.length ||
                _bookmarks.map((bookmark) => bookmark.id).toSet().length !=
                    _bookmarks.length) {
              throw const FormatException(
                'Duplicate personal record identifiers',
              );
            }
          }
          final resumes = Map<String, dynamic>.from(
            saved['resumes'] as Map? ?? {},
          );
          _resumes = {
            for (final entry in resumes.entries)
              entry.key: [
                for (final value
                    in saved['version'] == 3
                        ? entry.value as List
                        : [entry.value])
                  Map<String, dynamic>.from(value as Map),
              ],
          };
          _selected = saved['selected'] as String?;
          final speed = (saved['speed'] as num?)?.toDouble() ?? 1;
          if (speed.isFinite && speed >= 0.5 && speed <= 3) _speed = speed;
          final backward = saved['backward'] as int? ?? 10;
          final forward = saved['forward'] as int? ?? 30;
          if (backward > 0 && backward <= 300) _backward = backward;
          if (forward > 0 && forward <= 300) _forward = forward;
        }
        if (pending == null) store.acceptSnapshot(session.scope.key, saved);
        _restored = true;
        await _restoreSelected();
      } on Exception {
        if (!_restored) {
          _history = [];
          _bookmarks = [];
        }
        _message = 'Cannot restore listening position. Saved listening data was not removed.';
      } on TypeError {
        if (!_restored) {
          _history = [];
          _bookmarks = [];
        }
        _message = 'Cannot restore listening position. Saved listening data was not removed.';
      }
      _notify();
    } finally {
      ready.complete();
    }
  }

  /// The bound book and edition that were open when this account last saved.
  (Book?, Edition?) _selectedEdition() {
    final book = _books
        .where(
          (book) => book.editions.any((edition) => edition.id == _selected),
        )
        .firstOrNull;
    return (
      book,
      book?.editions.where((edition) => edition.id == _selected).firstOrNull,
    );
  }

  /// Reopens the edition that was open when this account last saved, paused
  /// at its saved position. Does nothing while that edition is not in the
  /// bound books.
  Future<void> _restoreSelected() async {
    final (book, edition) = _selectedEdition();
    if (book == null || edition == null) return;
    final resume = _readPosition(edition);
    if (resume == null || !_resumeFits(edition, _resumeRecord(edition))) {
      _message = 'The saved audio source changed. Its resume is kept but was not applied.';
      if (resume != null) _offerReplacement(book, edition, resume);
    } else {
      await _open(book, edition, autoplay: false);
    }
  }

  String _editionSources(Edition edition) {
    final sources = [
      for (final file in edition.files) [file.key, file.revision],
    ]..sort((left, right) => left.first.compareTo(right.first));
    return jsonEncode(sources);
  }

  bool _currentEdition(Book book, Edition edition) =>
      _session != null &&
      _books.any(
        (candidate) =>
            candidate.id == book.id && candidate.editions.contains(edition),
      );

  void _offerReplacement(Book book, Edition edition, AudioPosition resume) {
    if (!_restored || !_currentEdition(book, edition)) return;
    _replacementStart = AudioReplacement(book, edition, resume);
  }

  bool _resumeFits(Edition edition, Map<String, dynamic>? value) =>
      value != null &&
      (value['sources'] == null ||
          value['sources'] == _editionSources(edition)) &&
      _positionFrom(edition.id, value)?.fits(edition) == true;

  Map<String, dynamic>? _resumeRecord(Edition edition) {
    final records = _resumes[edition.id] ?? [];
    return records.where((value) => _resumeFits(edition, value)).lastOrNull ??
        records.lastOrNull;
  }

  AudioPosition? _readPosition(Edition edition) =>
      _positionFrom(edition.id, _resumeRecord(edition));

  AudioPosition? _positionFrom(String editionId, dynamic value) {
    if (value is! Map) return null;
    if (value['source'] is! String ||
        value['revision'] is! String ||
        value['milliseconds'] is! int) {
      return null;
    }
    return AudioPosition(
      editionId: editionId,
      sourceKey: value['source'] as String,
      revision: value['revision'] as String,
      milliseconds: value['milliseconds'] as int,
    );
  }

  Future<void> open(Book book, Edition edition, {bool autoplay = true}) =>
      _enqueue(() async {
        await _open(book, edition, autoplay: autoplay);
      });

  /// True only when this account's selection was loaded and committed.
  Future<bool> _open(
    Book book,
    Edition edition, {
    required bool autoplay,
    AudioPosition? target,
    ListeningAction? action,
    AudioReplacement? replacement,
  }) async {
    if (!_currentEdition(book, edition) ||
        edition.kind != EditionKind.audio ||
        edition.files.isEmpty) {
      throw ArgumentError('Choose an audio edition from the current account.');
    }
    if (!_restored) {
      _message = 'Cannot restore listening records. Restart Bookfin before listening. Saved listening data was not removed.';
      _notify();
      return false;
    }
    final generation = _generation;
    final files = <Uri>[];
    for (final file in edition.files) {
      final uri = await downloads.localFile(file);
      if (generation != _generation || !_currentEdition(book, edition)) {
        return false;
      }
      if (uri == null || uri.scheme != 'file') {
        _message =
            'Download every file in this audio edition before listening.';
        _notify();
        return false;
      }
      files.add(uri);
    }
    final resume = replacement != null
        ? null
        : target ?? _readPosition(edition);
    if (resume != null &&
        (!resume.fits(edition) ||
            target == null && !_resumeFits(edition, _resumeRecord(edition)))) {
      _message = 'The saved audio source changed. Its resume is kept but was not applied.';
      _offerReplacement(book, edition, resume);
      _notify();
      return false;
    }
    _loading = true;
    _decoderReady = false;
    try {
      await engine.pause();
      _save();
      reports?.stop();
      final fileIndex = resume == null
          ? 0
          : edition.files.indexWhere((file) => file.key == resume.sourceKey);
      await engine.load(files, fileIndex, resume?.milliseconds ?? 0);
      await engine.speed(_speed);
      final confirmed = target == null
          ? AudioSample(fileIndex, resume?.milliseconds ?? 0)
          : await engine.seek(fileIndex, target.milliseconds);
      if (generation != _generation ||
          replacement != null && !identical(replacement, _replacementStart)) {
        await engine.pause();
        if (generation == _generation) {
          _playing = false;
          _active = false;
          _notify();
        }
        return false;
      }
      if (confirmed.fileIndex < 0 ||
          confirmed.fileIndex >= edition.files.length) {
        throw const FormatException(
          'The decoder did not confirm an edition source.',
        );
      }
      final previous = _position;
      _book = book;
      if (target == null || _edition?.id != edition.id) _invalidateSlider();
      if (target == null) _undo = null;
      _edition = edition;
      _selected = edition.id;
      _playing = false;
      _active = autoplay;
      _position = _positionForSample(confirmed);
      _decoderReady = true;
      _replacementStart = null;
      if (action != null) _record(action, previous ?? _position!, _position!);
      _message = null;
      _cancelSleep();
    } finally {
      _loading = false;
    }
    _save();
    if (target != null) await _writes;
    if (generation != _generation) return false;
    _notify();
    if (autoplay) await engine.play();
    return generation == _generation;
  }

  void _accept(AudioSample sample) {
    if (_closed ||
        _loading ||
        !_decoderReady ||
        _seeking ||
        _edition == null ||
        sample.fileIndex < 0 ||
        sample.fileIndex >= _edition!.files.length) {
      return;
    }
    final file = _edition!.files[sample.fileIndex];
    final previous = _position;
    final wasPlaying = _playing;
    _position = _positionForSample(sample);
    final milliseconds = _position!.milliseconds;
    _playing = _active && sample.playing && !sample.completed;
    if (wasPlaying != _playing && _commandAction == null) {
      _record(
        sample.completed
            ? ListeningAction.completion
            : _playing
            ? ListeningAction.resume
            : ListeningAction.interruption,
        previous!,
        _position!,
      );
    }
    reports?.observe(
      _session!,
      file,
      milliseconds,
      playing: _playing,
      speed: _speed,
      completed: sample.completed,
    );
    if (previous?.sourceKey != file.key ||
        previous!.milliseconds ~/ 1000 != milliseconds ~/ 1000 ||
        wasPlaying != _playing) {
      _save();
    }
    if (sample.completed && _active) {
      _active = false;
      _cancelSleep();
      unawaited(_enqueue(engine.pause));
    }
    _notify();
  }

  AudioPosition _positionForSample(AudioSample sample) {
    final file = _edition!.files[sample.fileIndex];
    return AudioPosition(
      editionId: _edition!.id,
      sourceKey: file.key,
      revision: file.revision,
      milliseconds: file.durationMs == null
          ? max(0, sample.milliseconds)
          : sample.milliseconds.clamp(0, file.durationMs!),
    );
  }

  Future<void> play() => _enqueue(() async {
    if (_edition == null) return;
    if (!_decoderReady) {
      await _open(_book!, _edition!, autoplay: true, target: _position);
      return;
    }
    final generation = _generation;
    for (final file in _edition!.files) {
      final local = await downloads.localFile(file);
      if (generation != _generation) return;
      if (local == null) {
        _message =
            'Download every file in this audio edition before listening.';
        _notify();
        return;
      }
    }
    if (durationMilliseconds != null &&
        editionMilliseconds == durationMilliseconds) {
      if (!await _seekPosition(0, 0, ListeningAction.seek)) return;
    }
    _active = true;
    await engine.play();
  });

  Future<void> pause() => _enqueue(() async {
    final generation = _generation;
    _commandAction = ListeningAction.pause;
    try {
      await engine.pause();
      if (generation != _generation) return;
      if (_active) _record(ListeningAction.pause, _position!, _position!);
    } finally {
      _commandAction = null;
    }
    _playing = false;
    _save();
    await _writes;
    _notify();
  });

  Future<void> stop() => _enqueue(() async {
    final generation = _generation;
    _commandAction = ListeningAction.stop;
    try {
      await engine.pause();
      if (generation != _generation) return;
      if (_active) _record(ListeningAction.stop, _position!, _position!);
    } finally {
      _commandAction = null;
    }
    _playing = false;
    _active = false;
    _cancelSleep();
    reports?.stop();
    _save();
    await _writes;
    _notify();
  });

  Future<void> seekEdition(int milliseconds) =>
      _enqueue(() => _seekEdition(milliseconds));

  Future<void> _seekEdition(
    int milliseconds, {
    ListeningAction kind = ListeningAction.seek,
    _SliderGesture? gesture,
  }) async {
    if (_edition == null) return;
    final duration = durationMilliseconds;
    if (duration == null) {
      _message =
          'Choose a chapter or file. The recording length is not available.';
      _notify();
      return;
    }
    var remaining = milliseconds.clamp(0, duration);
    for (var index = 0; index < _edition!.files.length; index++) {
      final length = _edition!.files[index].durationMs!;
      if (remaining < length || index == _edition!.files.length - 1) {
        await _seekPosition(index, remaining, kind, gesture: gesture);
        return;
      }
      remaining -= length;
    }
  }

  Future<void> seekSource(String sourceKey, int milliseconds) =>
      _enqueue(() => _seekSource(sourceKey, milliseconds));

  Future<void> _seekSource(
    String sourceKey,
    int milliseconds, {
    ListeningAction kind = ListeningAction.chapter,
  }) async {
    if (_edition == null) return;
    final index = _edition!.files.indexWhere((file) => file.key == sourceKey);
    if (index < 0 || milliseconds < 0) {
      throw ArgumentError('Choose a chapter in this edition.');
    }
    final duration = _edition!.files[index].durationMs;
    await _seekPosition(
      index,
      duration == null ? milliseconds : milliseconds.clamp(0, duration),
      kind,
    );
  }

  Future<void> jump({required bool forward}) => _enqueue(() async {
    final current = editionMilliseconds;
    final amount = (forward ? _forward : -_backward) * 1000;
    if (current != null && durationMilliseconds != null) {
      await _seekEdition(current + amount, kind: ListeningAction.jump);
    } else if (_position != null) {
      await _seekSource(
        _position!.sourceKey,
        max(0, _position!.milliseconds + amount),
        kind: ListeningAction.jump,
      );
    }
  });

  void _record(
    ListeningAction kind,
    AudioPosition before,
    AudioPosition after,
  ) {
    assert(
      _restored && _book != null && _edition != null && after.fits(_edition!),
    );
    final event = ListeningEvent(
      id: recordId(),
      at: DateTime.now().toUtc(),
      kind: kind,
      before: before,
      after: after,
      bookTitle: _book!.title,
      editionLabel: _edition!.label,
    );
    _history = [..._history, event];
    if (event.changesPosition) _undo = event;
  }

  /// True only after a confirmed position and its action were committed.
  Future<bool> _seekPosition(
    int index,
    int milliseconds,
    ListeningAction kind, {
    AudioPosition? before,
    _SliderGesture? gesture,
  }) async {
    final generation = _generation;
    final previous = gesture?.origin ?? before ?? _position!;
    if (gesture == null) _invalidateSlider();
    if (!_decoderReady) {
      final loaded = await _open(
        _book!,
        _edition!,
        autoplay: false,
        target: _position,
      );
      if (!loaded || generation != _generation) return false;
    }
    if (gesture != null && gesture.revision != _sliderRevision) return false;
    assert(_edition != null && index >= 0 && index < _edition!.files.length);
    _seeking = true;
    late final AudioSample confirmed;
    try {
      confirmed = await engine.seek(index, milliseconds);
    } finally {
      _seeking = false;
    }
    if (generation != _generation) return false;
    if (confirmed.fileIndex < 0 ||
        confirmed.fileIndex >= _edition!.files.length) {
      throw const FormatException(
        'The decoder did not confirm an edition source.',
      );
    }
    _position = _positionForSample(confirmed);
    _record(kind, previous, _position!);
    _accept(confirmed);
    _save();
    await _writes;
    _notify();
    return generation == _generation;
  }

  Future<void> setSpeed(double value) => _enqueue(() async {
    if (!value.isFinite || value < 0.5 || value > 3) {
      throw ArgumentError('Playback speed must be between 0.5 and 3.');
    }
    await engine.speed(value);
    _speed = value;
    _save();
    _notify();
  });

  Future<void> setJumps(int backward, int forward) => _enqueue(() async {
    if (backward < 1 || forward < 1 || backward > 300 || forward > 300) {
      throw ArgumentError('Short jumps must be between 1 and 300 seconds.');
    }
    _backward = backward;
    _forward = forward;
    _save();
    _notify();
  });

  Future<void> setSleep(Duration? duration) => _enqueue(() async {
    if (duration != null && duration <= Duration.zero) {
      throw ArgumentError('Choose a future sleep time.');
    }
    _cancelSleep();
    if (duration != null) {
      _sleepDeadline = DateTime.now().add(duration);
      _sleep = Timer(duration, () {
        _cancelSleep();
        unawaited(pause());
      });
    }
    _notify();
  });

  void _cancelSleep() {
    _sleep?.cancel();
    _sleep = null;
    _sleepDeadline = null;
  }

  String? get _decoderAnchor => _position == null || _edition == null
      ? null
      : jsonEncode([_editionSources(_edition!), encodePosition(_position!)]);

  void _save() {
    final accountKey = _session?.scope.key;
    if (accountKey == null || !_restored) return;
    ++_recordRevision;
    final position = _position;
    final decoderAnchor = _decoderAnchor;
    if (position != null && decoderAnchor != _recordedDecoderAnchor) {
      final records = _resumes.putIfAbsent(position.editionId, () => []);
      // A legacy file-relative position can be read but cannot establish
      // ownership of a whole recording. Keep it when saving a known recording.
      final index = records.lastIndexWhere(
        (value) => value['sources'] == _editionSources(_edition!),
      );
      final value = <String, dynamic>{
        'source': position.sourceKey,
        'revision': position.revision,
        'sources': _editionSources(_edition!),
        'milliseconds': position.milliseconds,
        'pendingOffline':
            pendingOfflineResume ||
            downloads.policy.network == MediaNetwork.disconnected ||
            downloads.policy.network == MediaNetwork.unknown,
      };
      if (index < 0) {
        records.add(value);
      } else {
        records[index] = value;
      }
      _recordedDecoderAnchor = decoderAnchor;
    }
    final value = <String, dynamic>{
      'version': 3,
      'history': _history.map((event) => event.toJson()).toList(),
      'bookmarks': _bookmarks.map((bookmark) => bookmark.toJson()).toList(),
      'selected': _selected,
      'resumes': {
        for (final entry in _resumes.entries)
          entry.key: [
            for (final value in entry.value) Map<String, dynamic>.from(value),
          ],
      },
      'speed': _speed,
      'backward': _backward,
      'forward': _forward,
    };
    _pendingWrites[accountKey] = value;
    _writes = _writes.then((_) => _persistSnapshot(accountKey, value));
  }

  Future<void> _persistSnapshot(
    String accountKey,
    Map<String, dynamic> value,
  ) async {
    try {
      await store.write(accountKey, value);
      if (identical(_pendingWrites[accountKey], value)) {
        _pendingWrites.remove(accountKey);
        _failedAccounts.remove(accountKey);
        if (_session?.scope.key == accountKey) {
          if (_message ==
              'Personal records could not be saved. Free storage and try again.') {
            _message = null;
          }
          _notify();
        }
      }
    } on Exception {
      _failedAccounts.add(accountKey);
      if (_session?.scope.key == accountKey) {
        _message =
            'Personal records could not be saved. Free storage and try again.';
        _notify();
      }
    }
  }

  Future<void> flush() async {
    final generation = _generation;
    await _binding;
    await _operations;
    if (generation != _generation) return;
    if (_decoderAnchor != _recordedDecoderAnchor) _save();
    await _writes;
    final accountKey = _session?.scope.key;
    final pending = _pendingWrites[accountKey];
    if (accountKey != null && pending != null && generation == _generation) {
      _writes = _writes.then((_) => _persistSnapshot(accountKey, pending));
      await _writes;
    }
    await reports?.idle;
  }

  Future<void> close() async {
    if (_closed) return;
    await stop();
    reports?.stop();
    await reports?.idle;
    reports?.close();
    _closed = true;
    _cancelSleep();
    await _samples.cancel();
    await engine.close();
    super.dispose();
  }

  void _notify() {
    if (!_closed) notifyListeners();
  }

  void checkInvariants() {
    if ((_edition == null) != (_position == null) ||
        (_edition == null) != (_book == null) ||
        _decoderReady && _edition == null ||
        _playing && _position == null ||
        _position != null &&
            (!_position!.fits(_edition!) || _session == null)) {
      throw StateError(
        'Playback selection, source position, and account must agree.',
      );
    }
    if (_history.map((event) => event.id).toSet().length != _history.length ||
        _bookmarks.map((bookmark) => bookmark.id).toSet().length !=
            _bookmarks.length ||
        _undo != null && !_history.contains(_undo) ||
        _sliderStart != null &&
            (_edition == null ||
                !_sliderStart!.origin.fits(_edition!) ||
                _sliderStart!.revision != _sliderRevision) ||
        _failedAccounts.any(
          (account) => !_pendingWrites.containsKey(account),
        ) ||
        _replacementStart != null &&
            (!_restored ||
                _session == null ||
                !_books.any(
                  (book) => book.editions.contains(_replacementStart!.edition),
                ))) {
      throw StateError(
        'Personal records, pending writes, and recovery selection must agree.',
      );
    }
  }
}

/// A bookmark of the open edition, and where it is in the edition, in
/// milliseconds from the edition's start.
typedef EditionBookmark = ({AudioBookmark bookmark, int at});

/// The value last derived from a key. It is derived again only when the key
/// differs from the last key. A key holds the inputs of the value. Lists,
/// books and editions compare by identity, so an input must be replaced,
/// never changed in place, when it changes.
class _Memo<K, V> {
  ({K key, V value})? _last;

  V of(K key, V Function() derive) {
    if (_last case (key: final last, :final value) when last == key) {
      return value;
    }
    final value = derive();
    _last = (key: key, value: value);
    return value;
  }
}

class PlaybackChapter {
  const PlaybackChapter(
    this.name,
    this.sourceKey,
    this.milliseconds, [
    this.editionMilliseconds,
  ]);
  final String name;
  final String sourceKey;

  /// Where the chapter starts within its source file.
  final int milliseconds;

  /// Where the chapter starts within the whole edition, or null when an
  /// earlier file has no known duration.
  final int? editionMilliseconds;
}
