import 'dart:async';

import 'package:flutter/foundation.dart';

import '../catalog/jellyfin.dart';
import '../playback/playback.dart';
import '../playback/store.dart';
import '../reader/session.dart';

class RecordSync extends ChangeNotifier {
  RecordSync({required this.records, this.playback, this.reader});
  final LocalResumeStore records;
  final Playback? playback;
  final ReaderSession? reader;
  JellyfinSession? _session;
  JellyfinClient? _client;
  Timer? _timer;
  int _generation = 0;
  bool _disposed = false;
  bool _busy = false;
  String? _message;
  Map<String, List<Map<String, dynamic>>> _conflicts = {};
  bool get busy => _busy;
  String? get message => _message;
  Map<String, List<Map<String, dynamic>>> get conflicts =>
      Map.unmodifiable(_conflicts);

  void bind(JellyfinSession? session) {
    if (_session?.scope.key == session?.scope.key &&
        _session?.token == session?.token) {
      return;
    }
    ++_generation;
    _timer?.cancel();
    _client?.close();
    _session = session;
    _busy = false;
    _message = null;
    _conflicts = {};
    _client = session == null
        ? null
        : JellyfinClient(session.scope.server, deviceId: 'bookfin-record-sync');
    if (session != null) {
      _timer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => unawaited(synchronize()),
      );
    }
    _emit();
  }

  Future<void> synchronize() async {
    final session = _session;
    final client = _client;
    if (_disposed || _busy || session == null || client == null) return;
    final generation = _generation;
    _busy = true;
    _message = null;
    _emit();
    try {
      await playback?.flush();
      await reader?.flush();
      await records.synchronize(session, client);
      if (_disposed || generation != _generation) return;
      await playback?.refreshPersonalRecords();
      await reader?.refreshPersonalRecords();
      if (_disposed || generation != _generation) return;
      final conflicts = await records.conflicts(session.scope.key);
      if (_disposed || generation != _generation) return;
      _conflicts = conflicts;
      _message = _conflicts.isEmpty ? 'Personal records are synced.' : 'Choose between saved places or edits. Both versions are kept until you choose.';
    } on Exception {
      if (!_disposed && generation == _generation) {
        _message = 'Personal records remain on this device. Sync needs a connection and the compatible Bookfin Storage plugin on Jellyfin. No other storage is used. Retry after checking the server.';
        try {
          final conflicts = await records.conflicts(session.scope.key);
          if (!_disposed && generation == _generation) _conflicts = conflicts;
        } on Exception {
          if (!_disposed && generation == _generation) _message = 'Personal records could not be read. Existing records were kept. Restart before syncing again.';
        }
      }
    } finally {
      if (!_disposed && generation == _generation) {
        _busy = false;
        _emit();
      }
    }
  }

  Future<void> resolve(String record, String identity) async {
    final session = _session;
    if (session == null || _busy) return;
    final generation = _generation;
    _busy = true;
    _emit();
    var resolved = false;
    try {
      await playback?.flush();
      await reader?.flush();
      final accepted = await records.resolve(
        session.scope.key,
        record,
        identity,
      );
      if (_disposed || generation != _generation) return;
      await playback?.refreshPersonalRecords();
      await reader?.refreshPersonalRecords();
      if (_disposed || generation != _generation) return;
      if (!accepted) {
        final conflicts = await records.conflicts(session.scope.key);
        if (_disposed || generation != _generation) return;
        _conflicts = conflicts;
        _message = 'This saved choice changed before it was selected. Review the current saved versions and choose again.';
        return;
      }
      resolved = true;
    } on Exception {
      if (!_disposed && generation == _generation) _message = 'The choice was not saved. Both versions were kept. Retry after checking device storage.';
    } finally {
      if (!_disposed && generation == _generation) {
        _busy = false;
        _emit();
      }
    }
    if (resolved && !_disposed && generation == _generation) {
      await synchronize();
    }
  }

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _timer?.cancel();
    _client?.close();
    super.dispose();
  }
}
