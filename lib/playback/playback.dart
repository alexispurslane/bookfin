import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../catalog/jellyfin.dart';
import '../catalog/model.dart';
import '../crossings/crossings.dart' show AudioLanding;
import '../downloads/downloads.dart';
import '../foundation/serial_queue.dart';
import '../foundation/time.dart' show audioTime;
import 'audio_outline.dart';
import 'reporting.dart';
import 'records.dart';
import 'record_writer.dart';
import 'record_codec.dart' show ConflictVersion, ResumeValue;

export 'audio_outline.dart' show PlaybackChapter;
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

  /// Whether this store found the saved records of [accountKey] damaged
  /// while this app ran, kept the damaged data aside, and started the
  /// account again from the records that it could read.
  bool setAside(String accountKey) => false;
}

/// One current journal version and whether another installation saved it.
typedef ListeningResume = ({ConflictVersion version, bool elsewhere});

/// The owner of each account's saved listening records, as [Playback] uses it.
abstract class ListeningStore {
  /// The saved listening snapshot of [accountKey], or null when the account
  /// has none: the settings plus `history`, `bookmarks` and `resumes`.
  Future<Map<String, dynamic>?> read(String accountKey);

  /// Saves [changes] to the listening records of [accountKey].
  ///
  /// A record that [changes] does not name keeps its saved value. A named
  /// record that equals the value this writer last saved or accepted adds no
  /// sync action, so a retry can resend changes that were already saved.
  Future<void> save(String accountKey, ListeningChanges changes);

  /// Records [value] as the snapshot that the writer of [accountKey] now
  /// shows, so later saves compare their records with it.
  void acceptSnapshot(String accountKey, Map<String, dynamic>? value) {}

  /// Where the saved place of [edition] in [accountKey] came from.
  Future<PlaceOrigin> origin(String accountKey, Edition edition) async =>
      (own: null, elsewhere: false, device: null);

  /// The current journal version of this recording, including deletion,
  /// and whether another installation saved it. Null means the store has no
  /// single known version. Views are detached and never written back.
  Future<ListeningResume?> listeningResume(
    String accountKey,
    Edition edition,
  ) async => null;

  /// Whether this store found the saved records of [accountKey] damaged
  /// while this app ran, kept the damaged data aside, and started the
  /// account again from the records that it could read. A [read] of the
  /// account finds out.
  bool setAside(String accountKey) => false;
}

/// The listening records that one save changes.
///
/// A save carries the whole small [settings], but only the history events,
/// bookmarks and edition resumes that changed.
class ListeningChanges {
  ListeningChanges(
    this.settings, {
    this.history = const {},
    this.bookmarks = const {},
    this.resumes = const {},
  });

  /// The version, selected edition, speed and jump lengths.
  final Map<String, dynamic> settings;

  /// The changed history events as JSON, by id. A null value deletes it.
  final Map<String, Map<String, dynamic>?> history;

  /// The changed bookmarks as JSON, by id. A null value deletes it.
  final Map<String, Map<String, dynamic>?> bookmarks;

  /// The whole resume list of each changed edition, by edition id. Resumes
  /// are never deleted.
  final Map<String, List<Map<String, dynamic>>> resumes;

  /// These changes followed by [later]: the later value of each record and
  /// the later settings win.
  ListeningChanges followedBy(ListeningChanges later) => ListeningChanges(
    later.settings,
    history: {...history, ...later.history},
    bookmarks: {...bookmarks, ...later.bookmarks},
    resumes: {...resumes, ...later.resumes},
  );

  /// The listening snapshot that results when these changes apply to
  /// [snapshot]. A changed record keeps its place, a new one goes last, and
  /// a deleted one is removed.
  Map<String, dynamic> applyTo(Map<String, dynamic>? snapshot) {
    List<Map<String, dynamic>> apply(
      List<dynamic>? saved,
      Map<String, Map<String, dynamic>?> changed,
    ) {
      final unplaced = Map.of(changed);
      return [
        for (final value in saved ?? const [])
          if (!unplaced.containsKey(value['id']))
            Map<String, dynamic>.from(value as Map)
          else
            ?unplaced.remove(value['id']),
        ...unplaced.values.nonNulls,
      ];
    }

    return {
      ...settings,
      'history': apply(snapshot?['history'] as List?, history),
      'bookmarks': apply(snapshot?['bookmarks'] as List?, bookmarks),
      'resumes': <String, dynamic>{
        ...?(snapshot?['resumes'] as Map?)?.cast<String, dynamic>(),
        ...resumes,
      },
    };
  }
}

/// The place of another edition that a mapped move went to the landing of,
/// and how Bookfin found the landing.
typedef _Counterpart = ({Place place, MatchedBy matchedBy});

// The revision is a gesture-cancellation counter, not a media-source revision.
typedef _SliderGesture = ({AudioPosition origin, int revision});

class AudioReplacement {
  const AudioReplacement(this.book, this.edition, this.previous);
  final Book book;
  final Edition edition;
  final AudioPosition previous;
}

typedef RecentListening = ({Book book, Edition edition, DateTime at});

/// The open book and edition, and whether their audio plays. [active] is
/// true from a play command until a pause, a stop or the end of the
/// edition; [playing] is true while the decoder reports sound.
typedef PlaybackSelection = ({
  Book? book,
  Edition? edition,
  bool playing,
  bool active,
});

/// The listening settings: the speed, and the short jump lengths in seconds.
typedef PlaybackSettings = ({double speed, int backward, int forward});

/// The operation that a listening notice explains. It does not change history.
enum PlaybackOperation {
  open,
  play,
  pause,
  stop,
  seek,
  restore,
  speed,
  decoder,
}

/// A failed operation and the edition it tried to use. Edition ids belong to
/// the bound account; account replacement discards the notice.
typedef PlaybackActionNotice = ({
  String editionId,
  PlaybackOperation operation,
  String message,
});

/// Independent notice lifetimes owned by Playback: the latest audio action,
/// record recovery for this binding, and pending saves for this account.
/// A successful audio action cannot resolve a record recovery or a failed save.
typedef PlaybackStatus = ({
  PlaybackActionNotice? actionNotice,
  String? recoveryMessage,
  bool saveFailed,
});

extension PlaybackStatusMessages on PlaybackStatus {
  /// Notices for an edition, a book, or account-wide content when neither is
  /// supplied. An edition narrows a book's scope. History and tabs supply
  /// neither: audio action errors do not describe their record lists.
  Iterable<String> messagesFor({Book? book, Edition? edition}) sync* {
    if (actionNotice case final notice?) {
      final belongs = edition != null
          ? notice.editionId == edition.id
          : book?.editions.any((item) => item.id == notice.editionId) == true;
      if (belongs) yield notice.message;
    }
    if (recoveryMessage case final message?) yield message;
    if (saveFailed) {
      yield 'Personal records could not be saved. Free storage and try again.';
    }
  }
}

/// The alternatives for the open recording. Playback owns its lifetime;
/// screens return this exact request so a stale answer cannot move audio.
class ListeningChoice {
  ListeningChoice._({
    required this.local,
    required this.remote,
    required this._identity,
    required this._sources,
    this.device,
    this._version,
    this._historyId,
    this._requested = false,
  });
  final AudioPosition local;
  final AudioPosition remote;
  final String _identity;
  final String _sources;
  final String? device;
  final ConflictVersion? _version;
  String? _historyId;
  bool _requested;
}

enum ListeningPlace { thisPhone, otherDevice }

class Playback extends ChangeNotifier {
  Playback({
    required this.downloads,
    required this.engine,
    required this.store,
    this.reports,
  }) {
    if (store case final RecordWriterHost host) {
      _unregisterWriter = host.registerWriter(
        account: () => _session?.scope.key,
        flush: flush,
        refresh: refreshPersonalRecords,
        uploadRequests: _uploadRequests,
      );
    }
    _samples = engine.samples.listen(
      _accept,
      onError: (Object error) => unawaited(_sampleStreamFailed()),
    );
  }
  VoidCallback? _unregisterWriter;
  final _uploadRequests = ChangeNotifier();
  // Live reports can be offline or backing off. Their network state must
  // not suppress opportunities to upload durable records at this cadence.
  AudioPosition? _lastUploadPosition;

  // An opportunity, not a pending flag. The coordinator flushes registered
  // writers and asks the durable store whether anything needs uploading.
  void _requestUpload() {
    _lastUploadPosition = _position;
    _uploadRequests.notifyListeners();
  }

