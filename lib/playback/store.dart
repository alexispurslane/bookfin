import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show compute;
import 'package:shared_preferences/shared_preferences.dart';

import 'playback.dart';
import '../sync/journal.dart';
import '../catalog/jellyfin.dart';
import 'database.dart';
import '../reader/session.dart' show ReadingChanges, ReadingStore;

/// Runs [work] on [input] in another isolate and completes with its result,
/// which comes back without a copy. [compute] is the default.
typedef RecordsHop = Future<R> Function<M, R>(R Function(M) work, M input);

/// Which domains of an account hold records that changed outside their
/// writer since the writer last took in a snapshot that the store handed
/// it: [listening] for Playback, [reading] for the reader. Sync and a
/// choice between saved versions change records outside the writers.
typedef StaleDomains = ({bool listening, bool reading});

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
/// Measured in AOT on an M-series Mac: a hop costs about 33 µs, replaying
/// one action about 12 µs, and deriving the snapshot of one record about
/// 5 µs, while copying one record into a hop costs about 0.6 µs. So a hop
/// pays from about four actions or eight records. These limits are a
/// compromise: widget tests run in fake time, in which a hop never
/// completes, and their accounts stay below them. A real account gains
/// about one action for each second of listening, so it is far above them.
const _hopItems = 16;

/// The shortest saved text of an account in the format before the journal
/// that the store decodes in another isolate. 4 KB holds about 15 records.
const _hopText = 4 * 1024;

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
/// When SQLite reports damaged pages in the record file during a read or a
/// write, the database keeps the whole file aside and continues on a new
/// file ([RecordFileSetAside]). The store then writes every account that it
/// holds in memory whole into the new file, with the write in progress, and
/// [setAside] reports the damage for every account.
///
/// Engine rule 1: the whole-account work of a read (journal replay, the
/// decoding of an older format, and each domain's snapshot) runs in one hop
/// to another isolate, and its result comes back without a copy. A save
/// does only the work of its own change on the UI isolate.
///
/// Invariants, checked on demand by [checkInvariants]:
/// - The journal of each cached account satisfies
///   [RecordJournal.checkInvariants].
/// - The durable rows of each cached account equal its journal and settings.
/// - Each kept view equals the view that its cached account derives.
class LocalResumeStore implements ResumeStore, ListeningStore {
  LocalResumeStore({this.openDatabase, RecordsHop? hop})
    : _hop = hop ?? compute;
  final Future<RecordDatabase> Function()? openDatabase;
  final RecordsHop _hop;
  Future<RecordDatabase>? _database;
  RecordDatabase? _opened;
  Future<RecordDatabase?> _storage() async {
    if (openDatabase == null) return null;
    return _opened ??= await (_database ??= openDatabase!());
  }

  /// The writers whose domain holds records that changed outside them since
  /// the last snapshot that they took in, as [StaleDomains] says.
  final Set<String> _behind = {};

  /// The accounts whose damaged data this store kept aside.
  final Set<String> _setAside = {};

