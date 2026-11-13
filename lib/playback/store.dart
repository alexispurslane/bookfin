import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart'
    show ValueListenable, ValueNotifier, VoidCallback, compute;
import 'package:shared_preferences/shared_preferences.dart';

import '../catalog/model.dart' show Edition, EditionKind;
import '../foundation/hop.dart';
import '../reader/session.dart' show ReadingChanges, ReadingStore;
import '../sync/journal.dart';
import 'database.dart';
import 'playback.dart';
import 'record_codec.dart';
import 'record_writer.dart';

/// What the store knows of the kept copies of damaged records: how many
/// records the latest retry of them brought back, and whether kept copies
/// exist on this phone.
typedef KeptRecords = ({int recovered, bool kept});

/// One stored account: the settings of both domains and the record journal.
///
/// [metadata] holds the listening settings at the top and the reading
/// settings under `reading`, without records. The journal is the only owner
/// of records. Snapshots derive from it when a writer reads them.
typedef _StoredAccount = ({
  Map<String, dynamic> metadata,
  RecordJournal journal,
});

/// The snapshot of one domain that a read hands to its writer, and the
/// records that the snapshot shows, by address. The two share no objects.
typedef _View = ({
  Map<String, dynamic> snapshot,
  Map<String, Map<String, dynamic>> records,
});

/// The views of both domains of one account.
typedef _Views = ({_View listening, _View reading});

/// An account that a hop restored from storage, its views, and whether it
/// must be saved again before anything reads it. [commit] holds the rows of
/// that save when the store has a database. [damaged] says that the saved
/// data could not be read, so the account is a new one with the records
/// that the hop could still read, and the damaged data must move aside.
typedef _Restored = ({
  _StoredAccount stored,
  _Views views,
  bool persist,
  bool damaged,
  RecordCommit? commit,
});

/// The fewest journal actions, or the fewest records of a cached account,
/// that the store derives in another isolate. A smaller account derives on
/// the UI isolate.
///
/// Measured in AOT on an M-series Mac (tool/research/record_hop_bench), as
/// time on the calling isolate, medians of 201 runs: a hop costs 9 to 11 µs.
/// Restoring an account without actions costs 9 µs, and one with one action
/// 27 µs. Deriving the views of one record costs 12 µs, and of none 6 µs. So
/// a hop pays from the first action or record. Widget tests run the store's
/// hops in real time through test/real_time.dart.
const _hopItems = 1;

/// The shortest saved text of an account in the format before the journal
/// that the store decodes in another isolate. Measured as above: decoding
/// costs as much as a hop at about 32 characters, and a text that holds one
/// record has about 200.
const _hopText = 32;

/// The largest settings-only SQLite metadata text restored inline. This
/// bounds the existing fast path for scalar settings when no records exist;
/// growing metadata goes to a worker even when the journal is empty.
const _inlineMetadataText = 512;

