import 'dart:convert';
import 'dart:io';

import 'package:bookfin/catalog/shelf.dart';
import 'package:bookfin/foundation/theme.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:bookfin/playback/store.dart';
import 'package:bookfin/sync/coordinator.dart';
import 'package:bookfin/sync/journal.dart';
import 'package:bookfin/sync/screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../playback/incremental_save_test.dart' show bookmark;
import '../playback/playback_test.dart' show LocalFiles, TestEngine, title;
import 'fixture.dart';

/// Fails only the read that Playback uses to refresh. Sync and the tracking
/// of domains that need a refresh use the real store.
class _UnreadableStore extends LocalResumeStore {
  bool failRead = false;

  @override
  Future<Map<String, dynamic>?> read(String accountKey) async {
    if (failRead) throw Exception('The listening records cannot be read.');
    return super.read(accountKey);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  late SyncFixture server;
  late _UnreadableStore records;
  late LocalFiles downloads;
  late Playback playback;
  late RecordSync sync;
  late DateTime clock;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    server = await SyncFixture.open();
    records = _UnreadableStore();
    downloads = LocalFiles();
    playback = Playback(
      downloads: downloads,
      engine: TestEngine(),
      store: records,
    );
    await playback.bind(server.session, [title]);
    clock = DateTime(2026, 11, 7, 16, 29);
    sync = RecordSync(records: records, now: () => clock)
      ..suspend()
      ..bind(server.session);
    await sync.synchronize();
  });

  tearDown(() async {
    sync.dispose();
    records.failRead = false;
    await playback.close();
    downloads.dispose();
    await server.close();
  });

  Future<void> failRefresh() async {
    final remote = RecordJournal(server.session.scope.key, 'remote');
    remote.change(
      jsonEncode(['audio', 'bookmarks', 'remote-mark']),
      bookmark('remote-mark', title: 'From another device'),
    );
    server.publish(remote);
    records.failRead = true;
    clock = DateTime(2026, 11, 7, 16, 30);
    await sync.synchronize();
  }

  test('the next sync refreshes the real stale listening domain and clears its failure', () async {
    await failRefresh();
    expect(sync.lastSyncNotifier.value?.failure, isNotNull);
    expect(
      (
        listening: records.staleNotifier(server.session.scope.key).value,
        reading: records.reading.staleNotifier(server.session.scope.key).value,
      ),
      (listening: true, reading: false),
    );
    expect(playback.bookmarks, isEmpty);
    records.failRead = false;
    await sync.synchronize();
    expect(playback.bookmarks.single.title, 'From another device');
    expect(
      (
        listening: records.staleNotifier(server.session.scope.key).value,
        reading: records.reading.staleNotifier(server.session.scope.key).value,
      ),
      (listening: false, reading: false),
    );
    expect(sync.lastSyncNotifier.value?.failure, isNull);
  });

  Future<void> showFailedRefresh(WidgetTester tester) async {
    await tester.runAsync(failRefresh);
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: bookfinTheme(Brightness.light),
        home: RecordSyncPage(
          sync: sync,
          library: ValueNotifier(CatalogLibrary.build([title])),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'a failed refresh offers the next sync instead of restart advice',
    (tester) async {
      await showFailedRefresh(tester);
      expect(find.text('Synced records could not be shown'), findsOneWidget);
      expect(
        find.text(
          'The sync finished. Bookfin shows the new records after the next sync.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Restart Bookfin'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a failed refresh still shows the successful exchange in the status strip',
    (tester) async {
      await showFailedRefresh(tester);
      expect(find.text('Not syncing'), findsNothing);
      expect(find.text('Synced'), findsOneWidget);
      expect(find.textContaining('Jellyfin'), findsWidgets);
      expect(find.byTooltip('Sync now'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