  late final ReadingRecords reading = ReadingRecords._(this);
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
    R Function(M) work,
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
      final writer = _writer(
        account,
        reading: (jsonDecode(record) as List)[0] == 'reading',
      );
      _behind.add(writer);
      _handed.remove(writer);
    }
  }

  /// Drops the cached state of [account], so that the next operation reads
  /// it from storage.
  void _forget(String account) {
    _accounts.remove(account);
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

  Future<T> _access<T>(String account, T Function(_StoredAccount?) query) {
    final operation = _writes.then(
      (_) async => query(await _readAccount(account)),
    );
    _writes = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }

  Future<T> _query<T>(String account, T Function(RecordJournal) query) =>
      _access(
        account,
        (stored) => query(stored?.journal ?? _journal(account, {})),
      );

  /// Uploads the pending actions of the account of [session], then receives
  /// the actions that other devices uploaded, and saves each page of them
  /// with its discovery cursor in one write.
  ///
  /// Returns the domains whose writer has not taken in records that changed
  /// outside it, including records that an earlier sync saved before it
  /// failed. A sync that brings nothing new, or only this device's own
  /// actions, returns no stale domain once both writers are current.
  Future<StaleDomains> synchronize(
    JellyfinSession session,
    JellyfinClient client,
  ) async {
    await client.validate(session);
    final account = session.scope.key;
    final uploads = await _query(account, (journal) => journal.uploads);
    for (final action in uploads) {
      final identity = RecordJournal.identity(action);
      final payload = jsonEncode(action);
      final stored = await client.uploadPersonalRecord(
        session,
        identity,
        payload,
      );
      if (stored['Id'] != identity ||
          stored['Payload'] != payload ||
          stored['Deleted'] != false ||
          stored['Sequence'] is! int ||
          (stored['Sequence'] as int) < 1) {
        throw const FormatException(
          'The server did not confirm the pending personal record.',
        );
      }
      await _update(account, (journal) => journal.acknowledge(identity));
    }
    for (var request = 0; request < 128; request++) {
      final after = await _query(account, (journal) => journal.cursor);
      final page = await client.personalRecordChanges(session, after);
      if (page['Objects'] is! List ||
          page['Cursor'] is! int ||
          page['HasMore'] is! bool) {
        throw const FormatException(
          'Invalid personal-record discovery response.',
        );
      }
      final objects = page['Objects'] as List;
      var previous = after;
      final actions = <Map<String, dynamic>>[];
      for (final value in objects) {
        if (value is! Map<String, dynamic> ||
            value['Sequence'] is! int ||
            (value['Sequence'] as int) <= previous ||
            value['Deleted'] != false ||
            value['Payload'] is! String) {
          throw const FormatException(
            'Personal-record discovery is incomplete or contains retired actions.',
          );
        }
        previous = value['Sequence'] as int;
        final decoded = jsonDecode(value['Payload'] as String);
        if (decoded is! Map<String, dynamic> ||
            value['Id'] != RecordJournal.identity(decoded)) {
          throw const FormatException(
            'Invalid personal-record object identity.',
          );
        }
        actions.add(decoded);
      }
      if (page['Cursor'] != previous ||
          (page['HasMore'] == true && objects.isEmpty)) {
        throw const FormatException(
          'Personal-record discovery did not advance safely.',
        );
      }
      // The writers count as behind before the save, so that no read can
      // hand out a snapshot between the save and the mark. A failed save
      // costs one refresh that finds nothing new.
      await _update(account, (journal) {
        _changedOutsideWriters(account, journal.receive(actions));
        journal.cursor = previous;
      });
      if (page['HasMore'] == false) {
        return (
          listening: _behind.contains(_writer(account, reading: false)),
          reading: _behind.contains(_writer(account, reading: true)),
        );
      }
    }
    throw Exception(
      'Personal-record sync is incomplete. Retry to continue discovery.',
    );
  }

  Future<Map<String, List<Map<String, dynamic>>>> conflicts(String account) =>
      _access(account, (stored) {
        // NOTE: Engine rule 1. Only records with competing versions are
        // copied, which are few, so the copy costs less than a hop.
        final conflicts = jsonDecode(
          jsonEncode(stored?.journal.conflicts ?? {}),
        ) as Map<String, dynamic>;
        return {
          for (final entry in conflicts.entries)
            entry.key: (entry.value as List).cast<Map<String, dynamic>>(),
        };
      });

  /// Keeps the saved version [identity] of [record] and replaces the
  /// others, which a listening place keeps as bookmarks. Returns false and
  /// changes nothing when [record] has no such competing version.
  Future<bool> resolve(String account, String record, String identity) =>
      _update(account, (journal) {
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
            journal.change(jsonEncode([address[0], 'bookmarks', mark]), {
              'id': mark,
              'position': audio
                  ? {
                      'edition': value['edition'],
                      'source': value['source'],
                      'revision': value['revision'],
                      'milliseconds': value['milliseconds'],
                    }
                  : value,
              'createdAt': DateTime.now().toUtc().toIso8601String(),
              'title': 'Saved before sync choice',
              if (audio) 'bookTitle': 'Saved listening place',
              if (audio) 'editionLabel': 'Saved recording',
            });
          }
        }
        journal.change(
          record,
          selected['value'] as Map<String, dynamic>?,
          resolve: true,
        );
        _changedOutsideWriters(account, [record]);
        return true;
      });

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
        final views = await _derive(_viewsOfVersions, (
          metadata: stored.metadata,
          versions: versions,
        ), small: versions.length < _hopItems);
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
      final cached = _accounts[accountKey];
      if (cached != null) return cached;
      AccountRows? rows;
      try {
        rows = await database.rows(accountKey);
      } on RecordFileSetAside {
        await _rewriteCached(database);
      }
      if (rows != null) {
        return _adopt(
          accountKey,
          await _derive(_restoreRows, (
            account: accountKey,
            rows: rows,
          ), small: rows.payloads.length < _hopItems),
        );
      }
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

  /// Saves [restored] as the durable state of [account] when it must be
  /// saved, keeps its views, and returns it. [text] is the saved text that
  /// the hop restored, if any.
  ///
  /// A damaged account's data moves aside before the new account replaces
  /// it. With a database, both happen in one transaction, and preference
  /// text, which the store no longer reads once the account has rows, stays
  /// where it is. Without one, the text is copied to its own key first.
  Future<_StoredAccount> _adopt(
    String account,
    _Restored restored, {
    String? text,
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
    if (restored.damaged) _setAside.add(account);
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
              RecordDatabase.encodeCommit(
                account,
                metadata,
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
      //
      // NOTE: Engine rule 1. This encodes the whole account on the calling
      // isolate for each save. The web has no isolates, so a hop would run
      // there inline too.
      final values = journal.values;
      final value = {
        ..._snapshot(metadata, values, reading: false),
        'reading': _snapshot(metadata, values, reading: true),
        'sync': journal.encode(),
      };
      final preferences = await SharedPreferences.getInstance();
      if (!await preferences.setString(_key(account), jsonEncode(value))) {
        throw Exception(
          'Personal records were not saved. Free storage, then retry.',
        );
      }
    }
  }

  /// Writes every cached account whole into the new file that replaced a
  /// damaged record file, in one transaction, so that the records that the
  /// store holds in memory stay on the phone. A hop encodes them.
  Future<void> _rewriteCached(RecordDatabase database) async {
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
      await _derive(_wholeCommits, input, small: actions < _hopItems),
    );
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
        ..._flatten({'resumes': copied['resumes']}, reading: false),
      },
    );
  }

  @override
  void acceptSnapshot(String accountKey, Map<String, dynamic>? value) =>
      _accept(accountKey, value, reading: false);

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
      _behind.remove(writer);
      return;
    }
    // NOTE: Engine rule 1. Production writers accept the snapshot that their
    // read returned, which the branch above takes. This branch serves other
    // callers, such as tests, and a writer that has no saved records.
    final snapshot = _copy(value ?? const {});
    _observed[writer] = _flatten(
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
        final next = _flatten(
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
    Map<String, dynamic> settings, {
    required bool reading,
    required Map<String, Map<String, dynamic>?> Function(
      Map<String, Map<String, dynamic>> observed,
    )
    records,
  }) {
    final writer = '$account/${reading ? 'reading' : 'audio'}';
    final operation = _writes.then((_) async {
      var completed = false;
      try {
        final stored = await _readAccount(account);
        final journal = stored?.journal ?? _journal(account, {});
        final observed = _observed[writer] ?? {};
        final changed = records(observed);
        for (final MapEntry(key: record, :value) in changed.entries) {
          if (!const DeepCollectionEquality().equals(
            observed[record] ?? journal.value(record),
            value,
          )) {
            journal.change(record, value);
          }
        }
        final previous = stored?.metadata ?? _metadata({});
        await _persist(
          account,
          _metadata(
            reading
                ? {...previous, 'reading': settings}
                : {...settings, 'reading': previous['reading']},
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

/// The reading records of a [LocalResumeStore], as the reader uses them.
class ReadingRecords implements ResumeStore, ReadingStore {
  ReadingRecords._(this.owner);
  final LocalResumeStore owner;
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
      'settings': changes.settings,
      'resumes': changes.resumes,
      'bookmarks': changes.bookmarks,
    });
    return owner._change(
      accountKey,
      copied['settings'] as Map<String, dynamic>,
      reading: true,
      records: (_) => {
        for (final entry in (copied['bookmarks'] as Map).entries)
          jsonEncode(['reading', 'bookmarks', entry.key]):
              entry.value as Map<String, dynamic>?,
        ..._flatten({
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
}

void _validateActionValue(Map<String, dynamic> action) {
  final value = action['value'] as Map<String, dynamic>?;
  if (value == null) return;
  final address = jsonDecode(action['record'] as String) as List;
  final reading = address[0] == 'reading';
  try {
    switch (address[1]) {
      case 'bookmarks':
        if (value['id'] != address[2]) throw const FormatException();
        if (reading) {
          TextBookmark.fromJson(value);
        } else {
          AudioBookmark.fromJson(value);
        }
      case 'history':
        if (reading || value['id'] != address[2]) {
          throw const FormatException();
        }
        ListeningEvent.fromJson(value);
      case 'resumes':
        if (reading) {
          decodeTextPosition(value);
        } else {
          decodePosition(value);
        }
        final projected = reading
            ? {
                'reading': {
                  'resumes': [value],
                },
              }
            : {
                'resumes': {
                  value['edition'] as String: [
                    <String, dynamic>{...value}..remove('edition'),
                  ],
                },
              };
        if (!_flatten(
          projected,
          reading: reading,
        ).containsKey(action['record'])) {
          throw const FormatException();
        }
    }
  } on FormatException {
    throw const FormatException(
      'A personal record is invalid. Existing records were kept.',
    );
  } on TypeError {
    // Record decoders also use checked casts for persisted field types.
    throw const FormatException(
      'A personal record is invalid. Existing records were kept.',
    );
  }
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

/// The listening or reading snapshot of an account with [metadata] and the
/// record [values] of [RecordJournal.values]: the domain's settings plus
/// the current value of each of its records, as a fresh copy. It changes
/// the listening resumes of [values].
Map<String, dynamic> _snapshot(
  Map<String, dynamic> metadata,
  Map<String, Map<String, dynamic>> values, {
  required bool reading,
}) {
  final domain = reading ? 'reading' : 'audio';
  final snapshot = <String, dynamic>{
    ...reading
        ? metadata['reading'] as Map<String, dynamic>
        : (Map.of(metadata)..remove('reading')),
    'bookmarks': <dynamic>[],
    if (!reading) 'history': <dynamic>[],
    'resumes': reading ? <dynamic>[] : <String, dynamic>{},
  };
  for (final entry in values.entries) {
    final address = jsonDecode(entry.key) as List;
    if (address[0] != domain) continue;
    final collection = address[1] as String;
    final value = entry.value;
    if (!reading && collection == 'resumes') {
      final edition = value.remove('edition') as String;
      ((snapshot['resumes'] as Map).putIfAbsent(
        edition,
        () => <dynamic>[],
      ) as List).add(value);
    } else {
      (snapshot[collection] as List).add(value);
    }
  }
  return _copy(snapshot);
}

Map<String, dynamic> _copy(Map<String, dynamic> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

/// Both views of an account with [metadata] and the record [values] of
/// [RecordJournal.values]. It changes [values].
_Views _views(
  Map<String, dynamic> metadata,
  Map<String, Map<String, dynamic>> values,
) {
  _View view({required bool reading}) {
    final snapshot = _snapshot(metadata, values, reading: reading);
    final copy = _copy(snapshot);
    return (
      snapshot: snapshot,
      records: _flatten(reading ? {'reading': copy} : copy, reading: reading),
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

/// A new account from the damaged [AccountRows] of `input.account`: the
/// settings when they decode, and each action that decodes. Malformed rows
/// may have lost the upload state, so every action is uploaded again.
_Restored _salvageRows(({String account, AccountRows rows}) input) {
  final rows = input.rows;
  return _salvaged(
    input.account,
    _decodedObject(rows.metadata) ?? {},
    actions: [for (final payload in rows.payloads) ?_decodedObject(payload)],
    pending: rows.malformed ? null : rows.pending,
    database: true,
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

/// A new account from the damaged saved text of `input.account`: the
/// settings and each record or action that still decodes.
_Restored _salvageText(({String account, String text, bool database}) input) {
  final decoded = _decodedObject(input.text) ?? {};
  final sync = decoded['sync'];
  if (sync is! Map<String, dynamic>) {
    return _salvaged(
      input.account,
      decoded,
      records: decoded,
      database: input.database,
    );
  }
  final actions = sync['actions'];
  final pending = sync['pending'];
  return _salvaged(
    input.account,
    decoded,
    actions: [
      if (actions is List)
        for (final action in actions)
          if (action is Map<String, dynamic>) action,
    ],
    pending: pending is List && pending.every((identity) => identity is String)
        ? pending.cast<String>()
        : null,
    database: input.database,
  );
}

/// A new account of [account] with a new installation identity: the
/// settings of [snapshot], each of [actions] that the journal accepts, with
/// its upload still pending when [pending] names it, and each record of
/// [records], a snapshot in the format before the journal, that decodes.
/// When [pending] is null or names an action that is not salvaged, the
/// upload state is not known, so every salvaged action is uploaded again.
///
/// Salvaged actions keep their identities, so a sync that receives them
/// again adds nothing, and the server keeps one copy of an action that is
/// uploaded twice. An action that follows an action that is lost waits
/// until a sync brings the lost one. The account is saved before anything
/// reads it, as [_readText] explains for a new identity.
_Restored _salvaged(
  String account,
  Map<String, dynamic> snapshot, {
  List<Map<String, dynamic>> actions = const [],
  List<String>? pending = const [],
  Map<String, dynamic> records = const {},
  required bool database,
}) {
  final metadata = _metadata({
    ...snapshot,
    'reading': snapshot['reading'] is Map<String, dynamic>
        ? snapshot['reading']
        : null,
  });
  final readable = <String, Map<String, dynamic>>{};
  for (final action in actions) {
    final identity = RecordJournal.identity(action);
    if (readable.containsKey(identity)) continue;
    try {
      // A journal of its own checks one action alone: its form, its value,
      // and, when it has no predecessor, the versions that it preserves.
      RecordJournal(
        account,
        'salvage',
        null,
        _validateActionValue,
      ).receive([action]);
      readable[identity] = action;
    } on FormatException {
      continue;
    }
  }
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
    }, _validateActionValue);
  } on FormatException {
    // NOTE: Actions that pass alone can still disagree with each other, such
    // as one that preserves a version of another record. The damaged data
    // keeps them, and the next sync brings back the ones that it had sent.
    journal = RecordJournal(account, replica, null, _validateActionValue);
  }
  for (final MapEntry(key: record, :value) in _records(records)) {
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

/// Each record of [combined], a snapshot in the format before the journal,
/// that decodes on its own, by address, as [_flatten] reads it.
Iterable<MapEntry<String, Map<String, dynamic>>> _records(
  Map<String, dynamic> combined,
) sync* {
  for (final reading in [false, true]) {
    final snapshot = reading ? combined['reading'] : combined;
    if (snapshot is! Map<String, dynamic>) continue;
    final pieces = <Map<String, dynamic>>[
      for (final collection in [
        'bookmarks',
        if (!reading) 'history',
        if (reading) 'resumes',
      ])
        if (snapshot[collection] case final List values)
          for (final value in values)
            {
              collection: [value],
            },
      if (!reading && snapshot['resumes'] is Map<String, dynamic>)
        for (final MapEntry(key: edition, :value)
            in (snapshot['resumes'] as Map<String, dynamic>).entries)
          for (final place in value is List ? value : [value])
            {
              'resumes': {
                edition: [place],
              },
            },
    ];
    for (final piece in pieces) {
      try {
        yield* _flatten(
          reading ? {'reading': piece} : piece,
          reading: reading,
        ).entries;
      } on FormatException {
        continue;
      }
    }
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
  final journal = RecordJournal(account, replica, saved, _validateActionValue);
  if (saved == null) {
    for (final reading in [false, true]) {
      for (final entry in _flatten(combined, reading: reading).entries) {
        journal.change(entry.key, entry.value);
      }
    }
  }
  return journal;
}

Map<String, Map<String, dynamic>> _flatten(
  Map<String, dynamic> combined, {
  required bool reading,
}) {
  final domain = reading ? 'reading' : 'audio';
  final snapshot = reading
      ? combined['reading'] as Map<String, dynamic>?
      : combined;
  if (snapshot == null) return {};
  for (final collection in [
    'bookmarks',
    if (!reading) 'history',
    if (reading) 'resumes',
  ]) {
    final values = snapshot[collection];
    if (values != null &&
        (values is! List ||
            values.any((value) => value is! Map<String, dynamic>))) {
      throw const FormatException('Invalid personal-record collection.');
    }
  }
  final result = <String, Map<String, dynamic>>{};
  if (!reading &&
      snapshot['resumes'] != null &&
      snapshot['resumes'] is! Map<String, dynamic>) {
    throw const FormatException('Listening resumes must be an object.');
  }
  for (final collection in ['bookmarks', if (!reading) 'history']) {
    for (final value in (snapshot[collection] as List? ?? []).cast<Map>()) {
      result[jsonEncode([domain, collection, value['id']])] =
          Map<String, dynamic>.from(value);
    }
  }
  if (reading) {
    for (final value in (snapshot['resumes'] as List? ?? []).cast<Map>()) {
      final address = jsonEncode([
        value['edition'],
        value['source'],
        value['revision'],
      ]);
      result[jsonEncode([domain, 'resumes', address])] =
          Map<String, dynamic>.from(value);
    }
  } else {
    for (final entry in (snapshot['resumes'] as Map? ?? {}).entries) {
      final values = entry.value is List ? entry.value as List : [entry.value];
      for (final raw in values) {
        if (raw is! Map<String, dynamic>) {
          throw const FormatException('A listening resume must be an object.');
        }
        final value = Map<String, dynamic>.from(raw as Map);
        final address = jsonEncode([
          entry.key,
          if (value['sources'] != null)
            value['sources']
          else ...[
            value['source'],
            value['revision'],
          ],
        ]);
        result[jsonEncode([domain, 'resumes', address])] = {
          ...value,
          'edition': entry.key,
        };
      }
    }
  }
  return result;
}