/// The owner of each account's personal records on this phone.
///
/// Writers change records through [save], [write] or the `write` of
/// [reading]. A writer's change adds a sync action only for a record whose new value
/// differs from the value that this writer last saved or accepted, so a
/// writer never undoes a change that it did not see.
///
/// Durability: each write is one SQLite transaction, or one preference value
/// without a database, so a kill keeps all of a write or none of it. Sync
/// marks an upload done only after the server confirms it, and saves the
/// records that it receives with their discovery cursor in one write.
/// Versions from two devices that did not see each other stay side by side
/// until [resolve].
///
/// Damage: when the saved data of an account cannot be read, the read that
/// finds it keeps the damaged data aside, never deleted, and starts the
/// account again at once with a new installation identity and every record
/// that still decodes. Each such record keeps its sync action and its
/// upload state, so the next sync adds no copy of it and refills the rest.
/// An action that follows a lost action of its installation waits for that
/// sync. [setAside] reports the damage. If the damaged data cannot be moved
/// aside, the read fails and the data stays where it was.
///
/// Recovery: the kept copies of damaged data stay until the user discards
/// them ([discardKept]). After each launch, [recoverKept] reads them again
/// with the current code and merges every record that an account lacks
/// through the normal merge of the journal, so a later version of the app
/// can give back what an earlier one could not read.
///
/// When SQLite reports damaged pages in the record file during a read or a
/// write, the database keeps the whole file aside and continues on a new
/// file ([RecordFileSetAside]). The store then writes every account that it
/// holds in memory whole into the new file, with the write in progress, and
/// [setAside] reports the damage for every account. Until that rewrite
/// succeeds, memory holds the only copy of those accounts outside the kept
/// file, so the store keeps all of them, and each later operation first
/// tries the rewrite again.
///
/// Engine rule 1: the whole-account work of a read (the read of a large
/// account's rows, journal replay, the decoding of an older format, and
/// each domain's snapshot) runs in one hop to another isolate, and its
/// result comes back without a copy. A save does only the work of its own
/// change on the UI isolate.
///
/// Records of a newer build: a record can have an address or a kind that
/// this build does not know, because a newer build saved it on another
/// device. The journal keeps such a record, applies its action in causal
/// order, and syncs it on unchanged, so it never stops the discovery of the
/// records after it. No view shows it, no choice between saved versions
/// offers it, and no writer changes it. A later build that knows its kind
/// shows it at once, without a new sync. A value of a known kind that does
/// not decode is still damage. [readableRecord] decides which records this build
/// reads.
///
/// Invariants, checked on demand by [checkInvariants]:
/// - The journal of each cached account satisfies
///   [RecordJournal.checkInvariants].
/// - The durable rows of each cached account equal its journal and settings,
///   unless a rewrite into a new record file is due.
/// - Each kept view equals the view that its cached account derives.
class LocalResumeStore
    implements ResumeStore, ListeningStore, RecordWriterHost {
  LocalResumeStore({this.openDatabase, IsolateHop? hop, this.deviceName})
    : _hop = hop ?? compute;

  /// Looks up the name of this device, for example "Pixel 8", or gives null
  /// when the device has none. Each change that this store saves names the
  /// device, as [RecordJournal.change] says.
  final Future<String?> Function()? deviceName;
  Future<String?>? _deviceLookup;

  /// The name of this device, which the store looks up once. A failed
  /// lookup counts as a device without a name.
  Future<String?> _device() => _deviceLookup ??= () async {
    try {
      return await deviceName?.call();
    } on Exception {
      return null;
    }
  }();
  final Future<RecordDatabase> Function()? openDatabase;
  final IsolateHop _hop;
  Future<RecordDatabase>? _database;
  RecordDatabase? _opened;
  Future<RecordDatabase?> _storage() async {
    if (openDatabase == null) return null;
    if (_opened case final opened?) return opened;
    final opened = _opened = await (_database ??= openDatabase!());
    if (opened.keptFile != null) _keptCopy();
    return opened;
  }

  /// The writers whose domain holds records that changed outside them since
  /// the last snapshot that they took in. Each account/domain has one signal.
  final Map<String, ValueNotifier<bool>> _behind = {};
  final _writers = <_RegisteredWriter>{};

  ValueNotifier<bool> _stale(String account, {required bool reading}) =>
      _behind.putIfAbsent(
        _writer(account, reading: reading),
        () => ValueNotifier(false),
      );

  @override
  ValueListenable<bool> staleNotifier(String account) =>
      _stale(account, reading: false);

  @override
  VoidCallback registerWriter({
    required String? Function() account,
    required Future<void> Function() flush,
    required Future<void> Function() refresh,
  }) => _registerWriter(
    reading: false,
    account: account,
    flush: flush,
    refresh: refresh,
  );

  VoidCallback _registerWriter({
    required bool reading,
    required String? Function() account,
    required Future<void> Function() flush,
    required Future<void> Function() refresh,
  }) {
    final writer = _RegisteredWriter(reading, account, flush, refresh);
    _writers.add(writer);
    return () => _writers.remove(writer);
  }

  /// Flushes each live writer before sync or a choice. Writers retain their
  /// own retry and save-error policies. All flushes finish before a failure
  /// is handed to the caller; no storage operation holds the queue while
  /// awaiting a writer that can itself save.
  Future<void> flushWriters() async {
    await Future.wait([
      for (final writer in _writers.toList()) Future<void>.sync(writer.flush),
    ]);
  }

  /// Refreshes only stale writers currently bound to [account]. Independent
  /// refreshes all finish even when one fails with an Exception. A bug still
  /// reaches the caller. Snapshot acceptance alone clears a stale signal.
  Future<bool> refreshWriters(String account) async {
    Future<bool> refresh(_RegisteredWriter writer) async {
      try {
        await writer.refresh();
        return true;
      } on Exception {
        return false;
      }
    }

    final results = await Future.wait([
      for (final writer in _writers.toList())
        if (writer.account() == account &&
            _stale(account, reading: writer.reading).value)
          refresh(writer),
    ]);
    return !results.contains(false);
  }

  /// The accounts whose damaged data this store kept aside.
  final Set<String> _setAside = {};

  /// Whether the record file lacks accounts that the cache holds, because
  /// their rewrite into the new file that replaced a damaged one has not
  /// succeeded yet.
  bool _rewriteDue = false;

  late final ReadingRecords reading = ReadingRecords._(this);

  final _kept = ValueNotifier<KeptRecords>((recovered: 0, kept: false));

  /// What the store knows of the kept copies of damaged records. A damaged
  /// copy that this store keeps aside counts at once.
  ValueListenable<KeptRecords> get keptNotifier => _kept;

  /// The retry of the kept copies and their deletion, one at a time.
  Future<void> _keptWork = Future.value();

  /// Runs [work] after the retry or the deletion of kept copies that runs
  /// now.
  Future<void> _onKept(Future<void> Function() work) {
    final operation = _keptWork.then((_) => work());
    _keptWork = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }

  /// Counts a damaged copy that this store just kept aside.
  void _keptCopy() {
    if (!_kept.value.kept) {
      _kept.value = (recovered: _kept.value.recovered, kept: true);
    }
  }

  /// Reads every kept copy of damaged records again with the current code,
  /// in another isolate, and merges each record that an account lacks into
  /// it through the normal merge of the journal. That merge never lets
  /// older data replace newer data: an action that the account holds adds
  /// nothing, even when its kept copy differs, and a version that the
  /// account never saw stays beside its own. Each account's merge is one
  /// write. [keptNotifier] then says how many records came back.
  ///
  /// It deletes no kept copy, even one whose records all came back, because
  /// only the user's explicit [discardKept] deletes them. A copy that still
  /// cannot be read waits for a later version. A failure throws and leaves
  /// the records and the kept copies as they were.
  Future<void> recoverKept() => _onKept(() async {
    final database = await _storage();
    final preferences = await SharedPreferences.getInstance();
    const prefix = 'bookfin.damaged-records.v1.';
    final found = await _hop(_readKept, (
      reader: database?.reader,
      texts: [
        for (final key in preferences.getKeys())
          if (key.startsWith(prefix) &&
              key.lastIndexOf('.') > prefix.length &&
              preferences.get(key) is String)
            (
              account: key.substring(prefix.length, key.lastIndexOf('.')),
              text: preferences.getString(key)!,
            ),
      ],
    ));
    if (found.kept) _keptCopy();
    var recovered = 0;
    try {
      for (final MapEntry(key: account, value: kept)
          in found.accounts.entries) {
        recovered += await _recover(account, kept);
      }
    } finally {
      _kept.value = (recovered: recovered, kept: _kept.value.kept);
    }
  });

  /// Merges the records of [kept] that [account] lacks into it, as
  /// [recoverKept] says, saves them in one write, and returns how many
  /// records changed.
  Future<int> _recover(String account, _Kept kept) {
    final operation = _writes.then((_) async {
      var completed = false;
      try {
        final stored = await _readAccount(account);
        final journal = stored?.journal;
        // NOTE: Engine rule 1. With a database, the hop of [recoverKept]
        // dropped what the record file holds, so these loops see only the
        // few records that came back. Without one, only the web runs this,
        // and it has no isolates.
        final actions = [
          for (final MapEntry(key: identity, value: action)
              in kept.actions.entries)
            if (journal?.retained(identity) == null) action,
        ];
        final records = {
          for (final MapEntry(key: record, :value) in kept.records.entries)
            if (!(journal?.versionsByRecord.containsKey(record) ?? false))
              record: value,
        };
        if (actions.isEmpty && records.isEmpty) {
          completed = true;
          return 0;
        }
        final database = await _storage();
        final metadata = stored?.metadata ?? _metadata({});
        final sync = journal?.encode();
        final merged = await _derive(
          _withKept,
          (
            account: account,
            metadata: metadata,
            sync: sync,
            actions: actions,
            pending: kept.pending,
            records: records,
            database: database != null,
          ),
          small:
              (sync?['actions'] as List? ?? []).length + actions.length <
                  _hopItems &&
              _smallSettings(metadata, domains: true),
        );
        _changedOutsideWriters(account, merged.changed);
        await _persist(
          account,
          metadata,
          merged.journal,
          commit: merged.commit,
        );
        completed = true;
        return merged.changed.length;
      } finally {
        if (!completed) _forget(account);
      }
    });
    _writes = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }

  /// Deletes every kept copy of damaged records: the rows kept aside, the
  /// kept record files and the kept preference values. Only the user's
  /// confirmed Discard calls it. The records that came back stay. A failure
  /// throws, and the copies that remain still count as kept.
  Future<void> discardKept() => _onKept(() {
    final operation = _writes.then((_) async {
      final database = await _storage();
      try {
        await database?.discardKept();
      } on RecordFileSetAside {
        await _rewriteCached(database!);
        rethrow;
      }
      final preferences = await SharedPreferences.getInstance();
      for (final key in [
        for (final key in preferences.getKeys())
          if (key.startsWith('bookfin.damaged-records.')) key,
      ]) {
        if (!await preferences.remove(key)) {
          throw Exception('A kept copy of damaged records was not deleted.');
        }
      }
      _kept.value = (recovered: _kept.value.recovered, kept: false);
    });
    _writes = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  });

  Future<void> _writes = Future.value();
  final Map<String, Map<String, Map<String, dynamic>>> _observed = {};
  final Map<String, _StoredAccount> _accounts = {};

  /// The views of each cached account that a hop derived and no read has
  /// handed out yet, by writer. A change of the account removes them.
  final Map<String, _View> _views = {};

  /// The view that each writer's last read handed out, by writer, so that
  /// accepting that snapshot needs no work on the UI isolate.
  final Map<String, _View> _handed = {};
  String _key(String accountKey) => 'bookfin.playback.v1.$accountKey';
  String _writer(String account, {required bool reading}) =>
      '$account/${reading ? 'reading' : 'audio'}';

  /// Runs [work] on [input] on this isolate when [small], and in a hop
  /// otherwise.
  Future<R> _derive<M, R>(
    FutureOr<R> Function(M) work,
    M input, {
    required bool small,
  }) async => small ? work(input) : _hop(work, input);

  /// Keeps [views] of [account] for the next read of each domain.
  void _keep(String account, _Views views) {
    _views[_writer(account, reading: false)] = views.listening;
    _views[_writer(account, reading: true)] = views.reading;
  }

  /// Marks the writer of the domain of each of [records] of [account] as
  /// behind, because the records changed outside it. A snapshot that it was
  /// handed earlier no longer counts as taking the change in.
  void _changedOutsideWriters(String account, Iterable<String> records) {
    for (final record in records) {
      final address = jsonDecode(record) as List;
      if (!knownRecordAddress(address)) continue;
      final writer = _writer(account, reading: address[0] == 'reading');
      _handed.remove(writer);
      _stale(account, reading: address[0] == 'reading').value = true;
    }
  }

  /// Drops the cached state of [account], so that the next operation reads
  /// it from storage. While a rewrite is due, storage lacks the account, so
  /// the cache keeps it with the change that failed, for the rewrite.
  void _forget(String account) {
    if (!_rewriteDue) _accounts.remove(account);
    _forgetViews(account);
  }

  void _forgetViews(String account) {
    _views.remove(_writer(account, reading: false));
    _views.remove(_writer(account, reading: true));
  }

  Future<T> _update<T>(String account, T Function(RecordJournal) change) {
    final operation = _writes.then((_) async {
      var completed = false;
      try {
        final stored = await _readAccount(account);
        final journal = stored?.journal ?? _journal(account, {});
        final result = change(journal);
        await _persist(account, stored?.metadata ?? _metadata({}), journal);
        completed = true;
        return result;
      } finally {
        if (!completed) _forget(account);
      }
    });
    _writes = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }

  Future<T> _access<T>(
    String account,
    FutureOr<T> Function(_StoredAccount?) query,
  ) {
    final operation = _writes.then(
      (_) async => query(await _readAccount(account)),
    );
    _writes = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }

  Future<T> _query<T>(
    String account,
    FutureOr<T> Function(RecordJournal) query,
  ) => _access(
    account,
    (stored) => query(stored?.journal ?? _journal(account, {})),
  );

  /// A detached snapshot of actions still awaiting server acknowledgment.
  /// Editing the result cannot change retained or pending actions.
  Future<List<Map<String, dynamic>>> pendingUploads(String account) => _query(
    account,
    (journal) =>
        _derive(_copyActions, journal.uploads, small: journal.pending.isEmpty),
  );

  /// The last discovery sequence durably saved with its received page.
  Future<int> discoveryCursor(String account) =>
      _query(account, (journal) => journal.cursor);

  /// Marks an action uploaded only after transport verified its server copy.
  /// The action itself stays retained. A failed write keeps it pending.
  Future<void> acknowledge(String account, String identity) =>
      _update(account, (journal) => journal.acknowledge(identity));

  /// Receives a decoded discovery page and its cursor in one durable write.
  /// The protocol validates page ordering before calling this method. A
  /// cursor behind the saved cursor is rejected without changing records.
  /// Marks changed domains stale before saving, so no read can accept an old
  /// snapshot between the save and invalidation. A failed save can cause an
  /// extra refresh but never loses the discovery cursor's pending records.
  Future<void> receivePage(
    String account,
    List<Map<String, dynamic>> actions,
    int cursor,
  ) => _update(account, (journal) {
    if (cursor < journal.cursor) {
      throw RangeError.range(cursor, journal.cursor, null, 'cursor');
    }
    _changedOutsideWriters(account, journal.receive(actions));
    journal.cursor = cursor;
  });

  /// Replaces each saved action of [account] that has the identity of one
  /// of [copies], the server's copies, by that copy. The server's copy wins,
  /// because an action never changes and the server holds the copy that was
  /// uploaded before any damage here. The saved data moves aside first, as
  /// damaged data does, and is never deleted. The copies count as uploaded.
  ///
  /// The journal is replayed with the copies in a hop. Throws a
  /// [FormatException] when the copies do not fit the journal, and changes
  /// nothing then. Returns the number of differing retained actions replaced;
  /// new actions and copies equal to retained actions make no change.
  Future<int> takeServerCopies(
    String account,
    List<Map<String, dynamic>> copies,
  ) {
    final operation = _writes.then((_) async {
      var completed = false;
      try {
        final stored = await _readAccount(account);
        copies = [
          for (final action in copies)
            if (stored?.journal.retained(RecordJournal.identity(action))
                case final local?
                when !const DeepCollectionEquality().equals(local, action))
              action,
        ];
        if (copies.isEmpty) {
          completed = true;
          return 0;
        }
        final database = await _storage();
        final sync = stored!.journal.encode();
        final restored = await _derive(
          _withServerCopies,
          (
            account: account,
            metadata: stored.metadata,
            sync: sync,
            copies: copies,
            database: database != null,
          ),
          small:
              (sync['actions'] as List).length < _hopItems &&
              _smallSettings(stored.metadata, domains: true),
        );
        _changedOutsideWriters(account, [
          for (final copy in copies) ...[
            copy['record'] as String,
            stored.journal.retained(RecordJournal.identity(copy))!['record']
                as String,
          ],
        ]);
        await _adopt(
          account,
          restored,
          text: database == null
              ? (await SharedPreferences.getInstance()).getString(_key(account))
              : null,
          reported: false,
        );
        completed = true;
        return copies.length;
      } finally {
        if (!completed) _forget(account);
      }
    });
    _writes = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }

  Future<Map<String, List<Map<String, dynamic>>>> conflicts(String account) =>
      _access(account, (stored) {
        // NOTE: Engine rule 1. Only records with competing versions are
        // copied, which are few, so the copy costs less than a hop.
        final conflicts = jsonDecode(
          jsonEncode({
            for (final MapEntry(key: record, value: versions)
                in (stored?.journal.conflicts ?? const {}).entries)
              if (versions.every(
                (version) => readableRecord(
                  record,
                  version['value'] as Map<String, dynamic>?,
                ),
              ))
                record: versions,
          }),
        ) as Map<String, dynamic>;
        return {
          for (final entry in conflicts.entries)
            entry.key: (entry.value as List).cast<Map<String, dynamic>>(),
        };
      });

  /// Keeps the saved version [identity] of [record] and replaces the
  /// others, which a listening place keeps as bookmarks. Returns false and
  /// changes nothing when [record] has no such competing version.
  ///
  /// [bookmarkTitles] holds the title of the bookmark of each version, by
  /// the identity of its action, as the choice named it. A version without
  /// one gets a general title.
  Future<bool> resolve(
    String account,
    String record,
    String identity, {
    Map<String, String> bookmarkTitles = const {},
  }) async {
    final device = await _device();
    return _update(account, (journal) {
      final versions = journal.conflicts[record];
      final selected = versions
          ?.where((action) => RecordJournal.identity(action) == identity)
          .firstOrNull;
      if (selected == null) {
        return false;
      }
      final address = jsonDecode(record) as List;
      if (address[1] == 'resumes') {
        for (final action in versions!) {
          if (action['value'] == null) continue;
          final value = Map<String, dynamic>.from(action['value'] as Map);
          final mark = 'conflict.${RecordJournal.identity(action)}';
          final audio = address[0] == 'audio';
          final now = DateTime.now();
          journal.change(
            jsonEncode([address[0], 'bookmarks', mark]),
            {
              'id': mark,
              'position': audio
                  ? {
                      'edition': value['edition'],
                      'source': value['source'],
                      'revision': value['revision'],
                      'milliseconds': value['milliseconds'],
                    }
                  : value,
              'createdAt': now.toUtc().toIso8601String(),
              'title':
                  bookmarkTitles[RecordJournal.identity(action)] ??
                  'Saved before sync choice',
              if (audio) 'bookTitle': 'Saved listening place',
              if (audio) 'editionLabel': 'Saved recording',
            },
            device: device,
            savedAt: now,
          );
        }
      }
      journal.change(
        record,
        selected['value'] as Map<String, dynamic>?,
        resolve: true,
        device: device,
        savedAt: DateTime.now(),
      );
      _changedOutsideWriters(account, [record]);
      return true;
    });
  }

  @override
  Future<Map<String, dynamic>?> read(String accountKey) =>
      _read(accountKey, reading: false);

  /// The snapshot of one domain of [account], or null when it has none.
  ///
  /// The snapshot comes from a view that a hop derived: the one that the
  /// account's restore kept, or a new one from its cached journal, which
  /// also keeps the other domain's view.
  Future<Map<String, dynamic>?> _read(String account, {required bool reading}) {
    final writer = _writer(account, reading: reading);
    final operation = _writes.then((_) async {
      final stored = await _readAccount(account);
      if (stored == null) return null;
      var view = _views.remove(writer);
      if (view == null) {
        final versions = stored.journal.versionsByRecord;
        final views = await _derive(
          _viewsOfVersions,
          (metadata: stored.metadata, versions: versions),
          small:
              versions.length < _hopItems &&
              _smallSettings(stored.metadata, domains: true),
        );
        view = reading ? views.reading : views.listening;
        _views[_writer(account, reading: !reading)] = reading
            ? views.listening
            : views.reading;
      }
      _handed[writer] = view;
      return view.snapshot;
    });
    _writes = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }

  /// The stored account, from the cache or restored from storage. A
  /// restore runs in one hop and also derives both views, which the next
  /// read of each domain hands out.
  Future<_StoredAccount?> _readAccount(String accountKey) async {
    final database = await _storage();
    if (database != null) {
      if (_rewriteDue) await _rewriteCached(database);
      final cached = _accounts[accountKey];
      if (cached != null) return cached;
      _Restored? restored;
      try {
        restored = await _restoreFile(database, accountKey);
      } on RecordFileSetAside {
        await _rewriteCached(database);
      }
      if (restored != null) return _adopt(accountKey, restored);
    }
    final preferences = await SharedPreferences.getInstance();
    final legacy = await database?.read(accountKey);
    final raw = legacy ?? preferences.getString(_key(accountKey));
    if (raw == null) return null;
    return _adopt(
      accountKey,
      await _derive(_restoreText, (
        account: accountKey,
        text: raw,
        database: database != null,
      ), small: raw.length < _hopText),
      text: raw,
    );
  }

  /// The account that the record file holds for [account], restored, or
  /// null when it has none. A large account is read, decoded and replayed
  /// in one hop that reads the file on a connection of its own, so its rows
  /// never cross the UI isolate. Throws [RecordFileSetAside] when the file
  /// has damaged pages.
  ///
  /// When that hop fails for another reason, for example because its
  /// connection cannot open, the UI isolate's connection reads the rows, as
  /// for a small account, and another hop restores them. The user sees the
  /// account as usual, so nothing is reported.
  Future<_Restored?> _restoreFile(
    RecordDatabase database,
    String account,
  ) async {
    final small = await database.actionCount(account) < _hopItems;
    if (!small) {
      ({_Restored? restored, bool damaged})? read;
      try {
        read = await _hop(_readAndRestore, (
          account: account,
          reader: database.reader,
        ));
      } catch (_) {
        // The hop reports damage in [read] and throws only for other
        // failures, which the read below does not share.
      }
      if (read != null) {
        if (read.damaged) await database.setAsideDamaged();
        return read.restored;
      }
    }
    final rows = await database.rows(account);
    return rows == null
        ? null
        : _derive(_restoreRows, (
            account: account,
            rows: rows,
          ), small: small && rows.metadata.length < _inlineMetadataText);
  }

  /// Saves [restored] as the durable state of [account] when it must be
  /// saved, keeps its views, and returns it. [text] is the saved text that
  /// the hop restored, if any. [reported] says that [setAside] reports the
  /// damaged data that moved aside.
  ///
  /// A damaged account's data moves aside before the new account replaces
  /// it. With a database, both happen in one transaction, and preference
  /// text, which the store no longer reads once the account has rows, stays
  /// where it is. Without one, the text is copied to its own key first.
  Future<_StoredAccount> _adopt(
    String account,
    _Restored restored, {
    String? text,
    bool reported = true,
  }) async {
    final stored = restored.stored;
    final database = await _storage();
    if (restored.damaged && database != null) {
      _forgetViews(account);
      try {
        await database.replaceDamaged(
          restored.commit!,
          keptAt: DateTime.now().millisecondsSinceEpoch,
        );
        stored.journal.persisted();
        _accounts[account] = stored;
      } on RecordFileSetAside {
        _accounts[account] = stored;
        await _rewriteCached(database);
      }
    } else if (restored.damaged) {
      final preferences = await SharedPreferences.getInstance();
      final kept =
          'bookfin.damaged-records.v1.$account.${DateTime.now().millisecondsSinceEpoch}';
      if (!await preferences.setString(kept, text!)) {
        throw Exception('Damaged personal records could not be kept aside.');
      }
      await _persist(account, stored.metadata, stored.journal);
    } else if (restored.persist) {
      await _persist(
        account,
        stored.metadata,
        stored.journal,
        commit: restored.commit,
      );
    } else if (database != null) {
      _accounts[account] = stored;
    }
    if (restored.damaged) _keptCopy();
    if (restored.damaged && reported) _setAside.add(account);
    _keep(account, restored.views);
    return stored;
  }

  /// Saves [metadata] and [journal] as the durable state of [account].
  /// [commit] holds the rows of this save when a hop encoded them.
  Future<void> _persist(
    String account,
    Map<String, dynamic> metadata,
    RecordJournal journal, {
    RecordCommit? commit,
  }) async {
    final database = await _storage();
    _forgetViews(account);
    if (database != null) {
      try {
        await database.writeCommit(
          commit ??
              RecordDatabase.encodeCommitWithMetadataText(
                account,
                await _derive(
                  _encodeMetadata,
                  metadata,
                  small: _smallSettings(metadata, domains: true),
                ),
                journal,
                initialize: !_accounts.containsKey(account),
              ),
        );
        journal.persisted();
        _accounts[account] = (metadata: metadata, journal: journal);
      } on RecordFileSetAside {
        _accounts[account] = (metadata: metadata, journal: journal);
        await _rewriteCached(database);
      }
    } else {
      // Without a database the whole account is one preference value, so a
      // kill leaves the old value or the new one if the platform writes one
      // value atomically. Only the web runs this branch outside tests, and
      // its plugin writes with one localStorage.setItem call. The Linux and
      // Windows plugins rewrite one JSON file in place, so give a build for
      // those platforms the database.
      final text = await _derive(
        _preferenceText,
        (metadata: metadata, journal: journal),
        small:
            journal.versionsByRecord.isEmpty &&
            _smallSettings(metadata, domains: true),
      );
      final preferences = await SharedPreferences.getInstance();
      if (!await preferences.setString(_key(account), text)) {
        throw Exception(
          'Personal records were not saved. Free storage, then retry.',
        );
      }
    }
  }

  /// Writes every cached account whole into the new file that replaced a
  /// damaged record file, in one transaction, so that the records that the
  /// store holds in memory stay on the phone. A hop encodes them. The
  /// rewrite stays due until it succeeds.
  Future<void> _rewriteCached(RecordDatabase database) async {
    _rewriteDue = true;
    _keptCopy();
    final accounts = Map.of(_accounts);
    final input = [
      for (final MapEntry(key: account, value: stored) in accounts.entries)
        (
          account: account,
          metadata: stored.metadata,
          sync: stored.journal.encode(),
        ),
    ];
    final actions = input.fold(
      0,
      (count, account) => count + (account.sync['actions'] as List).length,
    );
    await database.writeCommits(
      await _derive(
        _wholeCommits,
        input,
        small:
            actions < _hopItems &&
            input.every(
              (account) => _smallSettings(account.metadata, domains: true),
            ),
      ),
    );
    _rewriteDue = false;
    for (final stored in accounts.values) {
      stored.journal.persisted();
    }
  }

  Future<void> checkInvariants() {
    final operation = _writes.then((_) async {
      final database = await _storage();
      for (final entry in _accounts.entries) {
        final journal = entry.value.journal;
        journal.checkInvariants();
        if (_rewriteDue) continue;
        final rows = await database!.load(entry.key);
        final savedSync = rows?['sync'] as Map<String, dynamic>?;
        final encoded = journal.encode();
        if (savedSync != null) {
          savedSync['pending'] = (savedSync['pending'] as List).cast<String>()
            ..sort();
          encoded['pending'] = (encoded['pending'] as List).cast<String>()
            ..sort();
        }
        if (rows == null ||
            !const DeepCollectionEquality().equals(savedSync, encoded) ||
            !const DeepCollectionEquality().equals(
              rows['current'],
              journal.current,
            ) ||
            !const DeepCollectionEquality().equals(
              rows['coverage'],
              journal.coverage,
            ) ||
            !const DeepCollectionEquality().equals(
              rows['snapshot'],
              entry.value.metadata,
            )) {
          throw StateError(
            'The personal-record owner and durable state must agree.',
          );
        }
      }
      for (final MapEntry(key: writer, value: view) in _views.entries) {
        final account = writer.substring(0, writer.lastIndexOf('/'));
        final stored = _accounts[account];
        final derived = stored == null
            ? null
            : _viewsOfVersions((
                metadata: stored.metadata,
                versions: stored.journal.versionsByRecord,
              ));
        final expected = writer.endsWith('/reading')
            ? derived?.reading
            : derived?.listening;
        if (expected == null ||
            !const DeepCollectionEquality().equals(
              view.snapshot,
              expected.snapshot,
            ) ||
            !const DeepCollectionEquality().equals(
              view.records,
              expected.records,
            )) {
          throw StateError('A kept view must match its cached account.');
        }
      }
      await database?.checkInvariants();
    });
    _writes = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }

  @override
  Future<void> write(String accountKey, Map<String, dynamic> value) =>
      _write(accountKey, value, reading: false);

  @override
  Future<void> save(String accountKey, ListeningChanges changes) {
    // NOTE: Engine rule 1. A change set holds one resume list and the few
    // records that changed, a few hundred bytes that copy in a few
    // microseconds, which is less than a hop.
    final copied = jsonDecode(
      jsonEncode({
        'settings': changes.settings,
        'history': changes.history,
        'bookmarks': changes.bookmarks,
        'resumes': changes.resumes,
      }),
    ) as Map<String, dynamic>;
    return _change(
      accountKey,
      copied['settings'] as Map<String, dynamic>,
      reading: false,
      records: (_) => {
        for (final collection in ['history', 'bookmarks'])
          for (final entry in (copied[collection] as Map).entries)
            jsonEncode(['audio', collection, entry.key]):
                entry.value as Map<String, dynamic>?,
        ...flattenRecords({'resumes': copied['resumes']}, reading: false),
      },
    );
  }

  @override
  void acceptSnapshot(String accountKey, Map<String, dynamic>? value) =>
      _accept(accountKey, value, reading: false);

  /// Reads the journal: the value of this installation's last action on
  /// the saved place of [edition], and the action of the current version.
  /// While two versions compete, no device saved the current place. The
  /// saved place of a reading edition is its resume, and of a listening
  /// edition the resume of its current files.
  @override
  Future<PlaceOrigin> origin(String accountKey, Edition edition) {
    final reading = edition.kind == EditionKind.text;
    final record = resumeRecordAddress(edition);
    return _query(accountKey, (journal) {
      final own = journal.lastOwn(record)?['value'];
      final versions = journal.versionsByRecord[record] ?? const [];
      final current = versions.length == 1 ? versions.single : null;
      final elsewhere =
          current != null && current['replica'] != journal.replica;
      return (
        own: switch (own) {
          Map<String, dynamic>() when reading => decodeTextPosition(own),
          Map<String, dynamic>() => decodePosition(own),
          _ => null,
        },
        elsewhere: elsewhere,
        device: elsewhere ? current['device'] as String? : null,
      );
    });
  }

  /// The whole record file counts for every account when it could not be
  /// opened, because the store cannot tell which accounts it held.
  @override
  bool setAside(String accountKey) =>
      _setAside.contains(accountKey) || _opened?.keptFile != null;

  /// Records [value] as the snapshot that the writer of one domain of
  /// [account] now shows.
  void _accept(
    String account,
    Map<String, dynamic>? value, {
    required bool reading,
  }) {
    final writer = _writer(account, reading: reading);
    final handed = _handed.remove(writer);
    if (handed != null && identical(handed.snapshot, value)) {
      _observed[writer] = handed.records;
      _stale(account, reading: reading).value = false;
      return;
    }
    // NOTE: Engine rule 1. Production writers accept the snapshot that their
    // read returned, which the branch above takes. This branch serves other
    // callers, such as tests, and a writer that has no saved records.
    final snapshot = _copy(value ?? const {});
    _observed[writer] = flattenRecords(
      reading ? {'reading': snapshot} : snapshot,
      reading: reading,
    );
  }

  /// Saves a whole listening or reading [value] by the changes of its records
  /// from what its writer last saved or accepted. A record that the writer
  /// knew and that [value] lacks is deleted.
  ///
  /// NOTE: Engine rule 1. This copies and flattens the whole snapshot on the
  /// calling isolate. Playback and the reader save change sets instead, so
  /// only tests and the [ResumeStore] interface still write whole snapshots.
  Future<void> _write(
    String accountKey,
    Map<String, dynamic> value, {
    required bool reading,
  }) {
    final snapshot = jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
    return _change(
      accountKey,
      snapshot,
      reading: reading,
      records: (observed) {
        final next = flattenRecords(
          reading ? {'reading': snapshot} : snapshot,
          reading: reading,
        );
        return {
          for (final record in {...observed.keys, ...next.keys})
            record: next[record],
        };
      },
    );
  }

  /// Replaces the settings of one domain of [account] and saves its changed
  /// records.
  ///
  /// [records] receives the record values that the domain's writer last saved
  /// or accepted, by address. It returns the records that the writer changed,
  /// with null for a deletion. A returned record adds a sync action only when
  /// it differs from the writer's last value, or from the retained value when
  /// the writer knew none.
  Future<void> _change(
    String account,
    FutureOr<Map<String, dynamic>> settings, {
    required bool reading,
    required Map<String, Map<String, dynamic>?> Function(
      Map<String, Map<String, dynamic>> observed,
    )
    records,
  }) {
    if (settings is Future<Map<String, dynamic>>) settings.ignore();
    final writer = '$account/${reading ? 'reading' : 'audio'}';
    final operation = _writes.then((_) async {
      var completed = false;
      try {
        final prepared = await settings;
        final device = await _device();
        final savedAt = DateTime.now();
        final stored = await _readAccount(account);
        final journal = stored?.journal ?? _journal(account, {});
        final observed = _observed[writer] ?? {};
        final changed = records(observed);
        for (final MapEntry(key: record, :value) in changed.entries) {
          if (!const DeepCollectionEquality().equals(
            observed[record] ?? journal.value(record),
            value,
          )) {
            journal.change(record, value, device: device, savedAt: savedAt);
          }
        }
        final previous = stored?.metadata ?? _metadata({});
        await _persist(
          account,
          _metadata(
            reading
                ? {...previous, 'reading': prepared}
                : {...prepared, 'reading': previous['reading']},
          ),
          journal,
        );
        for (final MapEntry(key: record, :value) in changed.entries) {
          if (value == null) {
            observed.remove(record);
          } else {
            observed[record] = value;
          }
        }
        _observed[writer] = observed;
        completed = true;
      } finally {
        if (!completed) _forget(account);
      }
    });
    _writes = operation.catchError((Object _) {});
    return operation;
  }
}

