import 'dart:async';

import 'package:bookfin/appearance/preferences.dart';
import 'package:bookfin/catalog/controller.dart';
import 'package:bookfin/catalog/jellyfin.dart';
import 'package:bookfin/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../appearance/preferences_test.dart' show MemoryAppearanceStore;
import '../catalog/controller_test.dart'
    show FixtureClient, MemoryCatalogStore, MemoryCredentials;

const _offline = 'Cannot reach Jellyfin. Showing downloaded books.';

/// A Jellyfin client that counts the refreshes that reach it. It can hold
/// a refresh open until [pendingValidate] completes, and a sign-in open,
/// after Jellyfin accepted it, until [pendingLibraries] completes.
class _CountingClient extends FixtureClient {
  _CountingClient() : super(Uri.parse('https://books.example'));
  int refreshes = 0;
  Completer<void>? pendingValidate;
  Completer<void>? pendingLibraries;
  @override
  Future<JellyfinSession> validate(JellyfinSession session) async {
    refreshes++;
    await pendingValidate?.future;
    return super.validate(session);
  }

  @override
  Future<List<BookLibrary>> libraries(JellyfinSession session) async {
    await pendingLibraries?.future;
    return super.libraries(session);
  }
}

void main() {
  late _CountingClient client;
  late MemoryCredentials credentials;
  late MemoryCatalogStore store;
  late CatalogController catalog;

  CatalogController newCatalog() => CatalogController(
    credentials: credentials,
    store: store,
    clientFactory: (_, _) => client,
  );

  setUp(() {
    client = _CountingClient();
    credentials = MemoryCredentials();
    store = MemoryCatalogStore();
    catalog = newCatalog();
  });
  tearDown(() {
    catalog.dispose();
    client.close();
  });

  Future<void> signIn() async {
    await catalog.connect('https://books.example', 'alice', 'password');
    await catalog.refresh(selected: {'books'});
    client.refreshes = 0;
  }

  Future<void> show(WidgetTester tester) async {
    final appearance = AppearanceController(MemoryAppearanceStore());
    addTearDown(appearance.dispose);
    await tester.pumpWidget(
      BookfinApp(appearance: appearance, catalog: catalog),
    );
    await tester.pumpAndSettle();
  }

  /// The phone sends the app away and brings it back, through every state
  /// between, as Android reports them.
  void hideAndReturn(WidgetTester tester) {
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
  }

  group('the catalog on return to the screen', () {
    testWidgets('a return after the app was hidden refreshes it once', (
      tester,
    ) async {
      await signIn();
      await show(tester);
      hideAndReturn(tester);
      await tester.pumpAndSettle();
      expect(client.refreshes, 1);
      expect(catalog.statusNotifier.value.message, isNull);
    });

    testWidgets('a return from inactive only does not refresh it', (
      tester,
    ) async {
      await signIn();
      await show(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(client.refreshes, 0);
    });

    testWidgets('a second return without hiding again does not refresh it', (
      tester,
    ) async {
      await signIn();
      await show(tester);
      hideAndReturn(tester);
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(client.refreshes, 1);
    });

    testWidgets('a return while a refresh runs starts no other', (
      tester,
    ) async {
      await signIn();
      await show(tester);
      client.pendingValidate = Completer();
      final asked = catalog.refresh(byUser: true);
      await tester.pump();
      hideAndReturn(tester);
      await tester.pump();
      client.pendingValidate!.complete();
      await asked;
      await tester.pumpAndSettle();
      expect(client.refreshes, 1);
      expect(catalog.statusNotifier.value.verified, isTrue);
    });

    testWidgets('a return while a sign-in runs starts no refresh', (
      tester,
    ) async {
      await signIn();
      await show(tester);
      client.pendingLibraries = Completer();
      final signingIn = catalog.connect(
        'https://books.example',
        'bob',
        'password',
      );
      await tester.pump();
      expect(catalog.session?.username, 'bob');
      hideAndReturn(tester);
      await tester.pump();
      client.pendingLibraries!.complete();
      await signingIn;
      await tester.pumpAndSettle();
      expect(client.refreshes, 0);
      expect(catalog.statusNotifier.value.verified, isTrue);
    });

    testWidgets(
      'a return while the saved library loads starts no refresh and keeps it',
      (tester) async {
        await signIn();
        catalog.dispose();
        final gate = store.readGate = Completer<void>();
        catalog = newCatalog();
        final restoring = catalog.restore();
        await show(tester);
        expect(catalog.session, isNotNull);
        hideAndReturn(tester);
        await tester.pump();
        gate.complete();
        await restoring;
        await tester.pumpAndSettle();
        expect(client.refreshes, 0);
        expect(catalog.books, hasLength(1));
      },
    );

    testWidgets('a signed-out app asks Jellyfin nothing on return', (
      tester,
    ) async {
      await show(tester);
      hideAndReturn(tester);
      await tester.pumpAndSettle();
      expect(client.refreshes, 0);
      expect(catalog.session, isNull);
    });

    testWidgets(
      'a return that reaches Jellyfin brings back the full library after it was offline',
      (tester) async {
        await signIn();
        client.failure = const CatalogFailure(CatalogFailureKind.unavailable);
        await catalog.refresh();
        await show(tester);
        expect(find.text(_offline), findsOneWidget);
        expect(find.text('The Orchard'), findsNothing);
        client.failure = null;
        hideAndReturn(tester);
        await tester.pumpAndSettle();
        expect(find.text(_offline), findsNothing);
        expect(catalog.statusNotifier.value.reach, CatalogReach.reached);
        expect(find.text('The Orchard'), findsWidgets);
      },
    );
  });
}
