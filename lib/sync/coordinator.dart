import 'dart:async';

import 'package:flutter/foundation.dart';

import '../catalog/jellyfin.dart';
import '../playback/playback.dart';
import '../playback/store.dart';
import '../reader/session.dart';
import 'journal.dart' show DeepCollectionEquality;

/// What the Sync page shows about an action that the user started: Sync now
/// or a choice between saved versions.
/// - [busy]: the action runs now.
/// - [message]: what the latest such action tells the user beyond how its
///   sync ended, which [RecordSync.lastSyncNotifier] says: why a choice was
///   not saved. Null otherwise.
typedef RecordSyncStatus = ({bool busy, String? message});

/// Why a sync failed.
enum RecordSyncFailure {
  /// Jellyfin could not be reached: no network, a timeout, or a server
  /// error.
  unreachable,

  /// Jellyfin answered, but it has no Bookfin Storage plugin that this app
  /// can use: the plugin's routes are not found, or its answers do not
  /// follow the storage contract.
  pluginMissing,

  /// The personal records on this phone could not be read.
  unreadable,

  /// Another cause, for example storage on this phone that could not be
  /// written, or a sign-in that expired.
  other,
}

/// How the latest sync ended.
/// - [at]: when it ended.
/// - [failure]: why it failed, or null when it succeeded.
/// - [synced]: when the latest successful sync of this account ended, or
///   null before the first one. A failed sync keeps it.
/// - [replaced]: how many damaged records on this phone it replaced by the
///   server's copy.
typedef RecordSyncOutcome = ({
  DateTime at,
  RecordSyncFailure? failure,
  DateTime? synced,
  int replaced,
});

/// The records with saved versions to choose between: each record address
/// with its saved versions.
typedef RecordConflicts = Map<String, List<Map<String, dynamic>>>;

/// What one sync or choice tells the user who started it beyond how its
/// sync ended, or null when nothing.
typedef _Result = ({String? message});

/// Synchronizes personal records with Jellyfin for the signed-in account.
///
/// It alone decides when a background sync runs. Signing in ([bind]) makes
/// a sync due at once. While the app is in front, a periodic sync runs every
/// [_period]. While it is in the background ([suspend]), no sync runs. On
/// [resume], a sync that came due in the background runs at once, and the
/// period restarts.
///
/// A background sync is one that the app starts: [synchronize], from the
/// period, from [resume] and after sign-in. It shows no busy state and no
/// message. After a sync, Playback and the reader refresh only when the
/// store reports that records of their domain changed outside them, and the
/// conflicts notify only when they differ. The user starts [syncNow] and
/// [resolve], which show busy in [statusNotifier] until they end, and then
/// why a choice was not saved. Every sync sets [lastSyncNotifier], which
/// says how it ended and why it failed, and [conflictsNotifier].
///
/// One sync or choice runs at a time. A background sync that comes due while
/// another runs is skipped, because the running one covers it. An action of
/// the user waits for the running one and then runs.
///
/// Invariants, which [checkInvariants] proves:
/// - A signed-out coordinator is idle and holds no message, no outcome and
///   no conflicts.
class RecordSync {
  static const _period = Duration(seconds: 30);

  RecordSync({
    required this.records,
    this.playback,
    this.reader,
    this.now = DateTime.now,
  });
  final LocalResumeStore records;
  final DateTime Function() now;
  final Playback? playback;
  final ReaderSession? reader;
  JellyfinSession? _session;
  JellyfinClient? _client;
  Timer? _timer;
  // When the latest sync of this account started, or null before the first,
  // which is due at once.
  DateTime? _periodStart;
  bool _suspended = false;
  int _generation = 0;
  bool _disposed = false;

  /// The sync or choice of this account that runs now, or null.
  Future<void>? _running;
  final _status = ValueNotifier<RecordSyncStatus>(_idle);
  final _lastSync = ValueNotifier<RecordSyncOutcome?>(null);
  final _conflicts = ValueNotifier<RecordConflicts>(const {});
  static const RecordSyncStatus _idle = (busy: false, message: null);

  /// The status of the action that the user started.
  ValueListenable<RecordSyncStatus> get statusNotifier => _status;