  final Downloads downloads;
  final AudioEngine engine;
  final ListeningStore store;
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
  // See [starting].
  Edition? _starting;
  PlaybackActionNotice? _actionNotice;
  String? _recoveryMessage;
  double _speed = 1;
  int _backward = 10;
  int _forward = 30;
  int _generation = 0;
  Map<String, List<Map<String, dynamic>>> _resumes = {};
  String? _selected;
  Timer? _sleep;
  // Ticks once a second while [_sleep] runs, to count the time left down.
  Timer? _sleepCountdown;
  DateTime? _sleepDeadline;
  Duration? _sleepTimer;
  // The command queue. Only [_inCommandOrder] adds to it.
  final _operations = SerialQueue();
  // The saves of the personal records, in the order of their changes. Only
  // [_save] and [flush] add to it.
  final _writes = SerialQueue();
  Future<void> _binding = Future.value();
  // The personal records. A change replaces a whole list, never changes it
  // in place, so the lists derived from them can be cached by the identity
  // of these lists (see [_Memo]). Debug builds enforce this contract with
  // unmodifiable lists. Release builds skip it, so that a broken contract
  // can only show a stale list, never throw in a path that saves records.
  List<HistoryEvent<AudioPosition>> _historyList = const [];
  List<Bookmark<AudioPosition>> _bookmarkList = const [];
  List<HistoryEvent<AudioPosition>> get _history => _historyList;
  set _history(List<HistoryEvent<AudioPosition>> value) =>
      _historyList = kDebugMode ? List.unmodifiable(value) : value;
  List<Bookmark<AudioPosition>> get _bookmarks => _bookmarkList;
  set _bookmarks(List<Bookmark<AudioPosition>> value) =>
      _bookmarkList = kDebugMode ? List.unmodifiable(value) : value;
  final _historyNewestFirst =
      _Memo<
        List<HistoryEvent<AudioPosition>>,
        List<HistoryEvent<AudioPosition>>
      >();
  final _bookmarksNewestFirst =
      _Memo<List<Bookmark<AudioPosition>>, List<Bookmark<AudioPosition>>>();
  final _editionIndex = _Memo<List<Book>, Map<String, (Book, Edition)>>();
  final _recent =
      _Memo<
        (List<HistoryEvent<AudioPosition>>, List<Book>),
        List<RecentListening>
      >();
  final _timeline =
      _Memo<
        (
          List<HistoryEvent<AudioPosition>>,
          List<Bookmark<AudioPosition>>,
          Book?,
        ),
        List<TimelineEntry>
      >();
  final _editionBookmarks =
      _Memo<(List<Bookmark<AudioPosition>>, Edition?), List<EditionBookmark>>();
  HistoryEvent<AudioPosition>? _undo;
  _SliderGesture? _sliderStart;
  int _sliderRevision = 0;
  bool _seeking = false;
  HistoryAction? _commandAction;
  // The changes of each account that the store did not yet confirm, merged
  // into one change set. A retry resends all of them.
  final _pendingWrites = <String, ListeningChanges>{};
  // History events and bookmarks changed since the last _save, by id, as
  // JSON. A null value is a deletion.
  final _changedHistory = <String, Map<String, dynamic>?>{};
  final _changedBookmarks = <String, Map<String, dynamic>?>{};
  final _failedAccounts = <String>{};
  // Saving local changes or adopting a snapshot invalidates older reads.
  int _recordRevision = 0;
  String? _recordedDecoderAnchor;
  AudioReplacement? _replacementStart;
  ListeningChoice? _playChoice;
  Map<String, dynamic>? _choiceToRestore;
  late final _playChoiceSignal = ValueNotifier<ListeningChoice?>(null);

  /// A requested choice, or null. Refresh alone never requests a dialog.
  /// A screen controller presents this request only while in the foreground.
  ValueListenable<ListeningChoice?> get playChoiceNotifier => _playChoiceSignal;

  late final _positionSignal = ValueNotifier<AudioPosition?>(_position);
  late final _selectionSignal = ValueNotifier<PlaybackSelection>(_selection);
  late final _sleepSignal = ValueNotifier<Duration?>(_sleepLeft);
  late final _recordsSignal = ValueNotifier<Object>(_records);
  late final _librarySignal = ValueNotifier<List<Book>>(_books);
  late final _settingsSignal = ValueNotifier<PlaybackSettings>(_settings);
  late final _statusSignal = ValueNotifier<PlaybackStatus>(_status);
  late final _undoSignal = ValueNotifier<UndoOffer<AudioPosition>?>(_undoOffer);
  late final _startingSignal = ValueNotifier<Edition?>(_starting);

  // Playback notifies through these narrow signals for one kind of change
  // each, and through itself for every change but two: a decoder report
  // that only moves the position, and a confirmed save that ends no
  // failure. Those two reach only the narrow signals, so the broad
  // listeners do not run several times a second while audio plays. A
  // widget that shows one value follows the signal of that value. Every signal holds the state
  // that [_publish] last read, so it notifies only when its own value
  // changed. Positions, records and the library compare by identity: each
  // new decoder report is a new position, a records change replaces its
  // list, and each bind replaces the library list.

  /// The position of the open edition, or null when none is open. It
  /// notifies on each decoder report while audio plays, a seek, a restore,
  /// and when another edition opens. A report that repeats the same place
  /// also notifies, so that a follower such as the media session can tell
  /// that the player stalled.
  ValueListenable<AudioPosition?> get positionNotifier => _positionSignal;

  /// The open book and edition, and whether they play.
  ValueListenable<PlaybackSelection> get selectionNotifier => _selectionSignal;

  /// The time left on the sleep timer in whole seconds, or null when no
  /// sleep timer runs. It counts down once a second while the timer runs.
  ValueListenable<Duration?> get sleepNotifier => _sleepSignal;

  /// Notifies when the history, the bookmarks or the saved resumes change:
  /// an added or deleted record, a recorded action, a refresh from storage,
  /// or another account. The resume of the open edition follows its
  /// position on each save, so [positionNotifier] carries that change.
  Listenable get recordsNotifier => _recordsSignal;

  /// Notifies when another library is bound, even for the same account.
  /// The values measured from the library, such as [editionTime] and
  /// [recent], can then change, although no record changed.
  Listenable get libraryNotifier => _librarySignal;

  /// The listening speed and the short jump lengths.
  ValueListenable<PlaybackSettings> get settingsNotifier => _settingsSignal;

  /// Scoped action notices and account-wide record recovery/save notices.
  ValueListenable<PlaybackStatus> get statusNotifier => _statusSignal;

  /// The Undo offer after a position change, or null when there is none. It
  /// notifies when the offer comes or goes, and when the place before the
  /// change is saved. A save of the place where audio plays now does not
  /// change it.
  ValueListenable<UndoOffer<AudioPosition>?> get undoNotifier => _undoSignal;

  /// The edition that a Play or Listen command is starting, or null. It
  /// notifies at the command, before any wait, and again when the edition's
  /// audio sounds, or when the command ends without sound: a missing
  /// download, a decoder failure, Pause, Stop or another account.
  ValueListenable<Edition?> get startingNotifier => _startingSignal;

