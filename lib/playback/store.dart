import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'playback.dart';
import '../sync/journal.dart';
import '../catalog/jellyfin.dart';
import 'database.dart';

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
  String _key(String accountKey) => 'bookfin.playback.v1.$accountKey';

  Future<T> _update<T>(
    String account,
    T Function(Map<String, dynamic>, RecordJournal) change,
  ) {
    final operation = _writes.then((_) async {
      final combined = await _readAccount(account) ?? <String, dynamic>{};
      final journal = _journal(account, combined);
      final result = change(combined, journal);
      journal.checkInvariants();
      _materialize(combined, journal);
      await _persist(account, combined);
      return result;
    });
    _writes = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }

  Future<void> synchronize(
    JellyfinSession session,
    JellyfinClient client,
  ) async {
    await client.validate(session);
    final account = session.scope.key;
    final uploads = await _update(account, (_, journal) => journal.uploads);
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
      await _update(account, (_, journal) => journal.pending.remove(identity));
    }
    for (var request = 0; request < 128; request++) {
      final after = await _update(account, (_, journal) => journal.cursor);
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
        for (final action in actions) {
          _validateRemote(action);
        }
        journal.cursor = previous;
      });
      if (page['HasMore'] == false) return;
    }
    throw Exception(
      'Personal-record sync is incomplete. Retry to continue discovery.',
    );
  }

  void _validateRemote(Map<String, dynamic> action) {
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
                    value['edition']: [
                      {...value}..remove('edition'),
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
    } catch (_) {
      throw const FormatException(
        'A remote personal record is invalid. Local records were kept.',
      );
    }
  }

  Future<Map<String, List<Map<String, dynamic>>>> conflicts(
    String account,
  ) async {
    await _writes;
    return _journal(account, await _readAccount(account) ?? {}).conflicts;
  }

  Future<void> resolve(String account, String record, String identity) =>
      _update(account, (_, journal) {
        final versions = journal.conflicts[record];
        final selected = versions
            ?.where((action) => RecordJournal.identity(action) == identity)
            .firstOrNull;
        if (selected == null) {
          throw ArgumentError('Choose a current personal-record conflict.');
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
              if (audio) 'editionLabel': 'Source ${value['source']}',
            });
          }
        }
        journal.change(
          record,
          selected['value'] as Map<String, dynamic>?,
          resolve: true,
        );
      });
  @override
  Future<Map<String, dynamic>?> read(String accountKey) async {
    await _writes;
    final combined = await _readAccount(accountKey);
    if (combined == null) return null;
    _observe(accountKey, combined, reading: false);
    final audio = Map<String, dynamic>.from(combined)
      ..remove('reading')
      ..remove('sync');
    return audio.isEmpty ? null : audio;
  }

  Future<Map<String, dynamic>?> _readAccount(String accountKey) async {
    final database = await _storage();
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
    if (stored == null && database != null) {
      await database.write(accountKey, raw);
    }
    return decoded;
  }

  Future<void> _persist(String account, Map<String, dynamic> value) async {
    final payload = jsonEncode(value);
    final database = await _storage();
    if (database != null) {
      await database.write(account, payload);
    } else {
      final preferences = await SharedPreferences.getInstance();
      if (!await preferences.setString(_key(account), payload)) {
        throw Exception(
          'Personal records were not saved. Free storage, then retry.',
        );
      }
    }
  }

  @override
  Future<void> write(String accountKey, Map<String, dynamic> value) =>
      _write(accountKey, value, reading: false);

  Future<void> _write(
    String accountKey,
    Map<String, dynamic> value, {
    required bool reading,
  }) {
    final snapshot = jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
    final operation = _writes.then((_) async {
      final existing = await _readAccount(accountKey) ?? <String, dynamic>{};
      final journal = _journal(accountKey, existing);
      final previous =
          _observed['$accountKey/${reading ? 'reading' : 'audio'}'] ??
          _flatten(existing, reading: reading);
      final combined = reading
          ? <String, dynamic>{...existing, 'reading': snapshot}
          : <String, dynamic>{
              ...snapshot,
              if (existing['reading'] != null) 'reading': existing['reading'],
            };
      final next = _flatten(combined, reading: reading);
      for (final record in {...previous.keys, ...next.keys}) {
        if (!const DeepCollectionEquality().equals(
          previous[record],
          next[record],
        )) {
          journal.change(record, next[record]);
        }
      }
      _materialize(combined, journal);
      await _persist(accountKey, combined);
      _observed['$accountKey/${reading ? 'reading' : 'audio'}'] = next;
    });
    _writes = operation.catchError((Object _) {});
    return operation;
  }

  RecordJournal _journal(String account, Map<String, dynamic> combined) {
    final saved = combined['sync'] as Map<String, dynamic>?;
    final replica =
        saved?['replica'] as String? ??
        List.generate(
          20,
          (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join();
    final journal = RecordJournal(account, replica, saved);
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
    combined['sync'] = journal.encode();
  }

  void _observe(
    String account,
    Map<String, dynamic> combined, {
    required bool reading,
  }) {
    try {
      _observed['$account/${reading ? 'reading' : 'audio'}'] = _flatten(
        combined,
        reading: reading,
      );
    } on FormatException {
      return;
    }
  }
}

class _ReadingRecords implements ResumeStore {
  _ReadingRecords(this.owner);
  final LocalResumeStore owner;
  @override
  Future<Map<String, dynamic>?> read(String accountKey) async {
    await owner._writes;
    final combined = await owner._readAccount(accountKey);
    if (combined != null) owner._observe(accountKey, combined, reading: true);
    return combined?['reading'] as Map<String, dynamic>?;
  }

  @override
  Future<void> write(String accountKey, Map<String, dynamic> value) =>
      owner._write(accountKey, value, reading: true);
}
