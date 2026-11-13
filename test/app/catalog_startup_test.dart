import 'dart:async';

import 'package:bookfin/appearance/preferences.dart';
import 'package:bookfin/catalog/controller.dart';
import 'package:bookfin/catalog/jellyfin.dart';
import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/catalog/screen.dart';
import 'package:bookfin/catalog/store.dart';
import 'package:bookfin/main.dart';
import 'package:bookfin/playback/store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../appearance/preferences_test.dart' show MemoryAppearanceStore;
import '../catalog/controller_test.dart'
    show MemoryCatalogStore, MemoryCredentials, FixtureClient, account;
import '../catalog/file_store_test.dart' show LegacyPreferences;
import '../catalog/model_test.dart' show entry;

class _Store extends LocalCatalogStore {
  _Store() : super.preferences();
  final saved = MemoryCatalogStore();
  int reads = 0;
  int migrations = 0;
  Completer<void>? migrationGate;
  Exception? migrationError;
  bool recoveredChoices = false;

  @override
  Future<String?> read(AccountScope scope) async {
    reads++;
    return saved.read(scope);
  }

  @override
  Future<void> write(AccountScope scope, String text) =>
      saved.write(scope, text);

  @override
  Future<CatalogChoices> readChoices(AccountScope scope) async =>
      recoveredChoices
      ? CatalogChoices(retainedUnreadable: true)
      : saved.readChoices(scope);

  @override
  Future<void> writeChoices(AccountScope scope, CatalogChoices choices) =>
      saved.writeChoices(scope, choices);

  @override
  Future<void> migrateLegacy() async {
    migrations++;
    await migrationGate?.future;
    recoveredChoices = true;
    if (migrationError case final error?) throw error;
  }
}

/// Keeps real controller behavior while observing ownership and work counts.
class _Catalog extends CatalogController {
  _Catalog(_Store store, MemoryCredentials credentials, FixtureClient client)
    : super(
        credentials: credentials,
        store: store,
        clientFactory: (_, _) => client,
        hop: <M, R>(work, input) async => work(input),
      );
  int restores = 0;
  int refreshes = 0;
  int disposals = 0;
  int reconciliations = 0;
  @override
  Future<void> reconcileChoices() {
    reconciliations++;
    return super.reconcileChoices();
  }

  @override
  Future<void> restore() {
    restores++;
    return super.restore();
  }

  @override
  Future<void> refresh({Set<String>? hidden, bool byUser = false}) {
    refreshes++;
    // An illegal post-disposal call is counted without entering a controller
    // whose pending restore can no longer publish its completion.
    if (disposals != 0) return Future<void>.value();
    return super.refresh(hidden: hidden, byUser: byUser);
  }

  @override
  void dispose() {
    disposals++;
    super.dispose();
  }
}