/// A live writer and the domain whose stale signal controls its refresh.
class _RegisteredWriter {
  _RegisteredWriter(this.reading, this.account, this.flush, this.refresh);
  final bool reading;
  final String? Function() account;
  final Future<void> Function() flush;
  final Future<void> Function() refresh;
}

/// The reading domain shares its owner's writer coordination and durable
/// journal, while exposing only reading snapshots and invalidation.
class ReadingRecords implements ResumeStore, ReadingStore, RecordWriterHost {
  ReadingRecords._(this.owner);
  final LocalResumeStore owner;

  @override
  ValueListenable<bool> staleNotifier(String account) =>
      owner._stale(account, reading: true);

  @override
  VoidCallback registerWriter({
    required String? Function() account,
    required Future<void> Function() flush,
    required Future<void> Function() refresh,
  }) => owner._registerWriter(
    reading: true,
    account: account,
    flush: flush,
    refresh: refresh,
  );

  @override
  Future<Map<String, dynamic>?> read(String accountKey) =>
      owner._read(accountKey, reading: true);

  @override
  Future<void> write(String accountKey, Map<String, dynamic> value) =>
      owner._write(accountKey, value, reading: true);

  @override
  Future<void> saveReading(String accountKey, ReadingChanges changes) {
    // NOTE: Engine rule 1. A change set holds the few records that one
    // action changed, which copy faster than a hop.
    final copied = _copy({
      'resumes': changes.resumes,
      'bookmarks': changes.bookmarks,
      'history': changes.history,
    });
    return owner._change(
      accountKey,
      owner._derive(
        _copy,
        changes.settings,
        small: _smallSettings(changes.settings),
      ),
      reading: true,
      records: (_) => {
        for (final collection in ['bookmarks', 'history'])
          for (final entry in (copied[collection] as Map).entries)
            jsonEncode(['reading', collection, entry.key]):
                entry.value as Map<String, dynamic>?,
        ...flattenRecords({
          'reading': {'resumes': copied['resumes']},
        }, reading: true),
      },
    );
  }

