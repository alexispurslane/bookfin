import 'dart:async';
import 'dart:convert';

import 'package:bookfin/appearance/preferences.dart';
import 'package:bookfin/catalog/controller.dart';
import 'package:bookfin/catalog/jellyfin.dart';
import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../appearance/preferences_test.dart' show MemoryAppearanceStore;
import '../catalog/controller_test.dart'
    show FixtureClient, MemoryCatalogStore, MemoryCredentials, account;
import '../catalog/model_test.dart' show entry;
import '../real_time.dart';

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

  Future<void> signIn(WidgetTester tester) async {
    await finish(
      tester,
      catalog.connect('https://books.example', 'alice', 'password'),
    );
    await finish(tester, catalog.refresh());
    client.refreshes = 0;
  }

  /// Starts from a saved success of [age], without changing the app clock.
  Future<void> restoreSuccess(WidgetTester tester, Duration? age) async {
    await signIn(tester);
    final key = account('alice').scope.key;
    final saved = jsonDecode(store.values[key]!) as Map<String, dynamic>;
    saved['completedAt'] = age == null
        ? null
        : DateTime.now().toUtc().subtract(age).toIso8601String();
    store.values[key] = jsonEncode(saved);
    await finish(tester, catalog.restore());
  }

  /// Runs real and fake time until the catalog's refresh ends.
  Future<void> finishRefresh(WidgetTester tester) =>
      runUntil(tester, () => !catalog.busy);

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
    testWidgets('a return keeps a catalog refreshed less than an hour ago', (
      tester,
    ) async {
      await restoreSuccess(tester, const Duration(minutes: 59));
      await show(tester);
      hideAndReturn(tester);
      await finishRefresh(tester);
      await tester.pumpAndSettle();
      expect(client.refreshes, 0);
      expect(catalog.statusNotifier.value.message, isNull);
    });

    for (final age in <Duration?>[const Duration(minutes: 61), null]) {
      testWidgets(
        'a return refreshes a catalog whose last success is ${age == null ? 'unknown' : 'older than one hour'}',
        (tester) async {
          await restoreSuccess(tester, age);
          await show(tester);
          hideAndReturn(tester);
          await finishRefresh(tester);
          expect(client.refreshes, 1);
          expect(catalog.verified, isTrue);
        },
      );
    }

    testWidgets(
      'an unchanged response starts a new hour without saving the catalog again',
      (tester) async {
        await restoreSuccess(tester, const Duration(hours: 2));
        final saved = store.values[account('alice').scope.key];
        await show(tester);
        hideAndReturn(tester);
        await finishRefresh(tester);
        expect(client.refreshes, 1);
        expect(store.values[account('alice').scope.key], same(saved));
        hideAndReturn(tester);
        await finishRefresh(tester);
        expect(client.refreshes, 1);
        expect(catalog.verified, isTrue);
        catalog.checkInvariants();
      },
    );

    testWidgets('a manual refresh still reads a recent catalog', (
      tester,
    ) async {
      await signIn(tester);
      await finish(tester, catalog.refresh(byUser: true));
      expect(client.refreshes, 1);
      expect(catalog.verified, isTrue);
    });

    testWidgets('the launch refresh still reads a recent saved catalog', (
      tester,
    ) async {
      await restoreSuccess(tester, const Duration(minutes: 5));
      await finish(tester, catalog.restore().then((_) => catalog.refresh()));
      expect(client.refreshes, 1);
      expect(catalog.verified, isTrue);
    });

    testWidgets('an incomplete response does not start a new hour', (
      tester,
    ) async {
      await restoreSuccess(tester, const Duration(hours: 2));
      await show(tester);
      client.failure = const CatalogFailure(CatalogFailureKind.incomplete);
      hideAndReturn(tester);
      await finishRefresh(tester);
      expect(catalog.verified, isFalse);
      client.failure = null;
      hideAndReturn(tester);
      await finishRefresh(tester);
      expect(client.refreshes, 2);
      expect(catalog.verified, isTrue);
    });

    testWidgets(
      'a failed save keeps the old books and does not start a new hour',
      (tester) async {
        await restoreSuccess(tester, const Duration(hours: 2));
        await show(tester);
        client.entries = [entry('one', title: 'The River')];
        store.failWrites = true;
        hideAndReturn(tester);
        await finishRefresh(tester);
        expect(catalog.books.single.title, 'The Orchard');
        expect(catalog.verified, isFalse);
        store.failWrites = false;
        hideAndReturn(tester);
        await finishRefresh(tester);
        expect(client.refreshes, 2);
        expect(catalog.books.single.title, 'The River');
      },
    );

    testWidgets('a correction after an unchanged response keeps the new hour', (
      tester,
    ) async {
      await restoreSuccess(tester, const Duration(hours: 2));
      await show(tester);
      hideAndReturn(tester);
      await finishRefresh(tester);
      await finish(
        tester,
        catalog.correctBook(
          'book:one',
          const BookDetails(title: 'My title', author: 'Writer'),
        ),
      );
      hideAndReturn(tester);
      await finishRefresh(tester);
      expect(client.refreshes, 1);
      expect(catalog.books.single.title, 'My title');
    });

    testWidgets('a return from inactive only does not refresh it', (
      tester,
    ) async {
      await signIn(tester);
      await show(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(client.refreshes, 0);
    });

    testWidgets('a second return without hiding again does not refresh it', (
      tester,
    ) async {
      await restoreSuccess(tester, const Duration(hours: 2));
      await show(tester);
      hideAndReturn(tester);
      await finishRefresh(tester);
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(client.refreshes, 1);
    });

    testWidgets('a return while a refresh runs starts no other', (
      tester,
    ) async {
      await signIn(tester);
      await show(tester);
      client.pendingValidate = Completer();
      final asked = catalog.refresh(byUser: true);
      await tester.pump();
      hideAndReturn(tester);
      await tester.pump();
      client.pendingValidate!.complete();
      await finish(tester, asked);
      await tester.pumpAndSettle();
      expect(client.refreshes, 1);
      expect(catalog.statusNotifier.value.verified, isTrue);
    });

    testWidgets('a return while a sign-in runs starts no refresh', (
      tester,
    ) async {
      await signIn(tester);
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
      await finish(tester, signingIn);
      await tester.pumpAndSettle();
      // Only the sign-in's own catalog read, not one for the return.
      expect(client.refreshes, 1);
      expect(catalog.statusNotifier.value.verified, isTrue);
    });

    testWidgets(
      'a return while the saved library loads starts no refresh and keeps it',
      (tester) async {
        await signIn(tester);
        catalog.dispose();
        final gate = store.readGate = Completer<void>();
        catalog = newCatalog();
        final restoring = catalog.restore();
        await show(tester);
        expect(catalog.session, isNotNull);
        hideAndReturn(tester);
        await tester.pump();
        gate.complete();
        await finish(tester, restoring);
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
      'another account does not inherit the previous account refresh time',
      (tester) async {
        await signIn(tester);
        credentials.value = account('bob');
        await finish(tester, catalog.restore());
        await show(tester);
        hideAndReturn(tester);
        await finishRefresh(tester);
        expect(client.refreshes, 1);
        expect(catalog.session!.username, 'bob');
        expect(catalog.verified, isTrue);
        catalog.checkInvariants();
      },
    );

    testWidgets(
      'an expired sign-in keeps the local account without refreshing on return',
      (tester) async {
        await signIn(tester);
        client.failure = const CatalogFailure(CatalogFailureKind.unauthorized);
        await finish(tester, catalog.refresh());
        client.refreshes = 0;
        await show(tester);
        hideAndReturn(tester);
        await tester.pumpAndSettle();
        expect(client.refreshes, 0);
        expect(catalog.session, isNotNull);
        expect(catalog.books, isNotEmpty);
        expect(catalog.statusNotifier.value.reach, CatalogReach.signInExpired);
        catalog.checkInvariants();
      },
    );

    testWidgets(
      'a return that reaches Jellyfin brings back the full library after it was offline',
      (tester) async {
        await signIn(tester);
        client.failure = const CatalogFailure(CatalogFailureKind.unavailable);
        await finish(tester, catalog.refresh());
        await show(tester);
        expect(find.text(_offline), findsOneWidget);
        expect(find.text('The Orchard'), findsNothing);
        client.failure = null;
        hideAndReturn(tester);
        await finishRefresh(tester);
        await tester.pumpAndSettle();
        expect(find.text(_offline), findsNothing);
        expect(catalog.statusNotifier.value.reach, CatalogReach.reached);
        expect(find.text('The Orchard'), findsWidgets);
      },
    );
  });
}