  /// How the latest sync ended, or null before the first one ends.
  ValueListenable<RecordSyncOutcome?> get lastSyncNotifier => _lastSync;

  /// The records with saved versions to choose between, by record address.
  ValueListenable<RecordConflicts> get conflictsNotifier => _conflicts;

  bool get busy => _status.value.busy;
  String? get message => _status.value.message;
  RecordConflicts get conflicts => _conflicts.value;

  void bind(JellyfinSession? session) {
    if (_session?.scope.key == session?.scope.key &&
        _session?.token == session?.token) {
      return;
    }
    ++_generation;
    _timer?.cancel();
    _client?.close();
    _session = session;
    // A sync of the earlier account stops at its next step, so the new
    // account does not wait for it.
    _running = null;
    _client = session == null
        ? null
        : JellyfinClient(session.scope.server, deviceId: 'bookfin-record-sync');
    _periodStart = null;
    _schedule();
    if (_disposed) return;
    _status.value = _idle;
    _lastSync.value = null;
    _conflicts.value = const {};
    if (!_suspended) unawaited(synchronize());
  }

  /// Tries again to read the kept copies of damaged records, as
  /// [LocalResumeStore.recoverKept] says, then refreshes Playback and the
  /// reader when records of their domain came back for the signed-in
  /// account. The app starts it after its first frame, in the background. A
  /// failure leaves the records and the kept copies as they were, and the
  /// next launch tries again, so it reports nothing. A refresh that fails
  /// also reports nothing: its domain stays stale, so the next sync
  /// refreshes it.
  Future<void> recoverKept() async {
    if (_disposed) return;
    try {
      await records.recoverKept();
      final session = _session;
      if (_disposed || session == null) return;
      final stale = records.staleDomains(session.scope.key);
      if (stale.listening) await playback?.refreshPersonalRecords();
      if (stale.reading) await reader?.refreshPersonalRecords();
    } on Exception {
      return;
    }
  }

  /// Stops the periodic sync while the app is in the background.
  void suspend() {
    _suspended = true;
    _timer?.cancel();
  }

  /// Restarts the periodic sync when the app returns to the front, and syncs
  /// at once if a sync came due in the background.
  void resume() {
    if (!_suspended) return;
    _suspended = false;
    final start = _periodStart;
    if (_session != null &&
        (start == null || now().difference(start) >= _period)) {
      unawaited(synchronize());
    }
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = _session == null || _suspended || _disposed
        ? null
        : Timer.periodic(_period, (_) => unawaited(synchronize()));
  }

  /// A background sync. It replaces the result of an earlier action of the
  /// user, because the outcome of this sync is newer. While another sync or
  /// choice runs, it starts nothing and completes when that one ends.
  Future<void> synchronize() async {
    if (_running case final running?) return running;
    if (_disposed || _session == null) return;
    final generation = _generation;
    final result = await _exclusive(_sync);
    if (result != null && _current(generation) && !busy) {
      _status.value = _idle;
    }
  }

  /// A sync that the user started. It shows busy, then its result.
  Future<void> syncNow() => _act(_sync);

  /// Keeps the saved version [identity] of [record], then syncs. It shows
  /// busy until the sync ends, then the result. The other saved places stay
  /// as bookmarks with the titles of [bookmarkTitles], as
  /// [LocalResumeStore.resolve] says.
  Future<void> resolve(
    String record,
    String identity, {
    Map<String, String> bookmarkTitles = const {},
  }) => _act(() async {
    final session = _session!;
    final generation = _generation;
    try {
      await playback?.flush();
      await reader?.flush();
      final accepted = await records.resolve(
        session.scope.key,
        record,
        identity,
        bookmarkTitles: bookmarkTitles,
      );
      if (!_current(generation)) return null;
      await playback?.refreshPersonalRecords();
      await reader?.refreshPersonalRecords();
      if (!_current(generation)) return null;
      if (accepted) return await _sync();
      final conflicts = await records.conflicts(session.scope.key);
      if (!_current(generation)) return null;
      _publish(conflicts);
      return (
        message: 'This saved choice changed before it was selected. Review the current saved versions and choose again.',
      );
    } on Exception {
      if (!_current(generation)) return null;
      return (
        message: 'The choice was not saved. Both versions were kept. Retry after checking device storage.',
      );
    }
  });