  @override
  void acceptSnapshot(String accountKey, Map<String, dynamic>? value) =>
      owner._accept(accountKey, value, reading: true);

  @override
  bool setAside(String accountKey) => owner.setAside(accountKey);

  @override
  Future<PlaceOrigin> origin(String accountKey, Edition edition) =>
      owner.origin(accountKey, edition);
}

/// The settings of a listening [snapshot] and of its `reading` snapshot,
/// without records, in the current format.
Map<String, dynamic> _metadata(Map<String, dynamic> snapshot) {
  Map<String, dynamic> withoutRecords(Map<String, dynamic>? value) =>
      Map<String, dynamic>.from(value ?? const {})
        ..remove('sync')
        ..remove('bookmarks')
        ..remove('history')
        ..remove('resumes')
        ..remove('reading');
  return {
    ...withoutRecords(snapshot),
    'version': 3,
    'reading': {
      ...withoutRecords(snapshot['reading'] as Map<String, dynamic>?),
      'version': 1,
    },
  };
}

Map<String, dynamic> _copy(Map<String, dynamic> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

/// Bounds inline work to eight short scalar fields per domain. Nested
/// collections and unrecognized values go to a worker without traversing them.
bool _smallSettings(Map<String, dynamic> settings, {bool domains = false}) {
  if (settings.length > 8) return false;
  for (final entry in settings.entries) {
    if (entry.key.length >= _hopText) return false;
    final value = entry.value;
    if (domains && entry.key == 'reading' && value is Map<String, dynamic>) {
      if (!_smallSettings(value)) return false;
    } else if (value is String) {
      if (value.length >= _hopText) return false;
    } else if (value != null && value is! num && value is! bool) {
      return false;
    }
  }
  return true;
}

String _encodeMetadata(Map<String, dynamic> metadata) => jsonEncode(metadata);

String _preferenceText(
  ({Map<String, dynamic> metadata, RecordJournal journal}) input,
) {
  final values = input.journal.values;
  return jsonEncode({
    ...recordSnapshot(input.metadata, values, reading: false),
    'reading': recordSnapshot(input.metadata, values, reading: true),
    'sync': input.journal.encode(),
  });
}

/// Both views of an account with [metadata] and the record [values] of
/// [RecordJournal.values]. It changes [values].
_Views _views(
  Map<String, dynamic> metadata,
  Map<String, Map<String, dynamic>> values,
) {
  _View view({required bool reading}) {
    final snapshot = recordSnapshot(metadata, values, reading: reading);
    final copy = _copy(snapshot);
    return (
      snapshot: snapshot,
      records: flattenRecords(
        reading ? {'reading': copy} : copy,
        reading: reading,
      ),
    );
  }

  return (listening: view(reading: false), reading: view(reading: true));
}

/// Both views of a cached account, from its settings and the current
/// versions of its records.
_Views _viewsOfVersions(
  ({
    Map<String, dynamic> metadata,
    Map<String, List<Map<String, dynamic>>> versions,
  })
  account,
) => _views(account.metadata, {
  for (final MapEntry(key: record, value: versions) in account.versions.entries)
    record: ?RecordJournal.currentValue(record, versions),
});

/// The account that `input.reader` reads for `input.account`, restored as
/// [_restoreRows] does, or null when it has none. [damaged] says that SQLite
/// reported damaged pages in the record file.
Future<({_Restored? restored, bool damaged})> _readAndRestore(
  ({String account, RecordReader reader}) input,
) async {
  final read = await input.reader.rows(input.account);
  final rows = read.rows;
  return (
    restored: rows == null
        ? null
        : _restoreRows((account: input.account, rows: rows)),
    damaged: read.damaged,
  );
}

/// The account that its durable [AccountRows] hold, with its views, or a
/// new account from what [_salvageRows] can read of them when they are
/// damaged.
_Restored _restoreRows(({String account, AccountRows rows}) input) {
  try {
    return _readRows(input);
  } on FormatException {
    return _salvageRows(input);
  }
}

/// The account that its durable [AccountRows] hold, with its views.
///
/// Throws a [FormatException] when the rows cannot be decoded or their
/// current versions do not match the actions that they retain.
_Restored _readRows(({String account, AccountRows rows}) input) {
  final rows = RecordDatabase.decode(input.rows);
  final journal = _journal(input.account, {'sync': rows['sync']});
  if (!const DeepCollectionEquality().equals(
        journal.current,
        rows['current'],
      ) ||
      !const DeepCollectionEquality().equals(
        journal.coverage,
        rows['coverage'],
      )) {
    throw const FormatException(
      'Stored personal-record state does not match retained actions.',
    );
  }
  journal.persisted();
  final metadata = rows['snapshot'] as Map<String, dynamic>;
  return (
    stored: (metadata: metadata, journal: journal),
    views: _views(metadata, journal.values),
    persist: false,
    damaged: false,
    commit: null,
  );
}

/// The account that one saved [text] holds in a format before the record
/// tables, with its views, or a new account from what [_salvageText] can
/// read of it when it is damaged. [database] says that the account moves
/// into the database, so the result carries the rows of that first commit.
_Restored _restoreText(({String account, String text, bool database}) input) {
  try {
    return _readText(input);
  } on FormatException {
    return _salvageText(input);
  }
}

/// The account that one saved [text] holds, as [_restoreText] says.
///
/// Throws a [FormatException] when the text cannot be decoded.
_Restored _readText(({String account, String text, bool database}) input) {
  final decoded = jsonDecode(input.text);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Personal records must be an object.');
  }
  final reading = decoded['reading'];
  if (reading != null && reading is! Map<String, dynamic>) {
    throw const FormatException('Reading records must be an object.');
  }
  final metadata = _metadata(decoded);
  final journal = _journal(input.account, decoded);
  // Records move from preferences into the database, or from a format
  // without a journal into one, before anything reads them. A journal
  // made here has a new installation identity, and a sync that read an
  // unsaved one would upload each record under an identity that the
  // next read replaces.
  final persist = input.database || decoded['sync'] == null;
  return (
    stored: (metadata: metadata, journal: journal),
    views: _views(metadata, journal.values),
    persist: persist,
    damaged: false,
    commit: input.database
        ? RecordDatabase.encodeCommit(
            input.account,
            metadata,
            journal,
            initialize: true,
          )
        : null,
  );
}

