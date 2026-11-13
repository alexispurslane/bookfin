import 'dart:convert';

import 'package:bookfin/catalog/jellyfin.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:bookfin/playback/store.dart';
import 'package:bookfin/reader/session.dart';
import 'package:bookfin/sync/coordinator.dart';
import 'package:bookfin/sync/journal.dart';
import 'package:bookfin/sync/transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../playback/incremental_save_test.dart' show bookmark;
import '../playback/playback_test.dart'
    show LocalFiles, MemoryResume, TestEngine, account, recording, title;
import 'controlled_transport.dart';
import 'stale_domains_test.dart' show readingBookmark;

/// Counts the refreshes that record sync asks Playback for. While
/// [refreshFailure] is set, each refresh fails with it.
class _Playback extends Playback {
  _Playback(LocalFiles downloads)
    : super(downloads: downloads, engine: TestEngine(), store: MemoryResume());
  int refreshes = 0;
  Exception? refreshFailure;
  @override
  Future<void> flush() async {}
  @override
  Future<void> refreshPersonalRecords() async {
    refreshes++;
    if (refreshFailure case final failure?) throw failure;
  }
}

/// Counts the refreshes that record sync asks the reader for. While
/// [refreshFailure] is set, each refresh fails with it.
class _Reader extends ReaderSession {
  _Reader(LocalFiles downloads)
    : super(
        downloads: downloads,
        store: MemoryResume(),
        load: (_) => throw UnimplementedError(),
      );
  int refreshes = 0;
  Exception? refreshFailure;
  @override
  Future<void> flush() async {}
  @override
  Future<void> refreshPersonalRecords() async {
    refreshes++;
    if (refreshFailure case final failure?) throw failure;
  }
}

/// Personal records whose next sync reports [stale] and finds [found], and
/// which save every choice between saved versions.
class _Records extends LocalResumeStore {
  late final transport = ControlledTransport(this, synchronize);
  late final remote = RecordJournal(account().scope.key, 'remote');
  Future<void> changed = Future.value();
  ({bool listening, bool reading}) get stale => (
    listening: staleNotifier(account().scope.key).value,
    reading: reading.staleNotifier(account().scope.key).value,
  );
  set stale(({bool listening, bool reading}) value) {
    changed = changed.then((_) async {
      for (final reading in [false, true]) {
        final behind = reading ? value.reading : value.listening;
        if (behind) {
          final id = 'mark-${remote.uploads.length}';
          remote.change(
            jsonEncode([reading ? 'reading' : 'audio', 'bookmarks', id]),
            reading ? readingBookmark(id) : bookmark(id),
          );
        }
      }
      await receivePage(
        account().scope.key,
        remote.uploads,
        remote.uploads.length,
      );
      if (!value.listening) {
        acceptSnapshot(account().scope.key, await read(account().scope.key));
      }
      if (!value.reading) {
        reading.acceptSnapshot(
          account().scope.key,
          await reading.read(account().scope.key),
        );
      }
    });
  }

  int replaced = 0;
  Map<String, List<Map<String, dynamic>>> found = {};
  int syncs = 0;

  /// The identity of each version that a choice saved.
  final chosen = <String>[];
  Future<SyncReport> synchronize(
    JellyfinSession session,
    JellyfinClient client,
  ) async {
    syncs++;
    await changed;
    return (replaced: replaced);
  }

  @override
  Future<bool> resolve(
    String account,
    String record,
    String identity, {
    Map<String, String> bookmarkTitles = const {},
  }) async {
    await changed;
    chosen.add(identity);
    stale = (listening: true, reading: stale.reading);
    await changed;
    return true;
  }

  @override
  Future<Map<String, List<Map<String, dynamic>>>> conflicts(
    String account,
  ) async => {
    for (final entry in found.entries) entry.key: [...entry.value],
  };

  /// Whether the next retry of kept copies fails.
  bool recoveryFails = false;

