import 'dart:async';

import 'package:bookfin/catalog/jellyfin.dart';
import 'package:bookfin/playback/store.dart';
import 'package:bookfin/sync/coordinator.dart';
import 'package:bookfin/sync/transport.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback/playback_test.dart' show account;
import 'controlled_transport.dart';

// A background sync is one that the app starts: the 30-second period, the
// return to the front, and the sync after sign-in. Sync now and a choice
// between saved versions are started by the user.
void main() {
  late ControlledRecords records;
  late RecordSync sync;
  late DateTime clock;
  late List<RecordSyncStatus> shown;

  setUp(() async {
    records = ControlledRecords();
    clock = DateTime(2026, 11, 7, 16, 29);
    sync = RecordSync(
      records: records,
      transport: records.transport,
      now: () => clock,
    )..bind(account());
    // Signing in syncs at once. These tests start after that sync.
    await pumpEventQueue();
    records.runs = 0;
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
      failure: null,
      synced: DateTime(2026, 11, 7, 16, 30),
      replaced: 0,
    ));
  });

  test(
    'a background sync records how many damaged records took the server copy',
    () async {
      records.replaced = 2;
      await sync.synchronize();
      expect(sync.lastSyncNotifier.value?.replaced, 2);
      expect(shown, isEmpty);
      records.replaced = 0;
      await sync.synchronize();
      expect(sync.lastSyncNotifier.value?.replaced, 0);
    },
  );

  test(
    'a failed background sync is recorded as failed and shows no message',
    () async {
      records.failure = true;
      await sync.synchronize();
      expect(sync.lastSyncNotifier.value?.failure, isNotNull);
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

  test('Sync now shows busy, then how the sync ended', () async {
    records.gate = Completer();
    final running = sync.syncNow();
    expect(sync.busy, isTrue);
    records.gate!.complete();
    await running;
    expect(shown.map((status) => status.busy), [true, false]);
    // The outcome says how the sync ended. A message would repeat it.
    expect(sync.message, isNull);
    expect(sync.lastSyncNotifier.value?.failure, isNull);
  });

  test('a failed Sync now shows busy, then why it failed', () async {
    records.failure = true;
    await sync.syncNow();
    expect(shown.map((status) => status.busy), [true, false]);
    expect(sync.message, isNull);
    expect(sync.lastSyncNotifier.value?.failure, RecordSyncFailure.unreachable);
  });

  group('the cause of a failed sync', () {
    Future<RecordSyncFailure?> failWith(Exception error) async {
      records.error = error;
      await sync.synchronize();
      return sync.lastSyncNotifier.value?.failure;
    }

    test('a sync that cannot reach Jellyfin reports no connection', () async {
      expect(
        await failWith(const CatalogFailure(CatalogFailureKind.unavailable)),
        RecordSyncFailure.unreachable,
      );
    });

    test(
      'a sync whose Jellyfin has no storage plugin reports the plugin missing',
      () async {
        expect(
          await failWith(
            const CatalogFailure(CatalogFailureKind.unavailable, status: 404),
          ),
          RecordSyncFailure.pluginMissing,
        );
      },
    );

    test(
      'a storage answer outside the plugin contract reports an invalid reply',
      () async {
        expect(
          await failWith(
            const RecordProtocolFailure(
              'Invalid personal-record discovery response.',
            ),
          ),
          RecordSyncFailure.invalidResponse,
        );
        expect(
          await failWith(
            const CatalogFailure(CatalogFailureKind.invalidResponse),
          ),
          RecordSyncFailure.invalidResponse,
        );
      },
    );

    test('a sync whose records on this phone cannot be read reports them unreadable', () async {
      records.unreadable = true;
      expect(
        await failWith(const CatalogFailure(CatalogFailureKind.unavailable)),
        RecordSyncFailure.unreadable,
      );
    });

    test(
      'another failure is reported as neither no connection nor plugin missing',
      () async {
        expect(
          await failWith(Exception('Device storage is full.')),
          RecordSyncFailure.other,
        );
      },
    );

    test('a failed sync keeps when records last synced', () async {
      clock = DateTime(2026, 11, 7, 16, 40);
      await sync.synchronize();
      clock = DateTime(2026, 11, 7, 16, 50);
      await failWith(const CatalogFailure(CatalogFailureKind.unavailable));
      expect(sync.lastSyncNotifier.value?.at, DateTime(2026, 11, 7, 16, 50));
      expect(
        sync.lastSyncNotifier.value?.synced,
        DateTime(2026, 11, 7, 16, 40),
      );
    });
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
      expect(sync.message, isNull);
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
    expect(sync.message, isNull);
  });

  test(
    'a later background sync replaces the result of an earlier Sync now',
    () async {
      await sync.syncNow();
      records.failure = true;
      await sync.synchronize();
      expect(sync.message, isNull);
      expect(sync.lastSyncNotifier.value?.failure, isNotNull);
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
class ControlledRecords extends LocalResumeStore {
  @override
  Future<int> unreadableCount(String account) async => 0;
  @override
  Future<bool> hasPendingUploads(String account) async => false;

  late final transport = ControlledTransport(this, synchronize);
  int runs = 0;
  Completer<void>? gate;

  /// What a sync throws, or null when it succeeds.
  Exception? error;

  /// Fails a sync as when Jellyfin cannot be reached.
  set failure(bool value) => error = value
      ? const CatalogFailure(CatalogFailureKind.unavailable)
      : null;

  /// Makes the records unreadable, so [conflicts] throws.
  bool unreadable = false;
  int replaced = 0;
  Map<String, List<Map<String, dynamic>>> found = {};
  final resolved = <String>[];
  final kept = ValueNotifier<KeptRecords>((recovered: 0, kept: false));
  int discards = 0;
  bool discardFails = false;

  @override
  ValueListenable<KeptRecords> get keptNotifier => kept;

  @override
  Future<void> discardKept() async {
    discards++;
    if (discardFails) throw Exception('The disk is busy.');
    kept.value = (recovered: kept.value.recovered, kept: false);
  }

  Future<SyncReport> synchronize(
    JellyfinSession session,
    JellyfinClient client,
  ) async {
    runs++;
    await gate?.future;
    if (error case final error?) throw error;
    return (replaced: replaced);
  }

  @override
  Future<Map<String, List<Map<String, dynamic>>>> conflicts(
    String account,
  ) async => unreadable ? throw Exception('Records cannot be read.') : found;

  @override
  Future<bool> resolve(
    String account,
    String record,
    String identity, {
    Map<String, String> bookmarkTitles = const {},
  }) async {
    if (refuseChoice) return false;
    resolved.add(identity);
    found = {...found}..remove(record);
    return true;
  }

  /// Answers that a choice changed before it was selected.
  bool refuseChoice = false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
