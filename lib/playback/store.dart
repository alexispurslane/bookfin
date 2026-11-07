import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'playback.dart';
import '../sync/journal.dart';
import '../catalog/jellyfin.dart';
import 'database.dart';

/// One stored account: the settings of both domains and the record journal.
///
/// [metadata] holds the listening settings at the top and the reading
/// settings under `reading`, without records. The journal is the only owner
/// of records. Snapshots derive from it when a writer reads them.
typedef _StoredAccount = ({
  Map<String, dynamic> metadata,
  RecordJournal journal,
});

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
/// until [resolve]. A store that cannot be read is never written over: each
/// read and write of its account fails, and the data stays as it was.
///
/// Invariants, checked on demand by [checkInvariants]:
/// - The journal of each cached account satisfies
///   [RecordJournal.checkInvariants].
/// - The durable rows of each cached account equal its journal and settings.
class LocalResumeStore implements ResumeStore, ListeningStore {
  LocalResumeStore({this.openDatabase});
  final Future<RecordDatabase> Function()? openDatabase;
  Future<RecordDatabase>? _database;
  Future<RecordDatabase?> _storage() async {
    if (openDatabase == null) return null;
    return _database ??= openDatabase!();
  }

  late final ResumeStore reading = _ReadingRecords(this);
  Future<void> _writes = Future.value();
  final Map<String, Map<String, Map<String, dynamic>>> _observed = {};
  final Map<String, _StoredAccount> _accounts = {};
  String _key(String accountKey) => 'bookfin.playback.v1.$accountKey';

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
        if (!completed) _accounts.remove(account);
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

  Future<void> synchronize(
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
      await _update(account, (journal) {
        journal.receive(actions);
        journal.cursor = previous;
      });
      if (page['HasMore'] == false) return;
    }
    throw Exception(
      'Personal-record sync is incomplete. Retry to continue discovery.',
    );
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

  Future<Map<String, List<Map<String, dynamic>>>> conflicts(String account) =>
      _access(account, (stored) {
        final conflicts = jsonDecode(
          jsonEncode(stored?.journal.conflicts ?? {}),
        ) as Map<String, dynamic>;
        return {
          for (final entry in conflicts.entries)
            entry.key: (entry.value as List).cast<Map<String, dynamic>>(),
        };
      });

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
        return true;
      });
  @override
  Future<Map<String, dynamic>?> read(String accountKey) => _access(
    accountKey,
    (stored) => stored == null ? null : _snapshot(stored, reading: false),
  );

  Future<_StoredAccount?> _readAccount(String accountKey) async {
    final database = await _storage();
    if (database != null) {
      final cached = _accounts[accountKey];
      if (cached != null) return cached;
      final rows = await database.load(accountKey);
      if (rows != null) {
        final journal = _journal(accountKey, {'sync': rows['sync']});
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
        return _accounts[accountKey] = (
          metadata: rows['snapshot'] as Map<String, dynamic>,
          journal: journal,
        );
      }
    }
    final preferences = await SharedPreferences.getInstance();
    final legacy = await database?.read(accountKey);
    final raw = legacy ?? preferences.getString(_key(accountKey));
    if (raw == null) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Personal records must be an object.');
    }
    final reading = decoded['reading'];
    if (reading != null && reading is! Map<String, dynamic>) {
      throw const FormatException('Reading records must be an object.');
    }
    final stored = (
      metadata: _metadata(decoded),
      journal: _journal(accountKey, decoded),
    );
    if (database != null || decoded['sync'] == null) {
      // Records move from preferences into the database, or from a format
      // without a journal into one, before anything reads them. A journal
      // made here has a new installation identity, and a sync that read an
      // unsaved one would upload each record under an identity that the
      // next read replaces.
      await _persist(accountKey, stored.metadata, stored.journal);
    }
    return stored;
  }

  Future<void> _persist(
    String account,
    Map<String, dynamic> metadata,
    RecordJournal journal,
  ) async {
    final database = await _storage();
    final stored = (metadata: metadata, journal: journal);
    if (database != null) {
      await database.commit(
        account,
        metadata,
        journal,
        initialize: !_accounts.containsKey(account),
      );
      journal.persisted();
      _accounts[account] = stored;
    } else {
      // Without a database the whole account is one preference value, so a
      // kill leaves the old value or the new one if the platform writes one
      // value atomically. Only the web runs this branch outside tests, and
      // its plugin writes with one localStorage.setItem call. The Linux and
      // Windows plugins rewrite one JSON file in place, so give a build for
      // those platforms the database.
      final value = {
        ..._snapshot(stored, reading: false),
        'reading': _snapshot(stored, reading: true),
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

  /// The listening or reading snapshot of [stored]: the domain's settings
  /// plus the current value of each of its records, as a fresh copy.
  Map<String, dynamic> _snapshot(
    _StoredAccount stored, {
    required bool reading,
  }) {
    final domain = reading ? 'reading' : 'audio';
    final snapshot = <String, dynamic>{
      ...reading
          ? stored.metadata['reading'] as Map<String, dynamic>
          : (Map.of(stored.metadata)..remove('reading')),
      'bookmarks': <dynamic>[],
      if (!reading) 'history': <dynamic>[],
      'resumes': reading ? <dynamic>[] : <String, dynamic>{},
    };
    for (final entry in stored.journal.values.entries) {
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
    return jsonDecode(jsonEncode(snapshot)) as Map<String, dynamic>;
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
      _acceptSnapshot(accountKey, value ?? {}, reading: false);

  /// Saves a whole listening or reading [value] by the changes of its records
  /// from what its writer last saved or accepted. A record that the writer
  /// knew and that [value] lacks is deleted.
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
        if (!completed) _accounts.remove(account);
      }
    });
    _writes = operation.catchError((Object _) {});
    return operation;
  }

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
    final replica =
        saved?['replica'] as String? ??
        List.generate(
          20,
          (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join();
    final journal = RecordJournal(
      account,
      replica,
      saved,
      _validateActionValue,
    );
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
        final values = entry.value is List
            ? entry.value as List
            : [entry.value];
        for (final raw in values) {
          if (raw is! Map<String, dynamic>) {
            throw const FormatException(
              'A listening resume must be an object.',
            );
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

  void _acceptSnapshot(
    String account,
    Map<String, dynamic> combined, {
    required bool reading,
  }) {
    final snapshot = jsonDecode(jsonEncode(combined)) as Map<String, dynamic>;
    _observed['$account/${reading ? 'reading' : 'audio'}'] = _flatten(
      snapshot,
      reading: reading,
    );
  }
}

class _ReadingRecords implements ResumeStore {
  _ReadingRecords(this.owner);
  final LocalResumeStore owner;
  @override
  Future<Map<String, dynamic>?> read(String accountKey) async {
    return owner._access(accountKey, (stored) {
      return stored == null ? null : owner._snapshot(stored, reading: true);
    });
  }

  @override
  Future<void> write(String accountKey, Map<String, dynamic> value) =>
      owner._write(accountKey, value, reading: true);

  @override
  void acceptSnapshot(String accountKey, Map<String, dynamic>? value) =>
      owner._acceptSnapshot(accountKey, {'reading': value}, reading: true);
}