  @override
  Future<void> recoverKept() async {
    if (recoveryFails) throw Exception('The kept copies cannot be read.');
    await changed;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late LocalFiles downloads;
  late _Playback playback;
  late _Reader reader;
  late _Records records;
  late RecordSync sync;
  late DateTime clock;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    downloads = LocalFiles();
    playback = _Playback(downloads);
    reader = _Reader(downloads);
    records = _Records();
    records.registerWriter(
      account: () => account().scope.key,
      flush: playback.flush,
      refresh: () async {
        await playback.refreshPersonalRecords();
        records.acceptSnapshot(
          account().scope.key,
          await records.read(account().scope.key),
        );
      },
    );
    records.reading.registerWriter(
      account: () => account().scope.key,
      flush: reader.flush,
      refresh: () async {
        await reader.refreshPersonalRecords();
        records.reading.acceptSnapshot(
          account().scope.key,
          await records.reading.read(account().scope.key),
        );
      },
    );
    clock = DateTime(2026, 11, 7, 16, 29);
    sync = RecordSync(
      records: records,
      transport: records.transport,
      now: () => clock,
    )..bind(account());
    // Signing in syncs at once. These tests start after that sync.
    await sync.synchronize();
    await pumpEventQueue();
    playback.refreshes = 0;
    reader.refreshes = 0;
    records.syncs = 0;
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

  test(
    'listening records that came back from kept copies refresh only Playback',
    () async {
      records.stale = (listening: true, reading: false);
      await sync.recoverKept();
      expect(playback.refreshes, 1);
      expect(reader.refreshes, 0);
    },
  );

  test(
    'reading records that came back from kept copies refresh only the reader',
    () async {
      records.stale = (listening: false, reading: true);
      await sync.recoverKept();
      expect(playback.refreshes, 0);
      expect(reader.refreshes, 1);
    },
  );

  test(
    'a retry of kept copies that fails reports nothing and refreshes nothing',
    () async {
      records
        ..stale = (listening: true, reading: true)
        ..recoveryFails = true;
      await sync.recoverKept();
      expect(playback.refreshes, 0);
      expect(reader.refreshes, 0);
      expect(sync.message, isNull);
      expect(sync.lastSyncNotifier.value?.failure, isNull);
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

  group('a refresh that fails after a sync', () {
    test('does not stop the refresh of the other domain', () async {
      records.stale = (listening: true, reading: true);
      playback.refreshFailure = Exception('The listening records failed.');
      await sync.synchronize();
      expect(reader.refreshes, 1);

      playback.refreshFailure = null;
      reader.refreshFailure = Exception('The reading records failed.');
      playback.refreshes = 0;
      await sync.synchronize();
      expect(playback.refreshes, 1);
    });

    test('reports a refresh failure after the exchange succeeded', () async {
      records.stale = (listening: false, reading: true);
      reader.refreshFailure = Exception('The reading records failed.');
      await sync.synchronize();

      expect(
        sync.lastSyncNotifier.value?.failure,
        RecordSyncFailure.refreshFailed,
      );
    });

    test('does not report the storage plugin missing when a saved record cannot be decoded', () async {
      records.stale = (listening: true, reading: false);
      playback.refreshFailure = const FormatException('A bad saved record.');
      await sync.synchronize();

      expect(
        sync.lastSyncNotifier.value?.failure,
        RecordSyncFailure.refreshFailed,
      );
    });

    test(
      'advances the last successful sync time despite the failed refresh',
      () async {
        records.stale = (listening: true, reading: false);
        playback.refreshFailure = Exception('The listening records failed.');
        clock = DateTime(2026, 11, 7, 16, 30);
        await sync.synchronize();

        expect(
          sync.lastSyncNotifier.value?.synced,
          DateTime(2026, 11, 7, 16, 30),
        );
      },
    );

    test(
      'keeps the number of records that the sync restored from Jellyfin',
      () async {
        records
          ..stale = (listening: true, reading: false)
          ..replaced = 2;
        playback.refreshFailure = Exception('The listening records failed.');
        await sync.synchronize();

        expect(sync.lastSyncNotifier.value?.replaced, 2);
      },
    );

    test('still shows the choices that the sync found', () async {
      records
        ..stale = (listening: true, reading: false)
        ..found = {
          '["audio","resumes","x"]': [
            {'value': null},
          ],
        };
      playback.refreshFailure = Exception('The listening records failed.');
      await sync.synchronize();

      expect(sync.conflicts.keys, ['["audio","resumes","x"]']);
    });
  });

  group('a refresh that fails after a choice that was saved', () {
    setUp(() {
      records.stale = (listening: true, reading: true);
      playback.refreshFailure = Exception('The listening records failed.');
    });

    test('does not say that the choice was not saved', () async {
      await sync.resolve('["audio","resumes","x"]', 'chosen');

      expect(records.chosen, ['chosen']);
      expect(sync.message, isNull);
    });

    test('does not stop the refresh of the other domain', () async {
      await sync.resolve('["audio","resumes","x"]', 'chosen');

      expect(reader.refreshes, 1);
    });

    test('does not stop the sync that sends the choice', () async {
      await sync.resolve('["audio","resumes","x"]', 'chosen');

      expect(records.syncs, 1);
    });
  });

  test('a refresh that fails after a retry of kept copies does not stop the refresh of the other domain', () async {
    records.stale = (listening: true, reading: true);
    playback.refreshFailure = Exception('The listening records failed.');
    await sync.recoverKept();

    expect(reader.refreshes, 1);
  });

  group(
    'a listening refresh that cannot read the store, while audio plays',
    () {
      late TestEngine engine;
      late MemoryResume store;
      late Playback playing;
      late RecordSync sync;

      setUp(() async {
        engine = TestEngine();
        store = MemoryResume();
        playing = Playback(downloads: downloads, engine: engine, store: store);
        await playing.bind(account(), [title]);
        await playing.open(title, recording);
        records.registerWriter(
          account: () => account().scope.key,
          flush: playing.flush,
          refresh: playing.refreshPersonalRecords,
        );
        sync = RecordSync(records: records, transport: records.transport)
          ..bind(account());
        // Signing in syncs at once. These tests start after that sync.
        await pumpEventQueue();
        records.stale = (listening: true, reading: false);
        store.failRead = true;
      });
      tearDown(() async {
        sync.dispose();
        await playing.close();
      });

      test(
        'reports a background refresh failure after the exchange succeeded',
        () async {
          await sync.synchronize();

          expect(
            sync.lastSyncNotifier.value?.failure,
            RecordSyncFailure.refreshFailed,
          );
        },
      );

      test('leaves the audio playing through a background sync', () async {
        await sync.synchronize();

        expect(engine.isPlaying, isTrue);
        expect(playing.playing, isTrue);
        expect(playing.message, isNull);
      });

      test('reports nothing after a retry of kept copies', () async {
        await sync.recoverKept();

        expect(sync.message, isNull);
        expect(sync.lastSyncNotifier.value?.failure, isNull);
      });

      test('leaves the audio playing after a retry of kept copies', () async {
        await sync.recoverKept();

        expect(engine.isPlaying, isTrue);
        expect(playing.playing, isTrue);
        expect(playing.message, isNull);
      });
    },
  );
}
