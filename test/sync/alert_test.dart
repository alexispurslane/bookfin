import 'package:bookfin/catalog/book_page.dart';
import 'package:bookfin/catalog/controller.dart';
import 'package:bookfin/catalog/layout.dart';
import 'package:bookfin/catalog/library_services.dart';
import 'package:bookfin/catalog/shelf.dart';
import 'package:bookfin/foundation/theme.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:bookfin/playback/screen.dart';
import 'package:bookfin/settings/screen.dart';
import 'package:bookfin/sync/alert.dart';
import 'package:bookfin/sync/coordinator.dart';
import 'package:bookfin/sync/journal.dart';
import 'package:bookfin/sync/screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../catalog/controller_test.dart'
    show FixtureClient, MemoryCatalogStore, MemoryCredentials;
import '../catalog/layout_test.dart' show MemoryLayoutStore;
import '../catalog/book_page_test.dart' show StaticDownloads;
import '../playback/player_view_test.dart' show book, narrated;
import '../playback/playback_test.dart'
    show LocalFiles, MemoryResume, TestEngine, account, first;
import '../real_time.dart';
import 'conflicts.dart';
import 'status_test.dart' show ControlledRecords;

// The alert outside the Personal records page: a notice on the book page, a
// pill in the player, a badge on the Settings tab, and a line on the
// Settings row. All of them read RecordSync.conflictsNotifier.
void main() {
  late ControlledRecords records;
  late RecordSync sync;
  setUp(() async {
    records = ControlledRecords();
    sync = RecordSync(records: records, transport: records.transport)
      ..bind(account());
    await pumpEventQueue();
  });
  tearDown(() => sync.dispose());

  /// Syncs in the background with what [records] now holds.
  Future<void> backgroundSync(WidgetTester tester) async {
    await tester.runAsync(sync.synchronize);
    await tester.pumpAndSettle();
  }

  /// Waits for the choice that the user made to end.
  Future<void> settleChoice(WidgetTester tester) async {
    await settle(tester, sync);
  }

  void tallScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
  }

  group('on the book page', () {
    late FixtureClient client;
    late CatalogController catalog;
    late StaticDownloads downloads;
    setUp(() {
      client = FixtureClient(Uri.parse('https://books.example'));
      catalog = CatalogController(
        credentials: MemoryCredentials(),
        store: MemoryCatalogStore(),
        clientFactory: (server, device) => client,
      );
      downloads = StaticDownloads();
    });
    tearDown(() {
      catalog.dispose();
      client.close();
      downloads.dispose();
    });

    Future<void> showBook(WidgetTester tester) async {
      tallScreen(tester);
      await finish(
        tester,
        catalog.connect('https://books.example', 'alice', 'password'),
      );
      await finish(tester, catalog.refresh());
      await tester.pumpWidget(
        MaterialApp(
          theme: bookfinTheme(Brightness.light),
          builder: (context, child) =>
              RecordSyncScope(sync: sync, child: child!),
          home: BookPage(
            services: LibraryServices(
              catalog: catalog,
              layout: LibraryLayout(MemoryLayoutStore()),
              onReaderNightChanged: (_) {},
              downloads: downloads,
            ),
            bookId: catalog.books.single.id,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// Two saved places of the catalog's only book.
    Map<String, List<Map<String, dynamic>>> orchardConflict() {
      final edition = catalog.books.single.editions.single;
      final file = edition.files.first;
      return {
        placeRecord(edition, file): [
          place('Pixel 8', 4 * hour, edition: edition, file: file),
          place('Pixel Tablet', 2 * hour, edition: edition, file: file),
        ],
      };
    }

    testWidgets('no notice appears while no choice waits', (tester) async {
      await showBook(tester);
      expect(find.byType(ConflictAlert), findsNothing);
      expect(find.text('Two devices saved different places'), findsNothing);
    });

    testWidgets(
      'a conflict found by a background sync shows a notice above Resume on its book',
      (tester) async {
        await showBook(tester);
        records.found = orchardConflict();
        await backgroundSync(tester);
        expect(find.text('Two devices saved different places'), findsOneWidget);
        expect(find.textContaining('Pixel 8 at 4:00:00'), findsOneWidget);
        final notice = tester.getRect(find.byType(ConflictAlert));
        final listen = find.textContaining(RegExp('^(Listen|Resume)\$'));
        if (listen.evaluate().isNotEmpty) {
          expect(
            notice.bottom,
            lessThanOrEqualTo(tester.getRect(listen.first).top),
          );
        }
      },
    );

    testWidgets('a conflict of another book shows no notice here', (
      tester,
    ) async {
      await showBook(tester);
      records.found = {...frostConflict};
      await backgroundSync(tester);
      expect(find.byType(ConflictAlert), findsNothing);
    });

    testWidgets(
      'Choose opens the choice in a glass sheet, and Keep resolves it and the notice goes away',
      (tester) async {
        await showBook(tester);
        final conflict = orchardConflict();
        records.found = conflict;
        await backgroundSync(tester);
        await tester.tap(find.widgetWithText(FilledButton, 'Choose'));
        await tester.pumpAndSettle();
        expect(find.text('Choose a saved place'), findsOneWidget);
        expect(find.text('Keep A'), findsOneWidget);
        await tester.tap(find.text('Keep B'));
        await settleChoice(tester);
        expect(records.resolved, [
          RecordJournal.identity(conflict.values.single.last),
        ]);
        expect(find.text('Choose a saved place'), findsNothing);
        expect(find.byType(ConflictAlert), findsNothing);
      },
    );

    testWidgets('Not now closes the sheet and the notice stays', (
      tester,
    ) async {
      await showBook(tester);
      records.found = orchardConflict();
      await backgroundSync(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Choose'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(find.text('Choose a saved place'), findsNothing);
      expect(records.resolved, isEmpty);
      expect(find.byType(ConflictAlert), findsOneWidget);
    });

    testWidgets('the Settings row says which book waits for a choice', (
      tester,
    ) async {
      tallScreen(tester);
      await finish(
        tester,
        catalog.connect('https://books.example', 'alice', 'password'),
      );
      await finish(tester, catalog.refresh());
      await tester.pumpWidget(
        MaterialApp(
          theme: bookfinTheme(Brightness.light),
          home: Scaffold(
            body: SettingsTab(
              catalog: catalog,
              layout: LibraryLayout(MemoryLayoutStore()),
              onAppearance: () {},
              sync: sync,
            ),
          ),
        ),
      );
      expect(find.text('Bookmarks, history, and progress'), findsOneWidget);
      records.found = orchardConflict();
      await backgroundSync(tester);
      final title = catalog.books.single.title;
      expect(find.text('A choice waits · $title'), findsOneWidget);
      expect(find.text('Bookmarks, history, and progress'), findsNothing);
      records.found = {...orchardConflict(), ...frostConflict};
      await backgroundSync(tester);
      expect(find.textContaining('2 choices wait · '), findsOneWidget);
      records.found = {};
      await backgroundSync(tester);
      expect(find.text('Bookmarks, history, and progress'), findsOneWidget);
    });
  });

  group('in the player', () {
    late Playback playback;
    late LocalFiles downloads;
    setUp(() async {
      downloads = LocalFiles();
      playback = Playback(
        downloads: downloads,
        engine: TestEngine(),
        store: MemoryResume(),
      );
      await playback.bind(account(), [book]);
      await playback.open(book, narrated, autoplay: false);
    });
    tearDown(() async {
      await playback.close();
      downloads.dispose();
    });

    final playerConflict = {
      placeRecord(narrated, first): [
        place('Pixel 8', 90000, edition: narrated, file: first),
        place('Pixel Tablet', 30000, edition: narrated, file: first),
      ],
    };

    Widget player({Widget? below}) => MaterialApp(
      theme: bookfinTheme(Brightness.light),
      builder: (context, child) => RecordSyncScope(sync: sync, child: child!),
      home: Scaffold(
        body: Column(
          children: [
            Expanded(child: PlayerView(playback: playback)),
            ?below,
          ],
        ),
      ),
    );

    testWidgets(
      'a pill under the chapter appears only while a choice waits for the open book',
      (tester) async {
        tallScreen(tester);
        await tester.pumpWidget(player());
        await tester.pumpAndSettle();
        expect(find.byType(ConflictAlert), findsNothing);
        records.found = {...frostConflict};
        await backgroundSync(tester);
        expect(find.byType(ConflictAlert), findsNothing);
        records.found = {...playerConflict};
        await backgroundSync(tester);
        expect(find.text('Saved places differ'), findsOneWidget);
      },
    );

    testWidgets(
      'Choose on the pill opens the choice, and Keep clears the pill',
      (tester) async {
        tallScreen(tester);
        records.found = {...playerConflict};
        await tester.pumpWidget(player());
        await backgroundSync(tester);
        await tester.tap(find.text('Choose'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Keep A'));
        await settleChoice(tester);
        expect(records.resolved, hasLength(1));
        expect(find.byType(ConflictAlert), findsNothing);
      },
    );

    testWidgets(
      'a Keep on the Personal records page clears the pill and the badge together',
      (tester) async {
        tallScreen(tester);
        records.found = {...playerConflict};
        await tester.pumpWidget(
          player(
            below: SizedBox(
              height: 900,
              child: Row(
                children: [
                  ChoicesBadge(
                    conflicts: sync.conflictsNotifier,
                    child: const Icon(Icons.settings_outlined),
                  ),
                  Expanded(
                    child: RecordSyncView(
                      status: sync.statusNotifier,
                      lastSync: sync.lastSyncNotifier,
                      conflicts: sync.conflictsNotifier,
                      kept: records.kept,
                      library: ValueNotifier(CatalogLibrary.build([book])),
                      onSync: () {},
                      onResolve: (record, identity, bookmarkTitles) =>
                          sync.resolve(
                            record,
                            identity,
                            bookmarkTitles: bookmarkTitles,
                          ),
                      onDiscard: () {},
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await backgroundSync(tester);
        expect(find.byType(ConflictAlert), findsOneWidget);
        expect(find.text('1'), findsOneWidget);
        final keep = find.text('Keep A');
        await tester.ensureVisible(keep);
        await tester.tap(keep);
        await settleChoice(tester);
        expect(find.byType(ConflictAlert), findsNothing);
        expect(find.text('1'), findsNothing);
      },
    );
  });

  testWidgets('the Settings tab badge counts the waiting choices', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChoicesBadge(
            conflicts: sync.conflictsNotifier,
            child: const Icon(Icons.settings_outlined),
          ),
        ),
      ),
    );
    Badge badge() => tester.widget<Badge>(find.byType(Badge));
    expect(badge().isLabelVisible, isFalse);
    records.found = {...frostConflict};
    await backgroundSync(tester);
    expect(badge().isLabelVisible, isTrue);
    expect(find.text('1'), findsOneWidget);
    records.found = {...frostConflict, ...northConflict};
    await backgroundSync(tester);
    expect(find.text('2'), findsOneWidget);
    records.found = {};
    await backgroundSync(tester);
    expect(badge().isLabelVisible, isFalse);
  });
}

/// Waits until the sync or the choice that the user started on [sync]
/// ends, in real and fake time in turns, then lets the frames settle.
Future<void> settle(WidgetTester tester, RecordSync sync) async {
  await tester.pump();
  await runUntil(tester, () => !sync.busy);
  await tester.pumpAndSettle();
}
