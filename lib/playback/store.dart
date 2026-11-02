import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'playback.dart';

class LocalResumeStore implements ResumeStore {
  late final ResumeStore reading = _ReadingRecords(this);
  Future<void> _writes = Future.value();
  String _key(String accountKey) => 'bookfin.playback.v1.$accountKey';
  @override
  Future<Map<String, dynamic>?> read(String accountKey) async {
    await _writes;
    final combined = await _readAccount(accountKey);
    if (combined == null) return null;
    final audio = Map<String, dynamic>.from(combined)..remove('reading');
    return audio.isEmpty ? null : audio;
  }

  Future<Map<String, dynamic>?> _readAccount(String accountKey) async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_key(accountKey));
    if (raw == null) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Personal records must be an object.');
    }
    final reading = decoded['reading'];
    if (reading != null && reading is! Map<String, dynamic>) {
      throw const FormatException('Reading records must be an object.');
    }
    return decoded;
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
      final preferences = await SharedPreferences.getInstance();
      final existing = await _readAccount(accountKey) ?? <String, dynamic>{};
      final combined = reading
          ? <String, dynamic>{...existing, 'reading': snapshot}
          : <String, dynamic>{
              ...snapshot,
              if (existing['reading'] != null) 'reading': existing['reading'],
            };
      if (!await preferences.setString(
        _key(accountKey),
        jsonEncode(combined),
      )) {
        throw Exception(
          'Personal records were not saved. Free storage, then retry.',
        );
      }
    });
    _writes = operation.catchError((Object _) {});
    return operation;
  }
}

class _ReadingRecords implements ResumeStore {
  _ReadingRecords(this.owner);
  final LocalResumeStore owner;
  @override
  Future<Map<String, dynamic>?> read(String accountKey) async {
    await owner._writes;
    return (await owner._readAccount(accountKey))?['reading']
        as Map<String, dynamic>?;
  }

  @override
  Future<void> write(String accountKey, Map<String, dynamic> value) =>
      owner._write(accountKey, value, reading: true);
}