void main() {
  late _Store store;
  late MemoryCredentials credentials;
  late FixtureClient client;
  _Catalog? catalog;
  const emptySources = (downloads: null, playback: null, covers: null);

  Future<void> start({Future<BookfinSources> Function()? sources}) =>
      runBookfin(
        catalogStore: store,
        recordStore: LocalResumeStore(),
        createCatalog: (given) {
          expect(given, same(store));
          return catalog = _Catalog(store, credentials, client);
        },
        openOtherSources:
            sources ??
            () => openSources(
              restoreAppearance: () async {},
              restoreLayout: () async {},
              openDownloads: () async => null,
              openPlayback: (_) async => null,
              openCovers: () async => null,
            ),
      );

  // All fixtures complete in microtasks. No frame is pumped by this helper.
  Future<void> drain() async {
    for (var i = 0; i < 50; i++) {
      await Future<void>.value();
    }
  }

  setUp(() {
    final previous = SharedPreferencesAsyncPlatform.instance;
    SharedPreferencesAsyncPlatform.instance = LegacyPreferences();
    addTearDown(() => SharedPreferencesAsyncPlatform.instance = previous);
    store = _Store();
    credentials = MemoryCredentials()..value = account('alice');
    client = FixtureClient(credentials.value!.scope.server);
    catalog = null;
    store.saved.values[credentials.value!.scope.key] = CatalogCache(
      scope: credentials.value!.scope,
      libraries: client.views,
      entries: [entry('one')],
    ).encode();
  });

  tearDown(() => client.close());

  testWidgets('local catalog completes while other source opening is held', (
    tester,
  ) async {
    final sources = Completer<BookfinSources>();
    final launching = start(
      sources: () => openSources(
        restoreAppearance: () async {
          await sources.future;
        },
        restoreLayout: () async {},
        openDownloads: () async => null,
        openPlayback: (_) async => null,
        openCovers: () async => null,
      ),
    );
    await drain();
    try {
      expect(catalog?.restores, 1);
      expect(catalog?.books.single.title, 'The Orchard');
      expect(catalog?.busy, isFalse);
      expect(store.reads, 1);
      expect(store.migrations, 0);
      expect(client.validations, 0);
      expect(find.byType(BookfinApp), findsNothing);
    } finally {
      sources.complete(emptySources);
      await launching;
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await drain();
    }
  });

  testWidgets('source opening can finish before local catalog restoration', (
    tester,
  ) async {
    final read = Completer<void>();
    credentials.readGate = read;
    await start();
    await tester.pump();
    expect(find.byType(BookfinApp), findsOneWidget);
    expect(catalog!.busy, isTrue);
    expect(store.migrations, 0);
    expect(client.validations, 0);
    read.complete();
    await drain();
    await tester.pump();
    await tester.pump();
    expect(
      tester.widget<CatalogHome>(find.byType(CatalogHome)).catalog,
      same(catalog),
    );
    expect(catalog!.books.single.title, 'The Orchard');
    expect(catalog!.restores, 1);
    expect(catalog!.refreshes, 1);
    expect(client.validations, 1);
    expect(store.migrations, 1);
    await tester.pumpWidget(const SizedBox());
    expect(catalog!.disposals, 1);
  });
  testWidgets('failed source opening disposes its still-restoring catalog', (
    tester,
  ) async {
    final read = Completer<void>();
    credentials.readGate = read;
    final failure = StateError('source opening failed');
    await expectLater(
      start(sources: () async => throw failure),
      throwsA(same(failure)),
    );
    expect(catalog?.disposals, 1);
    read.complete();
    await drain();
    expect(catalog!.session, isNull);
    expect(store.reads, 0);
    expect(client.validations, 0);
    expect(store.migrations, 0);
    expect(find.byType(BookfinApp), findsNothing);
  });

  testWidgets(
    'disposing the app during restore starts no refresh or migration',
    (tester) async {
      final read = Completer<void>();
      credentials.readGate = read;
      await start();
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      expect(catalog!.disposals, 1);
      read.complete();
      await drain();
      await tester.pump();
      expect(catalog!.refreshes, 0);
      expect(store.migrations, 0);
      expect(catalog!.session, isNull);
    },
  );

  testWidgets(
    'completed restore waits for a frame before migration and never waits for network',
    (tester) async {
      final sources = Completer<BookfinSources>();
      final network = Completer<List<CatalogEntry>>();
      client.pendingCatalog = network;
      final migration = Completer<void>();
      store.migrationGate = migration;
      final launching = start(sources: () => sources.future);
      await drain();
      sources.complete(emptySources);
      await launching;
      await drain();
      expect(store.migrations, 0);
      await tester.pump();
      await drain();
      await tester.pump();
      expect(find.byType(CatalogHome), findsOneWidget);
      expect(find.text('The Orchard'), findsWidgets);
      expect(catalog!.books.single.title, 'The Orchard');
      expect(catalog!.restores, 1);
      expect(catalog!.refreshes, 1);
      expect(client.catalogReads, 1);
      expect(store.migrations, 1);
      migration.complete();
      await drain();
      expect(catalog!.message, contains('kept for recovery'));
      network.complete(client.entries);
      await drain();
      await tester.pump();
      expect(catalog!.message, contains('kept for recovery'));
      expect(catalog!.restores, 1);
      expect(catalog!.refreshes, 1);
      await tester.pumpWidget(const SizedBox());
      expect(catalog!.disposals, 1);
    },
  );

  testWidgets(
    'unreadable local catalog reports recovery without preventing the app',
    (tester) async {
      store.saved.failReads = true;
      credentials.value!.rejectCredential();
      await start();
      await tester.pump();
      await drain();
      await tester.pump();
      expect(find.byType(CatalogHome), findsOneWidget);
      expect(catalog!.message, contains('could not be read'));
      expect(catalog!.session!.scope.userId, 'alice');
      expect(client.validations, 0);
      expect(catalog!.restores, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'an expired sign-in restores its local books without server requests',
    (tester) async {
      credentials.value!.rejectCredential();
      await start();
      await tester.pump();
      await drain();
      await tester.pump();
      expect(catalog!.books.single.title, 'The Orchard');
      expect(catalog!.session!.needsSignIn, isTrue);
      expect(client.validations, 0);
      expect(catalog!.restores, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'supplied controllers remain owned and restored by their caller',
    (tester) async {
      final supplied = _Catalog(store, credentials, client);
      final appearance = AppearanceController(MemoryAppearanceStore());
      await tester.pumpWidget(
        BookfinApp(appearance: appearance, catalog: supplied),
      );
      await tester.pump();
      expect(supplied.restores, 0);
      expect(supplied.refreshes, 0);
      await tester.pumpWidget(const SizedBox());
      expect(supplied.disposals, 0);
      await supplied.restore();
      expect(supplied.books.single.title, 'The Orchard');
      supplied.dispose();
      appearance.dispose();
    },
  );

  testWidgets(
    'failed migration still reconciles recovery notices and reports the failure',
    (tester) async {
      final failure = FormatException('one inactive account failed migration');
      store.migrationError = failure;
      final reported = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = reported.add;
      try {
        await start();
        await tester.pump();
        await drain();
        await tester.pump();
        expect(catalog!.books.single.title, 'The Orchard');
        expect(catalog!.message, contains('kept for recovery'));
        expect(reported.single.exception, same(failure));
        expect(reported.single.library, 'catalog storage');
        expect(store.migrations, 1);
        expect(catalog!.reconciliations, 1);
      } finally {
        await tester.pumpWidget(const SizedBox());
        FlutterError.onError = previous;
      }
    },
  );

  testWidgets(
    'disposing during migration leaves its completion detached from the catalog',
    (tester) async {
      final migration = Completer<void>();
      store.migrationGate = migration;
      await start();
      await tester.pump();
      await drain();
      await tester.pump();
      expect(store.migrations, 1);
      await tester.pumpWidget(const SizedBox());
      migration.complete();
      await drain();
      expect(catalog!.disposals, 1);
      expect(catalog!.reconciliations, 0);
    },
  );

  testWidgets(
    'failed source opening also disposes a catalog already restored',
    (tester) async {
      final sources = Completer<BookfinSources>();
      final failure = StateError('source opening failed after restoration');
      final launching = start(sources: () => sources.future);
      final failed = expectLater(launching, throwsA(same(failure)));
      await drain();
      expect(catalog!.books.single.title, 'The Orchard');
      sources.completeError(failure);
      await failed;
      expect(catalog!.disposals, 1);
      expect(catalog!.refreshes, 0);
      expect(store.migrations, 0);
    },
  );
}