  /// The listening actions, newest first. The list stays the same object
  /// until the history changes.
  List<HistoryEvent<AudioPosition>> get history => _historyNewestFirst.of(
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
      // An open is no listening, so a book that opened at another device's
      // place keeps its place in the list.
      if (event.kind == HistoryAction.open ||
          event.kind == HistoryAction.preserve) {
        continue;
      }
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

  /// The bound edition [id] of this account, or null.
  Edition? editionOf(String id) => _editions[id]?.$2;

  /// The bound book that holds the edition [id], or null.
  Book? bookOf(String editionId) => _editions[editionId]?.$1;

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
  List<Bookmark<AudioPosition>> get bookmarks => _bookmarksNewestFirst.of(
    _bookmarks,
    () => List.unmodifiable(_bookmarks.reversed),
  );
  HistoryEvent<AudioPosition>? get undoAction => _undo;
  bool get unsavedChanges => _pendingWrites.containsKey(_session?.scope.key);
  bool get saveFailed => _failedAccounts.contains(_session?.scope.key);
  AudioReplacement? get replacementStart => _replacementStart;

  Future<void> confirmReplacement(AudioReplacement request) =>
      _audioCommand(PlaybackOperation.open, () async {
        if (!identical(request, _replacementStart)) return;
        if (request.edition.files.any(
          (file) => file.revision.isEmpty || file.mediaSourceId.isEmpty,
        )) {
          _actionFailed(
            request.edition.id,
            PlaybackOperation.open,
            'The replacement audio source cannot be identified. Refresh the library before starting it.',
          );
          _notify();
          return;
        }
        await _open(
          request.book,
          request.edition,
          autoplay: true,
          replacement: request,
        );
      }, target: () => request.edition.id);

  void cancelReplacement(AudioReplacement request) {
    if (!identical(request, _replacementStart)) return;
    _replacementStart = null;
    if (_actionNotice?.editionId == request.edition.id &&
        _actionNotice?.operation == PlaybackOperation.open) {
      _actionNotice = null;
    }
    _notify();
  }

  String sourceName(AudioPosition position) =>
      _editions[position.editionId]?.$2.files
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
    return _audioCommand(PlaybackOperation.seek, () async {
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

  Future<void> undoSeek() => _audioCommand(PlaybackOperation.restore, () async {
    final event = _undo;
    if (event == null) return;
    if (await _restorePosition(event.before, HistoryAction.undo)) {
      _undo = null;
    }
    _notify();
  }, target: () => _undo?.before.editionId);

  /// Restores where the history event [id] began, or where it ended when
  /// [previous] is false. If the event is gone when this command runs,
  /// completes normally without changing anything.
  Future<void> restoreHistory(String id, {bool previous = true}) =>
      _audioCommand(
        PlaybackOperation.restore,
        () async {
          final event = _history.where((event) => event.id == id).firstOrNull;
          if (event == null) return;
          await _restorePosition(
            previous ? event.before : event.after,
            HistoryAction.historyRestore,
          );
        },
        target: () {
          final event = _history.where((event) => event.id == id).firstOrNull;
          return (previous ? event?.before : event?.after)?.editionId;
        },
      );

  /// Plays from [landing], where a place of an ebook edition lands in the
  /// open edition, as a move of [kind] in the listening track from the place
  /// that plays now, with Undo: a mapped move. The move names the ebook place
  /// that it went to and how Bookfin found the landing. No reading record
  /// changes. Completes with whether the move happened: a landing outside the
  /// open edition moves nothing.
  Future<bool> goToLanding(AudioLanding landing, HistoryAction kind) {
    var went = false;
    return _audioCommand(PlaybackOperation.restore, () async {
      final edition = _edition;
      if (!_restored || edition == null || !landing.place.fits(edition)) {
        return;
      }
      went = await _moveOpen(
        edition,
        landing.place,
        kind,
        wasPlaying: _playing,
        generation: _generation,
        counterpart: (place: landing.from, matchedBy: landing.matchedBy),
      );
    }).then((_) => went);
  }

  Future<void> addBookmark({
    AudioPosition? position,
    String? title,
    String? note,
  }) => _recordsCommand(() async {
    if (!_restored || _position == null) return;
    final target = position ?? _position!;
    if (!target.fits(_edition!)) {
      throw ArgumentError('Choose a bookmark position in this audio edition.');
    }
    _putBookmark(
      Bookmark(
        id: recordId(),
        position: target,
        createdAt: DateTime.now().toUtc(),
        bookTitle: _book!.title,
        editionLabel: _edition!.label,
        title: _optionalText(title),
        note: _optionalText(note),
      ),
    );
    await _saveRecords();
  });

  /// Edits the bookmark [id]. If it is gone when this command runs,
  /// completes normally without changing anything.
  Future<void> editBookmark(String id, {String? title, String? note}) =>
      _recordsCommand(() async {
        if (!_restored) return;
        final index = _bookmarks.indexWhere((bookmark) => bookmark.id == id);
        if (index < 0) return;
        final bookmark = _bookmarks[index];
        _putBookmark(
          Bookmark(
            id: bookmark.id,
            position: bookmark.position,
            createdAt: bookmark.createdAt,
            bookTitle: bookmark.bookTitle,
            editionLabel: bookmark.editionLabel,
            title: _optionalText(title),
            note: _optionalText(note),
          ),
        );
        await _saveRecords();
      });

  Future<void> deleteBookmark(String id) => _recordsCommand(() async {
    if (!_restored) return;
    _removeBookmark(id);
    await _saveRecords();
  });

  Future<void> deleteHistory(String id) => _recordsCommand(() async {
    if (!_restored) return;
    _removeHistory(id);
    if (_undo?.id == id) _undo = null;
    await _saveRecords();
  });

  /// Adopts durable history, bookmarks and resumes without moving the current
  /// decoder or waiting for audio commands or account restoration. Waits only
  /// for local writes. Unconfirmed saves, changed records, a closed player or
  /// a replaced account reject the snapshot, leaving it stale for retry.
  /// Only an adopted snapshot is accepted. Read failures, including [Error]s,
  /// reach the caller and leave audio alone.
  Future<void> refreshPersonalRecords() async {
    final account = _session?.scope.key;
    final generation = _generation;
    if (_closed || account == null || !_restored) return;
    await _writes.idle;
    if (_closed ||
        generation != _generation ||
        !_restored ||
        _pendingWrites.containsKey(account)) {
      return;
    }
    final revision = _recordRevision;
    final edition = _edition;
    final savedFuture = store.read(account);
    final originFuture = edition == null
        ? Future<ListeningResume?>.value()
        : store.listeningResume(account, edition);
    // Future.wait retains the original error, which distinguishes a storage
    // failure from a programming error for the sync coordinator.
    final values = await Future.wait<Object?>([savedFuture, originFuture]);
    final saved = values[0] as Map<String, dynamic>?;
    final origin = values[1] as ListeningResume?;
    if (saved == null ||
        _closed ||
        generation != _generation ||
        revision != _recordRevision) {
      return;
    }
    final history = (saved['history'] as List)
        .map(
          (value) => HistoryEvent.fromJson(
            Map<String, dynamic>.from(value as Map),
            decodePosition,
          ),
        )
        .toList();
    final bookmarks = (saved['bookmarks'] as List)
        .map(
          (value) => Bookmark.fromJson(
            Map<String, dynamic>.from(value as Map),
            decodePosition,
          ),
        )
        .toList();
    final resumes = <String, List<Map<String, dynamic>>>{
      for (final entry in (saved['resumes'] as Map<String, dynamic>).entries)
        entry.key: (entry.value as List).cast<Map<String, dynamic>>(),
    };
    ++_recordRevision;
    _history = history;
    _bookmarks = bookmarks;
    _resumes = resumes;
    _undo = _history.where((event) => event.id == _undo?.id).firstOrNull;
    store.acceptSnapshot(account, saved);
    if (edition != null &&
        _edition != null &&
        _sameEdition(edition, _edition!)) {
      _reconcileListeningChoice(origin);
    }
    _notify();
    await _writes.idle;
  }

  /// Restores the bookmark [id]. If it is gone when this command runs,
  /// completes normally without changing anything.
  Future<void> restoreBookmark(String id) => _audioCommand(
    PlaybackOperation.restore,
    () async {
      final bookmark = _bookmarks
          .where((bookmark) => bookmark.id == id)
          .firstOrNull;
      if (bookmark == null) return;
      await _restorePosition(bookmark.position, HistoryAction.bookmarkRestore);
    },
    target: () => _bookmarks
        .where((mark) => mark.id == id)
        .firstOrNull
        ?.position
        .editionId,
  );

  String? _optionalText(String? value) =>
      value == null || value.trim().isEmpty ? null : value.trim();

  Future<void> _saveRecords() async {
    _save();
    await _writes.idle;
    _notify();
  }

  /// Adds [bookmark], or replaces the bookmark with its id, for the next save.
  void _putBookmark(Bookmark<AudioPosition> bookmark) {
    final index = _bookmarks.indexWhere((saved) => saved.id == bookmark.id);
    _bookmarks = index < 0
        ? [..._bookmarks, bookmark]
        : ([..._bookmarks]..[index] = bookmark);
    _changedBookmarks[bookmark.id] = bookmark.toJson();
  }

  /// Deletes the bookmark [id] for the next save, if this account shows it.
  void _removeBookmark(String id) {
    final count = _bookmarks.length;
    _bookmarks = [..._bookmarks]..removeWhere((bookmark) => bookmark.id == id);
    if (_bookmarks.length != count) _changedBookmarks[id] = null;
  }

  /// Deletes the history event [id] for the next save, if this account shows
  /// it.
  void _removeHistory(String id) {
    final count = _history.length;
    _history = [..._history]..removeWhere((event) => event.id == id);
    if (_history.length != count) _changedHistory[id] = null;
    if (_playChoice?._historyId == id) _playChoice = null;
  }

  Future<bool> _restorePosition(
    AudioPosition target,
    HistoryAction kind,
  ) async {
    if (!_restored) return false;
    final (book, edition) = _editions[target.editionId] ?? (null, null);
    if (edition == null || !target.fits(edition)) {
      _actionFailed(
        target.editionId,
        PlaybackOperation.restore,
        'The saved audio source changed or is unavailable. Its personal records were kept but were not applied.',
      );
      _notify();
      return false;
    }
    final generation = _generation;
    final saved = await _savedFiles(edition);
    if (generation != _generation) return false;
    if (saved == null) {
      _actionFailed(
        edition.id,
        PlaybackOperation.restore,
        'Download every file in this audio edition before restoring a position.',
      );
      _notify();
      return false;
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
    return _moveOpen(
      edition,
      target,
      kind,
      wasPlaying: wasPlaying,
      generation: generation,
      before: before,
    );
  }

  /// Moves the open [edition] to [target] as a move of [kind] from
  /// [before], and plays on when it [wasPlaying]. [counterpart] names the
  /// place of the other edition that a mapped move went to. Whether the
  /// move happened while the binding of [generation] lasts.
  Future<bool> _moveOpen(
    Edition edition,
    AudioPosition target,
    HistoryAction kind, {
    required bool wasPlaying,
    required int generation,
    AudioPosition? before,
    _Counterpart? counterpart,
  }) async {
    final applied = await _seekPosition(
      edition.files.indexWhere((file) => file.key == target.sourceKey),
      target.milliseconds,
      kind,
      before: before,
      counterpart: counterpart,
    );
    if (!applied || generation != _generation) return false;
    if (wasPlaying && !_active) {
      _active = true;
      await engine.play();
    }
    return true;
  }

  /// The signed-in account that playback is bound to, if any.
  JellyfinSession? get session => _session;
  Book? get book => _book;
  Edition? get edition => _edition;
  AudioPosition? get position => _position;
  bool get playing => _playing;
  bool get active => _active;

  /// The edition that a Play or Listen command is starting: from the command
  /// until the edition's audio sounds, or until the command ends without
  /// sound. Null otherwise. See [startingNotifier].
  Edition? get starting => _starting;
  bool get pendingOfflineResume =>
      _edition != null &&
      _resumeFits(_edition!, _resumeRecord(_edition!)) &&
      _resumeRecord(_edition!)?['pendingOffline'] == true;
  double get playbackSpeed => _speed;
  int get backwardSeconds => _backward;
  int get forwardSeconds => _forward;
  DateTime? get sleepDeadline => _sleepDeadline;

  /// The length chosen for the running sleep timer, or null when none runs.
  Duration? get sleepTimer => _sleepTimer;

  /// The length of the open edition in milliseconds, or null when none is
  /// open or a file has no known length.
  int? get durationMilliseconds =>
      _edition == null ? null : audioOutline(_edition!).length;

  /// Where [position] is in its audio edition, in milliseconds from the
  /// edition's start. Null when the edition is not in the library, or when a
  /// file before the position has no known length.
  int? editionTime(AudioPosition position) {
    final edition = _edition?.id == position.editionId
        ? _edition
        : _editions[position.editionId]?.$2;
    return edition == null ? null : _editionTime(edition, position);
  }

  /// [place] in words, for the History timeline: its time in its edition,
  /// such as "1:15", or in its file while the edition time is unknown, and
  /// the chapter that holds it while its edition is in the library.
  PlaceWords describe(AudioPosition place) {
    final at = editionTime(place);
    final edition = _edition?.id == place.editionId
        ? _edition
        : _editions[place.editionId]?.$2;
    final file = edition?.files
        .where((file) => file.key == place.sourceKey)
        .firstOrNull;
    return (
      short: audioTime(at ?? place.milliseconds),
      chapter: file?.chapterAt(place.milliseconds),
      quote: null,
      along: at == null ? null : AlongAudio(at),
    );
  }

  static int? _editionTime(Edition edition, AudioPosition position) =>
      audioOutline(edition).editionTime(position);

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
  Bookmark<AudioPosition>? get bookmarkHere {
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
    final total = audioOutline(edition).length;
    final elapsed = _editionTime(edition, position);
    return total == null || elapsed == null
        ? null
        : (elapsedMs: elapsed, totalMs: total);
  }

  /// The chapters of the open edition in order, from its audio outline. A
  /// file without a chapter at its start counts as a chapter named after the
  /// file. The list stays the same object until the open edition changes.
  List<PlaybackChapter> get chapters =>
      _edition == null ? const [] : audioOutline(_edition!).chapters;

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

  /// The queue primitive under the command entry points. No command calls
  /// it directly, because it does not say what an [Exception] from [action]
  /// means. A command uses [_audioCommand] or [_recordsCommand].
  ///
  /// Runs [action] after every command queued before it, so that one command
  /// runs at a time. [action] runs only while Playback is open and bound as
  /// it was when the command was queued. Otherwise it does not run, and the
  /// returned future completes normally.
  ///
  /// The returned future completes as [action] completed. A failure goes
  /// only there: to the caller, or to the zone when nothing listens. The
  /// queue itself never fails ([SerialQueue]), so a failed command never
  /// stops a later one.
  Future<void> _inCommandOrder(Future<void> Function() action) {
    final generation = _generation;
    final binding = _binding;
    return _operations.run(() async {
      await binding;
      if (!_closed && generation == _generation) await action();
    });
  }

  /// Queues [action] as an audio command: a command that drives the audio
  /// engine. It runs in the order and under the binding rule of
  /// [_inCommandOrder].
  ///
  /// An [Exception] from [action] is an engine failure. The audio stops,
  /// Playback shows that the file cannot play ([_audioFailed]), and the
  /// returned future completes normally. The failed command of an earlier
  /// binding shows nothing. [operation] names the attempted action; [target]
  /// resolves its edition id when the command starts, before any wait. Without
  /// [target], the command addresses the open edition.
  ///
  /// An [Error] that is not an [Exception] is a bug. It goes to the caller,
  /// and nothing turns it into a message.
  Future<void> _audioCommand(
    PlaybackOperation operation,
    Future<void> Function() action, {
    String? Function()? target,
  }) {
    final generation = _generation;
    return _inCommandOrder(
      () => _runAudio(
        operation,
        action,
        editionId: target == null ? _edition?.id : target(),
        generation: generation,
      ),
    );
  }

  /// Applies the audio-failure rule both to queued commands and to the
  /// automatic reopen inside binding, which cannot queue behind itself.
  Future<void> _runAudio(
    PlaybackOperation operation,
    Future<void> Function() action, {
    required String? editionId,
    required int generation,
  }) async {
    final edition = _editions[editionId]?.$2;
    try {
      await action();
    } on Exception {
      if (!_closed && generation == _generation) {
        await _audioFailed(edition, operation, generation);
      }
    }
  }

  /// Queues [action] as a records command: a command that reads or changes
  /// only the personal records, the settings or the sleep timer, and never
  /// drives the audio engine. It runs in the order and under the binding
  /// rule of [_inCommandOrder].
  ///
  /// An [Exception] from [action] is a records failure. It goes to the
  /// caller, who started the command and reports it. The audio plays on,
  /// and Playback shows no message. A failed save never gets here, because
  /// [_persistChanges] keeps it as the save status.
  ///
  /// An [Error] that is not an [Exception] is a bug. It goes to the caller,
  /// and nothing turns it into a message.
  Future<void> _recordsCommand(Future<void> Function() action) =>
      _inCommandOrder(action);

  /// Handles an error of the sample stream: an engine failure that no
  /// command caused. The handling is queued, so that it runs between
  /// commands and only under the binding that was current when the error
  /// arrived.
  ///
  /// It is neither kind of command, because it is itself the handling of an
  /// engine failure. As an audio command, an [Exception] from it would run
  /// [_audioFailed] a second time. [_audioFailed] already handles the engine
  /// failure of its own pause. Any other failure of it is a bug, which goes
  /// to the zone.
  Future<void> _sampleStreamFailed() {
    final edition = _edition;
    final generation = _generation;
    if (edition == null || _loading || !_decoderReady) return Future.value();
    return _inCommandOrder(() async {
      if (_edition == null || !_sameEdition(edition, _edition!)) return;
      await _audioFailed(edition, PlaybackOperation.decoder, generation);
    });
  }

  Future<void> _audioFailed(
    Edition? edition,
    PlaybackOperation operation,
    int generation,
  ) async {
    var message =
        'Cannot play this local audio file. Download it again or choose another edition.';
    try {
      await engine.pause();
    } on Exception {
      message =
          'The audio device failed. Restart Bookfin before listening again.';
    }
    if (_closed || generation != _generation) return;
    // A library refresh can replace a source without changing accounts while
    // its first open waits. Never attach that old failure to the new source.
    if (edition != null) {
      final current = _editions[edition.id]?.$2;
      if (current == null || !_sameEdition(edition, current)) return;
      _actionFailed(edition.id, operation, message);
    }
    _playing = false;
    _active = false;
    _starting = null;
    reports?.stop();
    _save();
    _requestUpload();
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
        final current = _editions[_edition!.id];
        if (current == null ||
            _position?.fits(current.$2) != true ||
            !_sameEdition(current.$2, _edition!)) {
          await bind(null, []);
          await bind(session, books);
        } else {
          _book = current.$1;
          _edition = current.$2;
          _notify();
        }
      }
      await _binding;
      if (generation != _generation) return;
      // The library can arrive after the account, so the saved book may
      // only now be in [books].
      if (_edition == null && _restored) {
        if (_selectedEdition() case (final book, final edition)) {
          final resume = _readPosition(edition);
          if (resume != null && !_resumeFits(edition, _resumeRecord(edition))) {
            _offerReplacement(book, edition, resume);
          } else if (resume != null) {
            unawaited(
              _audioCommand(PlaybackOperation.open, () async {
                if (_edition == null &&
                    _selected == edition.id &&
                    _currentEdition(book, edition)) {
                  await _open(book, edition, autoplay: false);
                }
              }, target: () => edition.id),
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
    _playChoice = null;
    _choiceToRestore = null;
    _lastUploadPosition = null;
    _playing = false;
    _active = false;
    _starting = null;
    _decoderReady = false;
    _resumes = {};
    _history = [];
    _bookmarks = [];
    _changedHistory.clear();
    _changedBookmarks.clear();
    _undo = null;
    _invalidateSlider();
    _selected = null;
    _speed = 1;
    _backward = 10;
    _forward = 30;
    _actionNotice = null;
    _recoveryMessage = null;
    _cancelSleep();
    _notify();
    final previousBinding = _binding;
    final previousOperations = _operations.idle;
    final ready = Completer<void>();
    _binding = ready.future;
    try {
      await previousBinding;
      await previousOperations;
      await engine.pause();
      await _writes.idle;
      if (session == null || generation != _generation) return;
      try {
        final pending = _pendingWrites[session.scope.key];
        final stored = await store.read(session.scope.key);
        final saved = pending == null ? stored : pending.applyTo(stored);
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
                  (value) => HistoryEvent.fromJson(
                    Map<String, dynamic>.from(value as Map),
                    decodePosition,
                  ),
                )
                .toList();
            _bookmarks = (saved['bookmarks'] as List)
                .map(
                  (value) => Bookmark.fromJson(
                    Map<String, dynamic>.from(value as Map),
                    decodePosition,
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
        if (store.setAside(session.scope.key)) {
          _recoveryMessage = 'Saved listening records were damaged. Bookfin kept a copy and restored the records that it could read. The next sync restores the rest.';
        }
        _choiceToRestore = (saved?['playChoice'] as Map?)
            ?.cast<String, dynamic>();
        await _restoreSelected();
      } on Exception {
        if (generation != _generation) return;
        if (!_restored) {
          _history = [];
          _bookmarks = [];
        }
        _recoveryMessage = 'Cannot restore listening position. Saved listening data was not removed.';
      } on TypeError {
        if (generation != _generation) return;
        if (!_restored) {
          _history = [];
          _bookmarks = [];
        }
        _recoveryMessage = 'Cannot restore listening position. Saved listening data was not removed.';
      }
      _notify();
    } finally {
      ready.complete();
    }
  }

  /// The bound book and edition that were open when this account last saved.
  (Book, Edition)? _selectedEdition() =>
      _selected == null ? null : _editions[_selected];

  /// Reopens the edition that was open when this account last saved, paused
  /// at its saved position. Does nothing while that edition is not in the
  /// bound books.
  Future<void> _restoreSelected() async {
    final selected = _selectedEdition();
    if (selected == null) return;
    final (book, edition) = selected;
    if (_choiceToRestore?['sources'] == editionSources(edition)) {
      await _open(book, edition, autoplay: false);
      return;
    }
    final resume = _readPosition(edition);
    if (resume == null || !_resumeFits(edition, _resumeRecord(edition))) {
      _actionFailed(
        edition.id,
        PlaybackOperation.open,
        'The saved audio source changed. Its resume is kept but was not applied.',
      );
      if (resume != null) _offerReplacement(book, edition, resume);
    } else {
      await _runAudio(
        PlaybackOperation.open,
        () async {
          await _open(book, edition, autoplay: false);
        },
        editionId: edition.id,
        generation: _generation,
      );
    }
  }

  /// Whether [a] and [b] describe the same audio: the same edition id, and
  /// the same source files in the same order at the same revisions. A library
  /// refresh rebuilds every book and edition as new objects, so identity
  /// cannot tell whether the audio changed.
  bool _sameEdition(Edition a, Edition b) =>
      a.id == b.id &&
      listEquals(
        [for (final file in a.files) (file.key, file.revision)],
        [for (final file in b.files) (file.key, file.revision)],
      );

  /// The bound objects of [edition] in [book], or null when the bound
  /// account's library no longer has that book with the same audio. Work
  /// that waits uses this after each wait, so a library refresh that
  /// replaces equal objects neither stops it nor leaves it holding the old
  /// objects.
  (Book, Edition)? _bound(Book book, Edition edition) {
    if (_session == null) return null;
    final found = _editions[edition.id];
    if (found == null ||
        found.$1.id != book.id ||
        !_sameEdition(found.$2, edition)) {
      return null;
    }
    return found;
  }

  bool _currentEdition(Book book, Edition edition) =>
      _bound(book, edition) != null;

  void _offerReplacement(Book book, Edition edition, AudioPosition resume) {
    if (!_restored || !_currentEdition(book, edition)) return;
    _replacementStart = AudioReplacement(book, edition, resume);
  }

  bool _resumeFits(Edition edition, Map<String, dynamic>? value) =>
      value != null &&
      (value['sources'] == null ||
          value['sources'] == editionSources(edition)) &&
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

  Future<void> open(Book book, Edition edition, {bool autoplay = true}) {
    if (autoplay) _start(edition);
    return _settleStart(
      _audioCommand(PlaybackOperation.open, () async {
        if (autoplay && _edition != null && _sameEdition(_edition!, edition)) {
          await _play();
        } else {
          await _open(book, edition, autoplay: autoplay);
        }
      }, target: () => edition.id),
    );
  }

  /// Shows [edition] as starting, at once, before the command waits.
  void _start(Edition edition) {
    if (_closed) return;
    _starting = edition;
    _publish();
  }

  /// Ends the start when [command] ended without sound to wait for. A command
  /// that called the decoder's play leaves the start to the first sound.
  Future<void> _settleStart(Future<void> command) => command.whenComplete(() {
    if (_starting != null && (!_active || _playing)) _endStart();
  });

  void _endStart() {
    if (_closed || _starting == null) return;
    _starting = null;
    _publish();
  }

  /// The saved files of [edition] in order, or null when any of them is not
  /// saved on this device. The lookups run together: each one can take a
  /// look at storage, and an edition can have dozens of files.
  Future<List<Uri>?> _savedFiles(Edition edition) async {
    final found = await Future.wait([
      for (final file in edition.files) downloads.localFile(file),
    ]);
    return found.every((uri) => uri?.scheme == 'file')
        ? found.cast<Uri>()
        : null;
  }

  /// True only when this account's selection was loaded and committed.
  Future<bool> _open(
    Book book,
    Edition edition, {
    required bool autoplay,
    AudioPosition? target,
    HistoryAction? action,
    AudioReplacement? replacement,
  }) async {
    var bound = _bound(book, edition);
    if (bound == null ||
        edition.kind != EditionKind.audio ||
        edition.files.isEmpty) {
      throw ArgumentError('Choose an audio edition from the current account.');
    }
    (book, edition) = bound;
    if (!_restored) {
      _recoveryMessage = 'Cannot restore listening records. Restart Bookfin before listening. Saved listening data was not removed.';
      _notify();
      return false;
    }
    final generation = _generation;
    // An open at the saved place asks where that place came from while the
    // audio loads. A failed query knows nothing.
    final account = _session!.scope.key;
    final origin = target != null || replacement != null
        ? null
        : store
              .origin(account, edition)
              .then<PlaceOrigin?>(
                (value) => value,
                onError: (Object _) => null,
              );
    final restoringChoice =
        _choiceToRestore?['sources'] == editionSources(edition);
    final opening = await Future.wait<Object?>([
      _savedFiles(edition),
      if (restoringChoice) origin ?? Future<PlaceOrigin?>.value(),
    ]);
    final files = opening[0] as List<Uri>?;
    final recovered = restoringChoice ? opening[1] as PlaceOrigin? : null;
    if (generation != _generation) return false;
    bound = _bound(book, edition);
    if (bound == null) return false;
    (book, edition) = bound;
    if (files == null) {
      _actionFailed(
        edition.id,
        PlaybackOperation.open,
        'Download every file in this audio edition before listening.',
      );
      _notify();
      return false;
    }
    final own = recovered?.own;
    final resume = replacement != null
        ? null
        : target ??
              (own is AudioPosition && own.fits(edition)
                  ? own
                  : _readPosition(edition));
    if (resume != null &&
        (!resume.fits(edition) ||
            target == null &&
                !restoringChoice &&
                !_resumeFits(edition, _resumeRecord(edition)))) {
      _actionFailed(
        edition.id,
        PlaybackOperation.open,
        'The saved audio source changed. Its resume is kept but was not applied.',
      );
      _offerReplacement(book, edition, resume);
      _notify();
      return false;
    }
    _loading = true;
    _decoderReady = false;
    try {
      await engine.pause();
      _save();
      if (_edition != null) _requestUpload();
      reports?.stop();
      final fileIndex = resume == null
          ? 0
          : edition.files.indexWhere((file) => file.key == resume.sourceKey);
      await engine.load(files, fileIndex, resume?.milliseconds ?? 0);
      await engine.speed(_speed);
      final confirmed = target == null
          ? AudioSample(fileIndex, resume?.milliseconds ?? 0)
          : await engine.seek(fileIndex, target.milliseconds);
      final known = await origin;
      // Refresh can run while the decoder loads. Reconcile against the
      // journal at confirmation, not the question from before that wait.
      final currentResume = restoringChoice
          ? await store.listeningResume(account, edition)
          : null;
      bound = generation == _generation ? _bound(book, edition) : null;
      if (bound == null ||
          replacement != null && !identical(replacement, _replacementStart)) {
        await engine.pause();
        if (generation == _generation) {
          _playing = false;
          _active = false;
          _notify();
        }
        return false;
      }
      (book, edition) = bound;
      if (confirmed.fileIndex < 0 ||
          confirmed.fileIndex >= edition.files.length) {
        throw const FormatException(
          'The decoder did not confirm an edition source.',
        );
      }
      final previous = _position;
      _book = book;
      if (target == null || _edition?.id != edition.id) {
        _playChoice = null;
      }
      if (target == null || _edition?.id != edition.id) _invalidateSlider();
      if (target == null) _undo = null;
      _edition = edition;
      _selected = edition.id;
      _playing = false;
      _active = autoplay;
      _position = _positionForSample(confirmed);
      _decoderReady = true;
      final savedChoice = _choiceToRestore;
      _choiceToRestore = null;
      if (restoringChoice) {
        // Reopening an unresolved question is not a choice of resume. The
        // journal's last local action supplies this phone's decoder place.
        _recordedDecoderAnchor = _decoderAnchor;
        _reconcileListeningChoice(currentResume, saved: savedChoice);
      }
      _replacementStart = null;
      if (action != null) {
        _record(action, previous ?? _position!, _position!);
      } else if (openedFrom(known, _position!, _history) case final own?
          when own.fits(edition)) {
        // The edition opened at another device's place: a move from this
        // phone's own place, which Undo can take back.
        _record(HistoryAction.open, own, _position!, device: known!.device);
      }
      _actionNotice = null;
      _cancelSleep();
    } finally {
      _loading = false;
    }
    _save();
    _lastUploadPosition = _position;
    if (target != null) await _writes.idle;
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
    // The first sound ends any start. A start that a later command took
    // over must not wait for a sound of its own edition.
    if (_playing && !wasPlaying) _starting = null;
    if (wasPlaying != _playing && _commandAction == null) {
      _record(
        sample.completed
            ? HistoryAction.completion
            : _playing
            ? HistoryAction.resume
            : HistoryAction.interruption,
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
    final lastUpload = _lastUploadPosition;
    if (wasPlaying && !_playing ||
        _playing &&
            (lastUpload == null ||
                lastUpload.sourceKey != file.key ||
                (milliseconds - lastUpload.milliseconds).abs() >=
                    LiveReports.progressIntervalMs)) {
      _requestUpload();
    }
    if (sample.completed && _active) {
      _active = false;
      _cancelSleep();
      unawaited(_audioCommand(PlaybackOperation.stop, engine.pause));
    }
    if (wasPlaying == _playing && !sample.completed) {
      _publish();
    } else {
      _notify();
    }
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

  Future<void> play() {
    if (!_playing && _edition != null) _start(_edition!);
    return _settleStart(_audioCommand(PlaybackOperation.play, _play));
  }

  /// System media controls start locally and leave the question for a screen.
  Future<void> playExternally() {
    if (!_playing && _edition != null) _start(_edition!);
    return _settleStart(_audioCommand(PlaybackOperation.play, () => _play(external: true)));
  }

  Future<void> _play({bool external = false}) async {
    if (_edition == null || _playing) return;
    if (_playChoice != null) {
      _playChoice!._requested = true;
      if (!external) {
        _notify();
        return;
      }
    }
    final generation = _generation;
    if (!_decoderReady) {
      final loaded = await _open(
        _book!,
        _edition!,
        autoplay: false,
        target: _position,
      );
      if (!loaded || generation != _generation) return;
    }
    final saved = await _savedFiles(_edition!);
    if (generation != _generation) return;
    if (saved == null) {
      _actionFailed(
        _edition!.id,
        PlaybackOperation.play,
        'Download every file in this audio edition before listening.',
      );
      _notify();
      return;
    }
    if (durationMilliseconds != null &&
        editionMilliseconds == durationMilliseconds) {
      if (!await _seekPosition(0, 0, HistoryAction.seek)) return;
    }
    if (_playChoice != null && !external) {
      _playChoice!._requested = true;
      _notify();
      return;
    }
    if (external && _playChoice != null) {
      _playChoice!._requested = true;
      _recordedDecoderAnchor = null;
      _preserveListeningChoice();
      _save();
      await _writes.idle;
      if (generation != _generation || saveFailed) return;
    }
    _active = true;
    await engine.play();
    if (generation != _generation) return;
    _actionNotice = null;
    _notify();
  }

  /// Cancels this presentation. The alternatives remain recoverable and a
  /// later Play asks again. A newer request is never cancelled by an old sheet.
  void cancelListeningChoice(ListeningChoice choice) {
    if (!identical(choice, _playChoice)) return;
    choice._requested = false;
    _save();
    _notify();
  }

  /// Accepts an answer only for the current account, recording and request.
  /// Preservation and the chosen resume use the existing writer. Failed saves
  /// leave the request available for retry and never start audio.
  Future<void> chooseListeningPlace(
    ListeningChoice choice,
    ListeningPlace place,
  ) => _audioCommand(PlaybackOperation.play, () async {
    if (!identical(choice, _playChoice)) return;
    final generation = _generation;
    _preserveListeningChoice();
    _save();
    await _writes.idle;
    if (generation != _generation ||
        saveFailed ||
        !identical(choice, _playChoice)) {
      return;
    }
    if (place == ListeningPlace.otherDevice) {
      final target = choice.remote;
      if (!await _seekPosition(
        _edition!.files.indexWhere((file) => file.key == target.sourceKey),
        target.milliseconds,
        HistoryAction.open,
        device: choice.device,
        choice: choice,
      )) {
        return;
      }
      if (!identical(choice, _playChoice) || saveFailed) return;
    }
    _playChoice = null;
    // Choosing the unchanged phone place must replace the adopted remote
    // resume too; a decoder-position comparison alone would skip this save.
    _recordedDecoderAnchor = null;
    _save();
    await _writes.idle;
    if (generation != _generation) return;
    if (saveFailed) {
      _playChoice = choice;
      _playChoice!._requested = true;
      _save();
      await _writes.idle;
      _notify();
      return;
    }
    _notify();
    await _play();
  });

  /// Refresh and restart use the same validity rule. A durable question's
  /// replacement or withdrawal is saved without choosing a resume.
  void _reconcileListeningChoice(
    ListeningResume? origin, {
    Map<String, dynamic>? saved,
  }) {
    final before = saved ?? _savedListeningChoice;
    _playChoice = _currentListeningChoice(
      origin,
      saved == null ? _playChoice : _readListeningChoice(saved),
    );
    if (before != null) {
      _preserveListeningChoice();
      if (!mapEquals(before, _savedListeningChoice)) _save(saveResume: false);
    }
  }

  ListeningChoice? _currentListeningChoice(
    ListeningResume? origin,
    ListeningChoice? choice,
  ) {
    final edition = _edition;
    final position = _position;
    if (choice?._historyId case final id?
        when !_history.any((event) => event.id == id)) {
      choice = null;
    }
    if (edition == null || position == null || origin == null) return null;
    final value = origin.version.value;
    if (value is! ResumeValue ||
        value.position is! AudioPosition ||
        !(value.position as AudioPosition).fits(edition)) {
      return null;
    }
    if (!origin.elsewhere) return choice;
    final remote = value.position as AudioPosition;
    if (samePlace(position, remote)) {
      return null;
    }
    if (choice?._version == origin.version ||
        choice != null &&
            choice._version == null &&
            choice._identity == origin.version.identity &&
            samePlace(choice.remote, remote)) {
      return choice;
    }
    return ListeningChoice._(
      local: position,
      remote: remote,
      identity: origin.version.identity,
      sources: editionSources(edition),
      device: origin.version.device,
      version: origin.version,
      requested: choice?._requested ?? false,
    );
  }

  /// Keeps the two alternatives as ordinary History entries in the very
  /// transaction that may replace the resume. No decoder move or Undo is
  /// invented by preservation. The history id is the durable choice target.
  void _preserveListeningChoice() {
    final choice = _playChoice;
    if (choice == null || choice._historyId != null) return;
    _record(HistoryAction.preserve, choice.local, choice.local);
    _record(
      HistoryAction.preserve,
      choice.remote,
      choice.remote,
      device: choice.device ?? 'Other device',
    );
    choice._historyId = _history.last.id;
  }

  Map<String, dynamic>? get _savedListeningChoice {
    final choice = _playChoice;
    if (choice == null) return _choiceToRestore;
    if (choice._historyId == null) return null;
    return {
      'history': choice._historyId,
      'identity': choice._identity,
      'sources': choice._sources,
      'requested': choice._requested,
    };
  }

  ListeningChoice? _readListeningChoice(Map<String, dynamic> saved) {
    if (_edition == null ||
        _position == null ||
        saved['sources'] != editionSources(_edition!)) {
      return null;
    }
    final event = _history
        .where((event) => event.id == saved['history'])
        .firstOrNull;
    if (event == null || !event.after.fits(_edition!)) return null;
    return ListeningChoice._(
      local: _position!,
      remote: event.after,
      device: event.device,
      identity: saved['identity'] as String,
      sources: saved['sources'] as String,
      historyId: event.id,
      requested: saved['requested'] == true,
    );
  }

  Future<void> pause() {
    _endStart();
    return _audioCommand(PlaybackOperation.pause, _pause);
  }

  Future<void> _pause() async {
    final generation = _generation;
    _commandAction = HistoryAction.pause;
    try {
      await engine.pause();
      if (generation != _generation) return;
      if (_active) _record(HistoryAction.pause, _position!, _position!);
    } finally {
      _commandAction = null;
    }
    _playing = false;
    _save();
    _requestUpload();
    await _writes.idle;
    _notify();
  }

  Future<void> stop() {
    _endStart();
    return _audioCommand(PlaybackOperation.stop, _stop);
  }

  Future<void> _stop() async {
    final generation = _generation;
    _commandAction = HistoryAction.stop;
    try {
      await engine.pause();
      if (generation != _generation) return;
      if (_active) _record(HistoryAction.stop, _position!, _position!);
    } finally {
      _commandAction = null;
    }
    _playing = false;
    _active = false;
    _cancelSleep();
    reports?.stop();
    _save();
    _requestUpload();
    await _writes.idle;
    _notify();
  }

  Future<void> seekEdition(int milliseconds) =>
      _audioCommand(PlaybackOperation.seek, () => _seekEdition(milliseconds));

  Future<void> _seekEdition(
    int milliseconds, {
    HistoryAction kind = HistoryAction.seek,
    _SliderGesture? gesture,
  }) async {
    if (_edition == null) return;
    final duration = durationMilliseconds;
    if (duration == null) {
      _actionFailed(
        _edition!.id,
        PlaybackOperation.seek,
        'Choose a chapter or file. The recording length is not available.',
      );
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

  Future<void> seekSource(String sourceKey, int milliseconds) => _audioCommand(
    PlaybackOperation.seek,
    () => _seekSource(sourceKey, milliseconds),
  );

  Future<void> _seekSource(
    String sourceKey,
    int milliseconds, {
    HistoryAction kind = HistoryAction.chapter,
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

  Future<void> jump({required bool forward}) =>
      _audioCommand(PlaybackOperation.seek, () async {
        final current = editionMilliseconds;
        final amount = (forward ? _forward : -_backward) * 1000;
        if (current != null && durationMilliseconds != null) {
          await _seekEdition(current + amount, kind: HistoryAction.jump);
        } else if (_position != null) {
          await _seekSource(
            _position!.sourceKey,
            max(0, _position!.milliseconds + amount),
            kind: HistoryAction.jump,
          );
        }
      });

  void _record(
    HistoryAction kind,
    AudioPosition before,
    AudioPosition after, {
    String? device,
    _Counterpart? counterpart,
  }) {
    assert(
      _restored && _book != null && _edition != null && after.fits(_edition!),
    );
    final event = HistoryEvent(
      id: recordId(),
      at: DateTime.now().toUtc(),
      kind: kind,
      before: before,
      after: after,
      bookTitle: _book!.title,
      editionLabel: _edition!.label,
      device: device,
      counterpartOf: counterpart?.place,
      matchedBy: counterpart?.matchedBy,
    );
    _history = [..._history, event];
    _changedHistory[event.id] = event.toJson();
    if (event.changesPosition) _undo = event;
  }

  /// True only after a confirmed position and its action were committed.
  /// A choice must still be current when the decoder confirms the move.
  /// Otherwise restore the decoder before publishing or saving any move.
  Future<bool> _seekPosition(
    int index,
    int milliseconds,
    HistoryAction kind, {
    AudioPosition? before,
    String? device,
    ListeningChoice? choice,
    _SliderGesture? gesture,
    _Counterpart? counterpart,
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
    if (choice != null && !identical(choice, _playChoice)) return false;
    assert(_edition != null && index >= 0 && index < _edition!.files.length);
    _seeking = true;
    late final AudioSample confirmed;
    try {
      confirmed = await engine.seek(index, milliseconds);
      if (generation != _generation) return false;
      if (choice != null && !identical(choice, _playChoice)) {
        // Samples stay suppressed until the rejected seek has been undone.
        // A failed restoration leaves the decoder unusable; the ordinary
        // audio failure path pauses it and a later Play reloads the local place.
        _decoderReady = false;
        final restored = await engine.seek(
          _edition!.files.indexWhere((file) => file.key == previous.sourceKey),
          previous.milliseconds,
        );
        if (generation != _generation) return false;
        if (restored.fileIndex < 0 ||
            restored.fileIndex >= _edition!.files.length ||
            !samePlace(_positionForSample(restored), previous)) {
          throw const FormatException(
            'The decoder did not restore the local place.',
          );
        }
        _decoderReady = true;
        return false;
      }
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
    _record(
      kind,
      previous,
      _position!,
      device: device,
      counterpart: counterpart,
    );
    _accept(confirmed);
    _save();
    await _writes.idle;
    _notify();
    return generation == _generation;
  }

  Future<void> setSpeed(double value) =>
      _audioCommand(PlaybackOperation.speed, () async {
        if (!value.isFinite || value < 0.5 || value > 3) {
          throw ArgumentError('Playback speed must be between 0.5 and 3.');
        }
        await engine.speed(value);
        _speed = value;
        _save();
        _notify();
      });

  Future<void> setJumps(int backward, int forward) => _recordsCommand(() async {
    if (backward < 1 || forward < 1 || backward > 300 || forward > 300) {
      throw ArgumentError('Short jumps must be between 1 and 300 seconds.');
    }
    _backward = backward;
    _forward = forward;
    _save();
    _notify();
  });

  Future<void> setSleep(Duration? duration) => _recordsCommand(() async {
    if (duration != null && duration <= Duration.zero) {
      throw ArgumentError('Choose a future sleep time.');
    }
    _cancelSleep();
    if (duration != null) {
      _sleepDeadline = DateTime.now().add(duration);
      _sleepTimer = duration;
      _sleep = Timer(duration, () {
        _cancelSleep();
        _publishSleep();
        unawaited(pause());
      });
      _sleepCountdown = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _publishSleep(),
      );
    }
    _notify();
  });

  void _cancelSleep() {
    _sleep?.cancel();
    _sleep = null;
    _sleepCountdown?.cancel();
    _sleepCountdown = null;
    _sleepDeadline = null;
    _sleepTimer = null;
  }

  /// The time left on the sleep timer, counted on the timers' own clock.
  Duration? get _sleepLeft => _sleepTimer == null
      ? null
      : _sleepTimer! - Duration(seconds: _sleepCountdown!.tick);

  void _publishSleep() {
    if (!_closed) _sleepSignal.value = _sleepLeft;
  }

  // NOTE: This encode stays on the UI isolate. It encodes a few short
  // strings once per save, about once a second, which costs far less than
  // the fixed cost of a hop to another isolate.
  String? get _decoderAnchor => _position == null || _edition == null
      ? null
      : jsonEncode([editionSources(_edition!), encodePosition(_position!)]);

  /// Hands the store the records changed since the last save, with the
  /// current settings. The changes stay pending until the store saves them.
  /// Choice reconciliation saves its marker and History without a resume.
  void _save({bool saveResume = true}) {
    final accountKey = _session?.scope.key;
    if (accountKey == null || !_restored) return;
    ++_recordRevision;
    final resumes = <String, List<Map<String, dynamic>>>{};
    final position = _position;
    final decoderAnchor = _decoderAnchor;
    if (saveResume &&
        position != null &&
        decoderAnchor != _recordedDecoderAnchor) {
      _preserveListeningChoice();
      final records = _resumes.putIfAbsent(position.editionId, () => []);
      // A legacy file-relative position can be read but cannot establish
      // ownership of a whole recording. Keep it when saving a known recording.
      final index = records.lastIndexWhere(
        (value) => value['sources'] == editionSources(_edition!),
      );
      final value = <String, dynamic>{
        'source': position.sourceKey,
        'revision': position.revision,
        'sources': editionSources(_edition!),
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
      resumes[position.editionId] = [
        for (final value in records) Map<String, dynamic>.from(value),
      ];
      _recordedDecoderAnchor = decoderAnchor;
    }
    final changes = ListeningChanges(
      {
        'version': 3,
        'selected': _selected,
        'speed': _speed,
        'backward': _backward,
        'forward': _forward,
        'playChoice': _savedListeningChoice,
      },
      history: Map.of(_changedHistory),
      bookmarks: Map.of(_changedBookmarks),
      resumes: resumes,
    );
    _changedHistory.clear();
    _changedBookmarks.clear();
    final value = _pendingWrites[accountKey]?.followedBy(changes) ?? changes;
    _pendingWrites[accountKey] = value;
    // Nothing holds the future of this save. A failed save is the save
    // status of [_persistChanges]. A bug in the save goes to the zone, and
    // the queue runs the next save all the same. The changes stay pending,
    // so the next save and [flush] send them again.
    unawaited(_writes.run(() => _persistChanges(accountKey, value)));
  }

  Future<void> _persistChanges(
    String accountKey,
    ListeningChanges value,
  ) async {
    try {
      await store.save(accountKey, value);
      if (identical(_pendingWrites[accountKey], value)) {
        final status = _status;
        _pendingWrites.remove(accountKey);
        _failedAccounts.remove(accountKey);
        if (!_closed && _session?.scope.key == accountKey) {
          // A save that ends no failure changes only [undoNotifier].
          _status == status ? _publish() : _notify();
        }
      }
    } on Exception {
      _failedAccounts.add(accountKey);
      if (_session?.scope.key == accountKey) {
        _notify();
      }
    }
  }

  /// Saves the current confirmed place and retries the pending changes of
  /// every account, waiting only for local record writes. A retry that fails
  /// leaves its changes pending. Audio commands, account restoration and
  /// live Jellyfin reports never delay this flush. To wait for a command's
  /// result, await that command; it saves the records it produces itself.
  ///
  /// A save that fails with an [Exception] is an expected failure, such as
  /// full storage. Its report is the save status ([unsavedChanges] and the
  /// status notifier), so this future completes normally, as the flush of
  /// the reader session does. Callers that drop the future, such as the
  /// app when it goes to the background, then leave no uncaught error. A
  /// save that fails with an [Error] is a bug and goes to the caller.
  Future<void> flush() async {
    // _position changes only when the decoder confirms it. During binding,
    // _save guards unrestored records; bind already queued the old account's
    // changes before clearing its selection.
    if (_decoderAnchor != _recordedDecoderAnchor) _save();
    await _writes.idle;
    // An account change keeps pending records under their original account.
    // They need a retry even after that account was unbound.
    await Future.wait([
      for (final entry in _pendingWrites.entries)
        _writes.run(() => _persistChanges(entry.key, entry.value)),
    ]);
  }

  /// Stops playback and flushes records before releasing its resources.
  /// Teardown completes even when the final save fails. The failure is
  /// reported as [flush] reports it: an [Exception] as the save status, a
  /// bug to the caller. The pending changes stay available to [flush].
  Future<void> close() async {
    if (_closed) return;
    try {
      await stop();
      await flush();
    } finally {
      _unregisterWriter?.call();
      reports?.stop();
      await reports?.idle;
      reports?.close();
      _closed = true;
      _cancelSleep();
      await _samples.cancel();
      await engine.close();
      for (final signal in _signals) {
        signal.dispose();
      }
      super.dispose();
    }
  }

  List<ChangeNotifier> get _signals => [
    _uploadRequests,
    _positionSignal,
    _selectionSignal,
    _sleepSignal,
    _recordsSignal,
    _librarySignal,
    _settingsSignal,
    _statusSignal,
    _undoSignal,
    _startingSignal,
    _playChoiceSignal,
  ];

  /// Publishes the current state to the narrow signals, then to the broad
  /// listeners.
  void _notify() {
    if (_closed) return;
    _publish();
    notifyListeners();
  }

  /// Shows the current state in each narrow signal. A signal notifies only
  /// when its own value changed.
  void _publish() {
    _positionSignal.value = _position;
    _selectionSignal.value = _selection;
    _sleepSignal.value = _sleepLeft;
    _recordsSignal.value = _records;
    _librarySignal.value = _books;
    _settingsSignal.value = _settings;
    _statusSignal.value = _status;
    _undoSignal.value = _undoOffer;
    _startingSignal.value = _starting;
    _playChoiceSignal.value = _playChoice?._requested == true
        ? _playChoice
        : null;
  }

  PlaybackSelection get _selection =>
      (book: _book, edition: _edition, playing: _playing, active: _active);

  PlaybackSettings get _settings =>
      (speed: _speed, backward: _backward, forward: _forward);

  PlaybackStatus get _status => (
    actionNotice: _actionNotice,
    recoveryMessage: _recoveryMessage,
    saveFailed: saveFailed,
  );

  void _actionFailed(
    String editionId,
    PlaybackOperation operation,
    String message,
  ) {
    _actionNotice = (
      editionId: editionId,
      operation: operation,
      message: message,
    );
  }

  /// The undo offer. Its action is saved once no unconfirmed write of the
  /// bound account holds it.
  UndoOffer<AudioPosition>? get _undoOffer => switch (_undo) {
    null => null,
    final action => (
      action: action,
      saved:
          _pendingWrites[_session?.scope.key]?.history.containsKey(action.id) !=
          true,
    ),
  };

  // The record lists and the resume map are replaced, never changed in
  // place, when records change, so their identities tell whether they
  // changed. [_save] changes the open edition's resume in place.
  Object get _records => (_historyList, _bookmarkList, _resumes);

  /// Throws a [StateError] when an invariant fails. Run it on demand from a
  /// test or a debug switch, when no command is in flight:
  /// - The selection, the position and the account agree, and the open book
  ///   and edition are the bound library's own objects.
  /// - A sleep timer, its length, its deadline and its countdown agree.
  /// - Each narrow signal shows the state that it names.
  /// - A pending listening choice belongs to the open recording; a kept
  ///   choice references its recoverable History entry. Its narrow signal
  ///   exposes only requested presentations, never a refresh alone.
  /// - The personal records, the pending writes and the replacement offer
  ///   agree.
  /// - Action and recovery notices belong to a signed-in binding. Save failure
  ///   is derived from that account's unconfirmed writes, never from text.
  void checkInvariants() {
    if (_session == null &&
        (_actionNotice != null || _recoveryMessage != null)) {
      throw StateError('Notices require their signed-in binding.');
    }
    if ((_edition == null) != (_position == null) ||
        (_edition == null) != (_book == null) ||
        _decoderReady && _edition == null ||
        _playing && _position == null ||
        _position != null &&
            (!_position!.fits(_edition!) || _session == null) ||
        _edition != null &&
            (!identical(_editions[_edition!.id]?.$1, _book) ||
                !identical(_editions[_edition!.id]?.$2, _edition))) {
      throw StateError(
        'Playback selection, source position, and account must agree.',
      );
    }
    if ((_sleep == null) != (_sleepTimer == null) ||
        (_sleepTimer == null) != (_sleepDeadline == null) ||
        (_sleepTimer == null) != (_sleepCountdown == null)) {
      throw StateError(
        'A sleep timer, its length, its deadline and its countdown agree.',
      );
    }
    if (!_closed &&
        (!identical(_positionSignal.value, _position) ||
            _selectionSignal.value != _selection ||
            _sleepSignal.value != _sleepLeft ||
            _recordsSignal.value != _records ||
            !identical(_librarySignal.value, _books) ||
            _settingsSignal.value != _settings ||
            _statusSignal.value != _status ||
            _undoSignal.value != _undoOffer)) {
      throw StateError('Each narrow signal shows the state that it names.');
    }
    final choice = _playChoice;
    if (choice != null &&
            (_edition == null ||
                !choice.local.fits(_edition!) ||
                !choice.remote.fits(_edition!) ||
                choice._sources != editionSources(_edition!) ||
                choice._historyId != null &&
                    !_history.any(
                      (event) =>
                          event.id == choice._historyId &&
                          samePlace(event.after, choice.remote),
                    )) ||
        !_closed &&
            _playChoiceSignal.value !=
                (choice?._requested == true ? choice : null)) {
      throw StateError(
        'The listening choice must belong to its open recording and History.',
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
        _changedHistory.isNotEmpty ||
        _changedBookmarks.isNotEmpty ||
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
typedef EditionBookmark = ({Bookmark<AudioPosition> bookmark, int at});

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
