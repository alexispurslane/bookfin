import 'dart:io';

import 'package:bookfin/catalog/jellyfin.dart';
import 'package:bookfin/playback/store.dart';
import 'package:bookfin/sync/coordinator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixture.dart';

// The cause of a failed sync, through the real Jellyfin client and a
// Jellyfin server on this machine.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  late SyncFixture fixture;
  late RecordSync sync;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    fixture = await SyncFixture.open();
    sync = RecordSync(records: LocalResumeStore());
  });
  tearDown(() async {
    sync.dispose();
    await fixture.close();
  });

  test(
    'Jellyfin without the storage plugin answers that its routes are not found',
    () async {
      fixture.pluginMissing = true;
      await expectLater(
        fixture.client.personalRecordChanges(fixture.session, 0),
        throwsA(
          isA<CatalogFailure>()
              .having(
                (failure) => failure.kind,
                'kind',
                CatalogFailureKind.unavailable,
              )
              .having((failure) => failure.status, 'status', 404),
        ),
      );
    },
  );

  test('a sync against Jellyfin without the storage plugin reports the plugin missing', () async {
    fixture.pluginMissing = true;
    sync.bind(fixture.session);
    await sync.syncNow();
    expect(
      sync.lastSyncNotifier.value?.failure,
      RecordSyncFailure.pluginMissing,
    );
  });

  test(
    'a sync while Jellyfin cannot be reached reports no connection',
    () async {
      await fixture.close();
      sync.bind(fixture.session);
      await sync.syncNow();
      expect(
        sync.lastSyncNotifier.value?.failure,
        RecordSyncFailure.unreachable,
      );
    },
  );

  test(
    'a sync that loses Jellyfin between pages reports no connection',
    () async {
      fixture.failDiscoveryAfter = 0;
      sync.bind(fixture.session);
      await sync.syncNow();
      expect(
        sync.lastSyncNotifier.value?.failure,
        RecordSyncFailure.unreachable,
      );
    },
  );
}