/// A new account from the damaged [AccountRows] of `input.account`, from
/// what [_readableRows] reads of them.
_Restored _salvageRows(({String account, AccountRows rows}) input) =>
    _salvaged(input.account, _readableRows(input.rows), database: true);

/// What a damaged copy of one account holds that the current code reads:
/// the settings of [snapshot], the [actions] that decode as objects, the
/// identities of those that wait for upload, or null when that is not
/// known, and the [records] of a snapshot in the format before the journal.
typedef _Readable = ({
  Map<String, dynamic> snapshot,
  List<Map<String, dynamic>> actions,
  List<String>? pending,
  Map<String, dynamic> records,
});

/// What [rows] hold: the settings when they decode, and each action that
/// decodes. Malformed rows may have lost the upload state, so it is not
/// known.
_Readable _readableRows(AccountRows rows) => (
  snapshot: _decodedObject(rows.metadata) ?? {},
  actions: [for (final payload in rows.payloads) ?_decodedObject(payload)],
  pending: rows.malformed ? null : rows.pending,
  records: const {},
);

/// What a saved [text] holds: the settings, and each action of its journal
/// or, in the format before the journal, each of its records.
_Readable _readableText(String text) {
  final decoded = _decodedObject(text) ?? {};
  final sync = decoded['sync'];
  if (sync is! Map<String, dynamic>) {
    return (
      snapshot: decoded,
      actions: const [],
      pending: const [],
      records: decoded,
    );
  }
  final actions = sync['actions'];
  final pending = sync['pending'];
  return (
    snapshot: decoded,
    actions: [
      if (actions is List)
        for (final action in actions)
          if (action is Map<String, dynamic>) action,
    ],
    pending: pending is List && pending.every((identity) => identity is String)
        ? pending.cast<String>()
        : null,
    records: const {},
  );
}

