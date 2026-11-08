import 'package:bookfin/appearance/preferences.dart';
import 'package:bookfin/catalog/jellyfin.dart';
import 'package:bookfin/main.dart';
import 'package:bookfin/playback/store.dart';
import 'package:bookfin/sync/coordinator.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../appearance/preferences_test.dart' show MemoryAppearanceStore;
import '../foundation_test.dart' show disconnectedCatalog;
import '../playback/playback_test.dart' show account;

// These tests run in fake time, so the coordinator reads the fake clock. Each
// test disposes the coordinator, because a live timer fails a widget test.
void main() {
  /// Signs in and lets the sync that signing in starts finish, then counts
  /// from zero.
  Future<(RecordSync, CountingRecords)> signIn(WidgetTester tester) async {
    final records = CountingRecords();
    final sync = RecordSync(records: records, now: tester.binding.clock.now)
      ..bind(account());
    await tester.pump();
    records.runs = 0;
    return (sync, records);
  }

  testWidgets('signing in syncs records at once', (tester) async {
    final records = CountingRecords();
    final sync = RecordSync(records: records, now: tester.binding.clock.now)
      ..bind(account());
    await tester.pump();
    expect(records.runs, 1);
    await tester.pump(const Duration(seconds: 30));
    expect(records.runs, 2);
    sync.dispose();
  });

  testWidgets(
    'signing in while the app is in the background syncs as soon as it returns',
    (tester) async {
      final (sync, records) = await signIn(tester);
      sync.suspend();
      sync.bind(account(user: 'bob'));
      await tester.pump(const Duration(seconds: 5));
      expect(records.runs, 0);
      sync.resume();
      await tester.pump();
      expect(records.runs, 1);
      sync.dispose();
    },
  );

  testWidgets('records sync every 30 seconds while the app is in front', (
    tester,
  ) async {
    final (sync, records) = await signIn(tester);
    await tester.pump(const Duration(seconds: 30));
    expect(records.runs, 1);
    await tester.pump(const Duration(seconds: 30));
    expect(records.runs, 2);
    sync.dispose();
  });

  testWidgets('records do not sync while the app is in the background', (
    tester,
  ) async {
    final (sync, records) = await signIn(tester);
    await tester.pump(const Duration(seconds: 30));
    sync.suspend();
    await tester.pump(const Duration(minutes: 5));
    expect(records.runs, 1);
    sync.dispose();
  });

  testWidgets(
    'returning after a sync came due syncs at once and then every 30 seconds',
    (tester) async {
      final (sync, records) = await signIn(tester);
      await tester.pump(const Duration(seconds: 10));
      sync.suspend();
      await tester.pump(const Duration(minutes: 1));
      sync.resume();
      await tester.pump();
      expect(records.runs, 1);
      await tester.pump(const Duration(seconds: 30));
      expect(records.runs, 2);
      sync.dispose();
    },
  );

  testWidgets('returning before a sync came due does not sync at once', (
    tester,
  ) async {
    final (sync, records) = await signIn(tester);
    await tester.pump(const Duration(seconds: 10));
    sync.suspend();
    await tester.pump(const Duration(seconds: 5));
    sync.resume();
    await tester.pump();
    expect(records.runs, 0);
    await tester.pump(const Duration(seconds: 30));
    expect(records.runs, 1);
    sync.dispose();
  });

  testWidgets('a sync just before leaving counts as the latest sync', (
    tester,
  ) async {
    final (sync, records) = await signIn(tester);
    await tester.pump(const Duration(seconds: 25));
    await sync.synchronize();
    sync.suspend();
    await tester.pump(const Duration(seconds: 10));
    sync.resume();
    await tester.pump();
    expect(records.runs, 1);
    sync.dispose();
  });

  testWidgets('returning from a shade over the app keeps the period', (
    tester,
  ) async {
    final (sync, records) = await signIn(tester);
    await tester.pump(const Duration(seconds: 20));
    sync.resume();
    await tester.pump(const Duration(seconds: 10));
    expect(records.runs, 1);
    sync.dispose();
  });

  testWidgets('signing in while the app is in the background waits for it', (
    tester,
  ) async {
    final (sync, records) = await signIn(tester);
    sync.suspend();
    sync.bind(account(user: 'bob'));
    await tester.pump(const Duration(minutes: 1));
    expect(records.runs, 0);
    sync.resume();
    await tester.pump();
    expect(records.runs, 1);
    sync.dispose();
  });

  testWidgets(
    'the app suspends record sync when hidden and resumes it in front',
    (tester) async {
      final sync = LifecycleSync();
      await tester.pumpWidget(
        BookfinApp(
          appearance: AppearanceController(MemoryAppearanceStore()),
          catalog: disconnectedCatalog(),
          sync: sync,
        ),
      );
      void enter(AppLifecycleState state) =>
          tester.binding.handleAppLifecycleStateChanged(state);
      // A shade or a dialog over the app leaves it visible.
      enter(AppLifecycleState.inactive);
      expect(sync.calls, isEmpty);
      enter(AppLifecycleState.hidden);
      enter(AppLifecycleState.paused);
      expect(sync.calls.last, 'suspend');
      enter(AppLifecycleState.hidden);
      enter(AppLifecycleState.inactive);
      expect(sync.calls.last, 'suspend');
      enter(AppLifecycleState.resumed);
      expect(sync.calls.last, 'resume');
      await tester.pumpWidget(const SizedBox());
    },
  );
}

class LifecycleSync extends RecordSync {
  LifecycleSync() : super(records: CountingRecords());
  final calls = <String>[];

  @override
  void suspend() {
    calls.add('suspend');
    super.suspend();
  }

  @override
  void resume() {
    calls.add('resume');
    super.resume();
  }
}

class CountingRecords implements LocalResumeStore {
  int runs = 0;

  @override
  Future<SyncReport> synchronize(
    JellyfinSession session,
    JellyfinClient client,
  ) async {
    runs++;
    return (stale: (listening: false, reading: false), replaced: 0);
  }

  @override
  Future<Map<String, List<Map<String, dynamic>>>> conflicts(
    String account,
  ) async => {};

  /// The app retries kept copies after its first frame. These tests keep
  /// none.
  @override
  Future<void> recoverKept() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
