import 'dart:async';

import 'package:bookfin/catalog/jellyfin.dart';
import 'package:bookfin/playback/store.dart';
import 'package:bookfin/sync/coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback/playback_test.dart' show account;

// A background sync is one that the app starts: the 30-second period, the
// return to the front, and the sync after sign-in. Sync now and a choice
// between saved versions are started by the user.
void main() {
  late ControlledRecords records;
  late RecordSync sync;
  late DateTime clock;
  late List<RecordSyncStatus> shown;

  setUp(() {
    records = ControlledRecords();
    clock = DateTime(2026, 11, 7, 16, 29);
    sync = RecordSync(records: records, now: () => clock)..bind(account());
    shown = [];
    sync.statusNotifier.addListener(() => shown.add(sync.statusNotifier.value));
  });
  tearDown(() => sync.dispose());

  test('a background sync shows no busy state and no message', () async {
    records.gate = Completer();
    final running = sync.synchronize();
    await pumpEventQueue();
    expect(sync.busy, isFalse);
    records.gate!.complete();
    await running;
    expect(records.runs, 1);
    expect(shown, isEmpty);
    expect(sync.message, isNull);
  });

  test('a background sync records when it finished', () async {
    records.gate = Completer();
    final running = sync.synchronize();
    clock = DateTime(2026, 11, 7, 16, 30);
    records.gate!.complete();
    await running;
    expect(sync.lastSyncNotifier.value, (
      at: DateTime(2026, 11, 7, 16, 30),
      failed: false,
    ));
  });

  test(
    'a failed background sync is recorded as failed and shows no message',
    () async {
      records.failure = true;
      await sync.synchronize();
      expect(sync.lastSyncNotifier.value?.failed, isTrue);
      expect(shown, isEmpty);
      expect(sync.message, isNull);
    },
  );

  test('a background sync publishes the conflicts it finds', () async {
    records.found = {
      '["audio","resumes","x"]': [
        {'value': null},
      ],
    };
    await sync.synchronize();
    expect(sync.conflictsNotifier.value.keys, ['["audio","resumes","x"]']);
  });

  test('Sync now shows busy, then the result', () async {
    records.gate = Completer();
    final running = sync.syncNow();
    expect(sync.busy, isTrue);
    records.gate!.complete();
    await running;
    expect(shown.map((status) => status.busy), [true, false]);
    expect(sync.message, 'Personal records are synced.');
    expect(sync.lastSyncNotifier.value?.failed, isFalse);
  });

  test('a failed Sync now shows busy, then why it failed', () async {
    records.failure = true;
    await sync.syncNow();
    expect(shown.map((status) => status.busy), [true, false]);
    expect(sync.message, contains('Personal records remain on this device'));
    expect(sync.lastSyncNotifier.value?.failed, isTrue);
  });

  test(
    'Sync now during a background sync waits for it, then syncs again',
    () async {
      records.gate = Completer();
      final background = sync.synchronize();
      await pumpEventQueue();
      final requested = sync.syncNow();
      expect(sync.busy, isTrue);
      records.gate!.complete();
      records.gate = null;
      await Future.wait([background, requested]);
      expect(records.runs, 2);
      expect(sync.busy, isFalse);
      expect(sync.message, 'Personal records are synced.');
    },
  );

  test(
    'a choice made during a background sync waits for it and is kept',
    () async {
      records.gate = Completer();
      final background = sync.synchronize();
      await pumpEventQueue();
      final choice = sync.resolve('["audio","resumes","x"]', 'chosen');
      expect(sync.busy, isTrue);
      expect(records.resolved, isEmpty);
      records.gate!.complete();
      records.gate = null;
      await Future.wait([background, choice]);
      expect(records.resolved, ['chosen']);
      expect(records.runs, 2);
      expect(sync.busy, isFalse);
    },
  );

  test('a choice stays busy until the sync after it finishes', () async {
    records.gate = Completer();
    final choice = sync.resolve('["audio","resumes","x"]', 'chosen');
    await pumpEventQueue();
    expect(records.resolved, ['chosen']);
    expect(sync.busy, isTrue);
    records.gate!.complete();
    await choice;
    expect(shown.map((status) => status.busy), [true, false]);
    expect(sync.message, 'Personal records are synced.');
  });

  test(
    'a later background sync replaces the result of an earlier Sync now',
    () async {
      await sync.syncNow();
      records.failure = true;
      await sync.synchronize();
      expect(sync.message, isNull);
      expect(sync.lastSyncNotifier.value?.failed, isTrue);
    },
  );

  test(
    'signing in to another account forgets the last sync and its result',
    () async {
      records.found = {
        '["audio","resumes","x"]': [
          {'value': null},
        ],
      };
      await sync.syncNow();
      sync.bind(account(user: 'bob'));
      expect(sync.lastSyncNotifier.value, isNull);
      expect(sync.message, isNull);
      expect(sync.conflictsNotifier.value, isEmpty);
      sync.checkInvariants();
    },
  );

  test('signing out leaves no sync state', () async {
    await sync.syncNow();
    sync.bind(null);
    sync.checkInvariants();
    expect(sync.lastSyncNotifier.value, isNull);
  });
}

/// Personal records whose sync can wait on [gate], fail, and find [found].
class ControlledRecords implements LocalResumeStore {
  int runs = 0;
  Completer<void>? gate;
  bool failure = false;
  Map<String, List<Map<String, dynamic>>> found = {};
  final resolved = <String>[];

  @override
  Future<void> synchronize(
    JellyfinSession session,
    JellyfinClient client,
  ) async {
    runs++;
    await gate?.future;
    if (failure) throw Exception('Jellyfin cannot be reached.');
  }

  @override
  Future<Map<String, List<Map<String, dynamic>>>> conflicts(
    String account,
  ) async => found;

  @override
  Future<bool> resolve(String account, String record, String identity) async {
    resolved.add(identity);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