/// Each of [actions] that a journal of [account] accepts alone, by
/// identity: its form, its value, and, when it has no predecessor, the
/// versions that it preserves. The first action of an identity counts.
Map<String, Map<String, dynamic>> _readableActions(
  String account,
  Iterable<Map<String, dynamic>> actions,
) {
  final readable = <String, Map<String, dynamic>>{};
  for (final action in actions) {
    final identity = RecordJournal.identity(action);
    if (readable.containsKey(identity)) continue;
    try {
      RecordJournal(
        account,
        'salvage',
        null,
        validateRecordAction,
      ).receive([action]);
      readable[identity] = action;
    } on FormatException {
      continue;
    }
  }
  return readable;
}

/// The account of `input.account` with its settings `input.metadata` and
/// the journal that `input.sync` encodes, in which each of `input.copies`
/// replaces the action of its identity, and counts as uploaded. It must be
/// saved as a damaged account, which keeps the saved data aside.
///
/// Throws a [FormatException] when the journal does not accept the copies.
_Restored _withServerCopies(
  ({
    String account,
    Map<String, dynamic> metadata,
    Map<String, dynamic> sync,
    List<Map<String, dynamic>> copies,
    bool database,
  })
  input,
) {
  final copies = {
    for (final copy in input.copies) RecordJournal.identity(copy): copy,
  };
  final sync = input.sync;
  final journal = RecordJournal(input.account, sync['replica'] as String, {
    ...sync,
    'actions': [
      for (final action
          in (sync['actions'] as List).cast<Map<String, dynamic>>())
        copies[RecordJournal.identity(action)] ?? action,
    ],
    'pending': [
      for (final identity in (sync['pending'] as List).cast<String>())
        if (!copies.containsKey(identity)) identity,
    ],
  }, validateRecordAction);
  return (
    stored: (metadata: input.metadata, journal: journal),
    views: _views(input.metadata, journal.values),
    persist: true,
    damaged: true,
    commit: input.database
        ? RecordDatabase.encodeCommit(
            input.account,
            input.metadata,
            journal,
            initialize: true,
          )
        : null,
  );
}