  /// Runs [work] for the user: busy while it waits and runs, then its
  /// result. [work] returns null when the account changed meanwhile.
  Future<void> _act(Future<_Result?> Function() work) async {
    if (_disposed || _session == null || busy) return;
    final generation = _generation;
    _status.value = (busy: true, message: null);
    String? message;
    try {
      message = (await _exclusive(work))?.message;
    } finally {
      if (_current(generation)) _status.value = (busy: false, message: message);
    }
  }

  /// Runs [work] after the sync or choice that runs now, so that one runs at
  /// a time for this account. Returns null without running [work] when the
  /// account changed meanwhile.
  Future<_Result?> _exclusive(Future<_Result?> Function() work) async {
    final generation = _generation;
    while (_running != null) {
      await _running;
    }
    if (!_current(generation)) return null;
    final run = work();
    final running = run.then<void>((_) {}, onError: (_) {});
    _running = running;
    try {
      return await run;
    } finally {
      if (identical(_running, running)) _running = null;
    }
  }

  /// Flushes local changes, syncs them, and reads the conflicts. Returns
  /// null when the account changed meanwhile.
  Future<_Result?> _sync() async {
    final session = _session;
    final client = _client;
    if (_disposed || session == null || client == null) return null;
    final generation = _generation;
    _periodStart = now();
    try {
      await playback?.flush();
      await reader?.flush();
      final (:stale, :replaced) = await records.synchronize(session, client);
      if (!_current(generation)) return null;
      if (stale.listening) await playback?.refreshPersonalRecords();
      if (stale.reading) await reader?.refreshPersonalRecords();
      if (!_current(generation)) return null;
      final conflicts = await records.conflicts(session.scope.key);
      if (!_current(generation)) return null;
      _publish(conflicts);
      return _ended(replaced: replaced);
    } on Exception catch (error) {
      if (!_current(generation)) return null;
      try {
        final conflicts = await records.conflicts(session.scope.key);
        if (!_current(generation)) return null;
        _publish(conflicts);
      } on Exception {
        if (!_current(generation)) return null;
        return _ended(failure: RecordSyncFailure.unreadable);
      }
      return _ended(failure: _cause(error));
    }
  }

  /// Why a sync that threw [error] failed, when the records on this phone
  /// could be read.
  static RecordSyncFailure _cause(Exception error) => switch (error) {
    CatalogFailure(kind: CatalogFailureKind.unavailable, status: 404) ||
    CatalogFailure(kind: CatalogFailureKind.invalidResponse) ||
    FormatException() => RecordSyncFailure.pluginMissing,
    CatalogFailure(kind: CatalogFailureKind.unavailable) =>
      RecordSyncFailure.unreachable,
    _ => RecordSyncFailure.other,
  };

  /// Shows [conflicts], unless they equal the ones shown.
  void _publish(RecordConflicts conflicts) {
    if (!const DeepCollectionEquality().equals(_conflicts.value, conflicts)) {
      _conflicts.value = Map.unmodifiable(conflicts);
    }
  }

  /// Records how this sync ended: its [failure], or else success and the
  /// number of damaged records that it [replaced].
  _Result _ended({RecordSyncFailure? failure, int replaced = 0}) {
    final at = now();
    _lastSync.value = (
      at: at,
      failure: failure,
      synced: failure == null ? at : _lastSync.value?.synced,
      replaced: replaced,
    );
    return (message: null);
  }

  bool _current(int generation) => !_disposed && generation == _generation;

  void checkInvariants() {
    if (_session == null &&
        (busy ||
            message != null ||
            _lastSync.value != null ||
            _conflicts.value.isNotEmpty)) {
      throw StateError('A signed-out record sync must hold no sync state.');
    }
  }

  void dispose() {
    _disposed = true;
    ++_generation;
    _timer?.cancel();
    _client?.close();
    _status.dispose();
    _lastSync.dispose();
    _conflicts.dispose();
  }
}
