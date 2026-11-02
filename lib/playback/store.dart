import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'playback.dart';

class LocalResumeStore implements ResumeStore {
  String _key(String accountKey) => 'bookfin.playback.v1.$accountKey';
  @override
  Future<Map<String, dynamic>?> read(String accountKey) async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_key(accountKey));
    return raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
  }

  @override
  Future<void> write(String accountKey, Map<String, dynamic> value) async {
    final preferences = await SharedPreferences.getInstance();
    if (!await preferences.setString(_key(accountKey), jsonEncode(value))) {
      throw StateError('Listening position was not saved.');
    }
  }
}