/// The records of one account that its kept copies hold and that the
/// record file lacks: [actions] by identity, the identities of those that
/// wait for upload, and [records] of a snapshot in the format before the
/// journal, by address.
typedef _Kept = ({
  Map<String, Map<String, dynamic>> actions,
  Set<String> pending,
  Map<String, Map<String, dynamic>> records,
});

/// What the kept copies of damaged records hold that the record file lacks,
/// by account, and whether kept copies exist. `input.reader` reads the rows
/// kept aside, the kept record files and what the record file holds, when
/// the store has a database. `input.texts` are the kept preference values.
///
/// An action counts as waiting for upload when one of its copies says so,
/// or when a copy does not know. A second upload of an action is harmless,
/// because the server keeps one copy of each identity.
Future<({bool kept, Map<String, _Kept> accounts})> _readKept(
  ({RecordReader? reader, List<({String account, String text})> texts}) input,
) async {
  final found = await input.reader?.kept();
  final copies = [
    if (found != null)
      for (final (:account, :rows) in found.rows)
        (account: account, copy: _readableRows(rows)),
    for (final (:account, :text) in [...?found?.texts, ...input.texts])
      (account: account, copy: _readableText(text)),
  ];
  final held =
      await input.reader?.held({
        for (final (:account, copy: _) in copies) account,
      }) ??
      const <String, HeldIdentities>{};
  final accounts = <String, _Kept>{};
  for (final (:account, :copy) in copies) {
    final kept = accounts.putIfAbsent(
      account,
      () => (actions: {}, pending: {}, records: {}),
    );
    final holds = held[account];
    final pending = copy.pending?.toSet();
    for (final MapEntry(key: identity, value: action) in _readableActions(
      account,
      copy.actions,
    ).entries) {
      if (holds?.actions.contains(identity) ?? false) continue;
      kept.actions.putIfAbsent(identity, () => action);
      if (pending?.contains(identity) ?? true) kept.pending.add(identity);
    }
    for (final MapEntry(key: record, :value) in recoverableRecords(
      copy.records,
    )) {
      if (holds?.records.contains(record) ?? false) continue;
      kept.records.putIfAbsent(record, () => value);
    }
  }
  accounts.removeWhere(
    (_, kept) => kept.actions.isEmpty && kept.records.isEmpty,
  );
  return (
    kept: (found?.kept ?? false) || input.texts.isNotEmpty,
    accounts: accounts,
  );
}

