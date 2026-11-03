import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'playback.dart';
import '../sync/journal.dart';
import '../catalog/jellyfin.dart';
import 'database.dart';

typedef _StoredAccount = ({
  Map<String, dynamic> snapshot,
  RecordJournal journal,
});

class LocalResumeStore implements ResumeStore {
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

  Future<T> _update<T>(
    String account,
    T Function(Map<String, dynamic>, RecordJournal) change,
  ) {
    final operation = _writes.then((_) async {
      var completed = false;
      try {
        final stored = await _readAccount(account);
        final combined = stored?.snapshot ?? <String, dynamic>{};
        final journal = stored?.journal ?? _journal(account, combined);
        final result = change(combined, journal);
        _materialize(combined, journal);
        await _persist(account, combined, journal);
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
      await _update(account, (_, journal) => journal.acknowledge(identity));
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
      await _update(account, (_, journal) {
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
      _update(account, (_, journal) {
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
  Future<Map<String, dynamic>?> read(String accountKey) =>
      _access(accountKey, (stored) {
        final combined = stored?.snapshot;
        if (combined == null) return null;
        final audio = Map<String, dynamic>.from(combined)
          ..remove('reading')
          ..remove('sync');
        return audio.isEmpty
            ? null
            : jsonDecode(jsonEncode(audio)) as Map<String, dynamic>;
      });

  Future<_StoredAccount?> _readAccount(String accountKey) async {
    final database = await _storage();
    if (database != null) {
      final cached = _accounts[accountKey];
      if (cached != null) return cached;
      final rows = await database.load(accountKey);
      if (rows != null) {
        final combined = <String, dynamic>{
          ...rows['snapshot'] as Map<String, dynamic>,
          'sync': rows['sync'],
        };
        final journal = _journal(accountKey, combined);
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
        _materialize(combined, journal);
        return _accounts[accountKey] = (snapshot: combined, journal: journal);
      }
    }
    final preferences = await SharedPreferences.getInstance();
    final stored = await database?.read(accountKey);
    final raw = stored ?? preferences.getString(_key(accountKey));
    if (raw == null) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Personal records must be an object.');
    }
    final reading = decoded['reading'];
    if (reading != null && reading is! Map<String, dynamic>) {
      throw const FormatException('Reading records must be an object.');
    }
    final journal = _journal(accountKey, decoded);
    _materialize(decoded, journal);
    if (database != null) {
      await database.commit(
        accountKey,
        _metadata(decoded),
        journal,
        initialize: true,
      );
      journal.persisted();
      _accounts[accountKey] = (snapshot: decoded, journal: journal);
    }
    return (snapshot: decoded, journal: journal);
  }

  Future<void> _persist(
    String account,
    Map<String, dynamic> value,
    RecordJournal journal,
  ) async {
    final database = await _storage();
    if (database != null) {
      await database.commit(
        account,
        _metadata(value),
        journal,
        initialize: !_accounts.containsKey(account),
      );
      journal.persisted();
      _accounts[account] = (snapshot: value, journal: journal);
    } else {
      final preferences = await SharedPreferences.getInstance();
      if (!await preferences.setString(_key(account), jsonEncode(value))) {
        throw Exception(
          'Personal records were not saved. Free storage, then retry.',
        );
      }
    }
  }

  Map<String, dynamic> _metadata(Map<String, dynamic> snapshot) {
    Map<String, dynamic> withoutRecords(Map<String, dynamic> value) =>
        Map<String, dynamic>.from(value)
          ..remove('sync')
          ..remove('bookmarks')
          ..remove('history')
          ..remove('resumes')
          ..remove('reading');
    return {
      ...withoutRecords(snapshot),
      if (snapshot['reading'] != null)
        'reading': withoutRecords(snapshot['reading'] as Map<String, dynamic>),
    };
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
            !const DeepCollectionEquality().equals({
              ..._flatten(entry.value.snapshot, reading: false),
              ..._flatten(entry.value.snapshot, reading: true),
            }, journal.values) ||
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
              _metadata(entry.value.snapshot),
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
  void acceptSnapshot(String accountKey, Map<String, dynamic>? value) =>
      _acceptSnapshot(accountKey, value ?? {}, reading: false);

  Future<void> _write(
    String accountKey,
    Map<String, dynamic> value, {
    required bool reading,
  }) {
    final snapshot = jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
    final operation = _writes.then((_) async {
      var completed = false;
      try {
        final stored = await _readAccount(accountKey);
        final existing = stored?.snapshot ?? <String, dynamic>{};
        final journal = stored?.journal ?? _journal(accountKey, existing);
        final previous =
            _observed['$accountKey/${reading ? 'reading' : 'audio'}'] ??
            <String, Map<String, dynamic>>{};
        final combined = reading
            ? <String, dynamic>{...existing, 'reading': snapshot}
            : <String, dynamic>{
                ...snapshot,
                if (existing['reading'] != null) 'reading': existing['reading'],
              };
        final next = _flatten(combined, reading: reading);
        final retained = journal.values;
        for (final record in {...previous.keys, ...next.keys}) {
          if (!const DeepCollectionEquality().equals(
            previous[record] ?? retained[record],
            next[record],
          )) {
            journal.change(record, next[record]);
          }
        }
        _materialize(combined, journal);
        await _persist(accountKey, combined, journal);
        _observed['$accountKey/${reading ? 'reading' : 'audio'}'] = next;
        completed = true;
      } finally {
        if (!completed) _accounts.remove(accountKey);
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

  void _materialize(Map<String, dynamic> combined, RecordJournal journal) {
    final audio = <String, dynamic>{
      ...combined,
      'version': 3,
      'bookmarks': <dynamic>[],
      'history': <dynamic>[],
      'resumes': <String, dynamic>{},
    };
    final reading = <String, dynamic>{
      ...?combined['reading'] as Map<String, dynamic>?,
      'version': 1,
      'bookmarks': <dynamic>[],
      'resumes': <dynamic>[],
    };
    for (final entry in journal.values.entries) {
      final address = jsonDecode(entry.key) as List;
      final target = address[0] == 'reading' ? reading : audio;
      final collection = address[1] as String;
      final value = Map<String, dynamic>.from(entry.value);
      if (address[0] == 'audio' && collection == 'resumes') {
        final edition = value.remove('edition') as String;
        ((target[collection] as Map).putIfAbsent(
          edition,
          () => <dynamic>[],
        ) as List).add(value);
      } else {
        (target[collection] as List).add(value);
      }
    }
    combined
      ..clear()
      ..addAll(audio);
    combined['reading'] = reading;
    if (openDatabase == null) {
      combined['sync'] = journal.encode();
    } else {
      combined.remove('sync');
    }
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
      final reading = stored?.snapshot['reading'];
      return reading == null
          ? null
          : jsonDecode(jsonEncode(reading)) as Map<String, dynamic>;
    });
  }

  @override
  Future<void> write(String accountKey, Map<String, dynamic> value) =>
      owner._write(accountKey, value, reading: true);

  @override
  void acceptSnapshot(String accountKey, Map<String, dynamic>? value) =>
      owner._acceptSnapshot(accountKey, {'reading': value}, reading: true);
}
