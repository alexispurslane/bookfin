import 'package:bookfin/catalog/jellyfin.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:bookfin/playback/store.dart';
import 'package:bookfin/reader/session.dart';
import 'package:bookfin/sync/coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback/playback_test.dart'
    show LocalFiles, MemoryResume, TestEngine, account;

/// Counts the refreshes that record sync asks Playback for.
class _Playback extends Playback {
  _Playback(LocalFiles downloads)
    : super(downloads: downloads, engine: TestEngine(), store: MemoryResume());
  int refreshes = 0;
  @override
  Future<void> flush() async {}
  @override
  Future<void> refreshPersonalRecords() async => refreshes++;
}

/// Counts the refreshes that record sync asks the reader for.
class _Reader extends ReaderSession {
  _Reader(LocalFiles downloads)
    : super(
        downloads: downloads,
        store: MemoryResume(),
        load: (_) => throw UnimplementedError(),
      );
  int refreshes = 0;
  @override
  Future<void> flush() async {}
  @override
  Future<void> refreshPersonalRecords() async => refreshes++;
}

/// Personal records whose next sync reports [stale] and finds [found].
class _Records implements LocalResumeStore {
  StaleDomains stale = (listening: false, reading: false);
  Map<String, List<Map<String, dynamic>>> found = {};
  @override
  Future<StaleDomains> synchronize(
    JellyfinSession session,
    JellyfinClient client,
  ) async => stale;

  @override
  Future<Map<String, List<Map<String, dynamic>>>> conflicts(
    String account,
  ) async => {
    for (final entry in found.entries) entry.key: [...entry.value],
  };

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late LocalFiles downloads;
  late _Playback playback;
  late _Reader reader;
  late _Records records;
  late RecordSync sync;

  setUp(() async {
    downloads = LocalFiles();
    playback = _Playback(downloads);
    reader = _Reader(downloads);
    records = _Records();
    sync = RecordSync(records: records, playback: playback, reader: reader)
      ..bind(account());
    // Signing in syncs at once. These tests start after that sync.
    await pumpEventQueue();
    playback.refreshes = 0;
    reader.refreshes = 0;
  });
  tearDown(() async {
    sync.dispose();
    await playback.close();
    reader.dispose();
    downloads.dispose();
  });

  test('a background sync that brings nothing new refreshes neither Playback nor the reader', () async {
    await sync.synchronize();
    await sync.syncNow();
    expect(playback.refreshes, 0);
    expect(reader.refreshes, 0);
  });

  test(
    'a sync that brings new listening records refreshes only Playback',
    () async {
      records.stale = (listening: true, reading: false);
      await sync.synchronize();
      expect(playback.refreshes, 1);
      expect(reader.refreshes, 0);
    },
  );

  test(
    'a sync that brings new reading records refreshes only the reader',
    () async {
      records.stale = (listening: false, reading: true);
      await sync.synchronize();
      expect(playback.refreshes, 0);
      expect(reader.refreshes, 1);
    },
  );

  test('a sync that finds the same saved versions again does not notify the list of choices', () async {
    records.found = {
      '["audio","resumes","x"]': [
        {'value': null},
      ],
    };
    await sync.synchronize();
    var notified = 0;
    sync.conflictsNotifier.addListener(() => notified++);
    await sync.synchronize();
    await sync.syncNow();
    expect(notified, 0);
    records.found = {};
    await sync.synchronize();
    expect(notified, 1);
    expect(sync.conflicts, isEmpty);
  });
}