/// The journal of `input.account` that `input.sync` encodes, or a new one
/// when it is null, after the normal merge of `input.actions`, with each of
/// them that `input.pending` names waiting for upload, and each of
/// `input.records` that it lacks. It returns the merged journal, whose
/// unsaved changes are the merge, the addresses of the records whose
/// current versions changed, and, when `input.database` says so, the rows of
/// its save with the settings `input.metadata`.
({RecordJournal journal, Set<String> changed, RecordCommit? commit}) _withKept(
  ({
    String account,
    Map<String, dynamic> metadata,
    Map<String, dynamic>? sync,
    List<Map<String, dynamic>> actions,
    Set<String> pending,
    Map<String, Map<String, dynamic>> records,
    bool database,
  })
  input,
) {
  final replica = input.sync?['replica'] as String? ?? _replica();
  var changed = <String>{};
  RecordJournal merged(List<Map<String, dynamic>> actions) {
    final journal = RecordJournal(
      input.account,
      replica,
      input.sync,
      validateRecordAction,
    )..persisted();
    changed = journal.receive(actions);
    return journal;
  }

  RecordJournal journal;
  try {
    journal = merged(input.actions);
  } on FormatException {
    // NOTE: Actions that each pass alone can still disagree with the
    // journal, such as one that preserves a version of another record. Each
    // one is tried then, and the kept copy keeps those that do not fit.
    final accepted = <Map<String, dynamic>>[];
    for (final action in input.actions) {
      try {
        merged([...accepted, action]);
        accepted.add(action);
      } on FormatException {
        continue;
      }
    }
    journal = merged(accepted);
  }
  for (final identity in input.pending) {
    if (journal.additions.containsKey(identity)) journal.markPending(identity);
  }
  for (final MapEntry(key: record, :value) in input.records.entries) {
    if (journal.versionsByRecord.containsKey(record)) continue;
    try {
      journal.change(record, value);
      changed.add(record);
    } on FormatException {
      continue;
    }
  }
  return (
    journal: journal,
    changed: changed,
    commit: input.database
        ? RecordDatabase.encodeCommit(
            input.account,
            input.metadata,
            journal,
            initialize: input.sync == null,
          )
        : null,
  );
}

/// The first commit of each of [accounts] that writes all of its settings
/// and its whole journal, encoded as [RecordJournal.encode] does.
List<RecordCommit> _wholeCommits(
  List<
    ({String account, Map<String, dynamic> metadata, Map<String, dynamic> sync})
  >
  accounts,
) => [
  for (final account in accounts)
    RecordDatabase.encodeCommit(
      account.account,
      account.metadata,
      _journal(account.account, {'sync': account.sync}),
      initialize: true,
    ),
];

/// A new account from the damaged saved text of `input.account`, from what
/// [_readableText] reads of it.
_Restored _salvageText(({String account, String text, bool database}) input) =>
    _salvaged(
      input.account,
      _readableText(input.text),
      database: input.database,
    );

/// A new account of [account] with a new installation identity from what
/// a damaged copy of it still holds ([_Readable]): its settings, each of
/// its actions that the journal accepts, with its upload still pending
/// when the copy says so, and each of its records that decodes. When the
/// copy's pending identities are not known or name an action that is not
/// salvaged, every salvaged action is uploaded again.
///
/// Salvaged actions keep their identities, so a sync that receives them
/// again adds nothing, and the server keeps one copy of an action that is
/// uploaded twice. An action that follows an action that is lost waits
/// until a sync brings the lost one. The account is saved before anything
/// reads it, as [_readText] explains for a new identity.
_Restored _salvaged(String account, _Readable copy, {required bool database}) {
  final (:snapshot, :actions, :pending, :records) = copy;
  final metadata = _metadata({
    ...snapshot,
    'reading': snapshot['reading'] is Map<String, dynamic>
        ? snapshot['reading']
        : null,
  });
  final readable = _readableActions(account, actions);
  final replica = _replica();
  RecordJournal journal;
  try {
    journal = RecordJournal(account, replica, {
      'version': 1,
      'replica': replica,
      'actions': readable.values.toList(),
      'pending': pending != null && pending.every(readable.containsKey)
          ? pending
          : readable.keys.toList(),
      'cursor': 0,
    }, validateRecordAction);
  } on FormatException {
    // NOTE: Actions that pass alone can still disagree with each other, such
    // as one that preserves a version of another record. The damaged data
    // keeps them, and the next sync brings back the ones that it had sent.
    journal = RecordJournal(account, replica, null, validateRecordAction);
  }
  for (final MapEntry(key: record, :value) in recoverableRecords(records)) {
    try {
      journal.change(record, value);
    } on FormatException {
      continue;
    }
  }
  return (
    stored: (metadata: metadata, journal: journal),
    views: _views(metadata, journal.values),
    persist: true,
    damaged: true,
    commit: database
        ? RecordDatabase.encodeCommit(
            account,
            metadata,
            journal,
            initialize: true,
          )
        : null,
  );
}

/// [text] decoded, or null when it is not a JSON object.
Map<String, dynamic>? _decodedObject(String text) {
  try {
    final decoded = jsonDecode(text);
    return decoded is Map<String, dynamic> ? decoded : null;
  } on FormatException {
    return null;
  }
}

/// A new random installation identity.
String _replica() => List.generate(
  20,
  (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();

RecordJournal _journal(String account, Map<String, dynamic> combined) {
  if (combined.containsKey('sync') &&
      combined['sync'] is! Map<String, dynamic>) {
    throw const FormatException(
      'The personal-record journal must be an object.',
    );
  }
  final saved = combined['sync'] as Map<String, dynamic>?;
  if (saved != null && saved['replica'] is! String) {
    throw const FormatException(
      'The personal-record journal needs an installation identity.',
    );
  }
  final replica = saved?['replica'] as String? ?? _replica();
  final journal = RecordJournal(account, replica, saved, validateRecordAction);
  if (saved == null) {
    for (final reading in [false, true]) {
      for (final entry in flattenRecords(combined, reading: reading).entries) {
        journal.change(entry.key, entry.value);
      }
    }
  }
  return journal;
}

/// Copies the whole upload snapshot away from the store's retained actions.
List<Map<String, dynamic>> _copyActions(List<Map<String, dynamic>> actions) =>
    (jsonDecode(jsonEncode(actions)) as List).cast<Map<String, dynamic>>();
