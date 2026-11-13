import 'package:bookfin/catalog/book_page.dart';
import 'package:bookfin/catalog/controller.dart';
import 'package:bookfin/catalog/layout.dart';
import 'package:bookfin/catalog/library_services.dart';
import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/catalog/screen.dart';
import 'package:bookfin/foundation/theme.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:bookfin/playback/recent.dart';
import 'package:bookfin/playback/screen.dart';
import 'package:bookfin/playback/timeline.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../catalog/controller_test.dart';
import '../catalog/layout_test.dart' show MemoryLayoutStore;
import '../catalog/model_test.dart' show entry;
import 'notices_test.dart' show NoticeStore;
import 'playback_test.dart';

void main() {
  late CatalogController catalog;
  late FixtureClient client;
  late LibraryLayout layout;
  late LocalFiles downloads;
  late Playback playback;
  late NoticeStore store;
  late Book available;
  late Book missing;
  setUp(() async {
    client = FixtureClient(Uri.parse('https://books.example'))
      ..entries = [
        entry('one', title: 'Available'),
        entry('other', title: 'Missing'),
      ];
    catalog = CatalogController(
      credentials: MemoryCredentials(),
      store: MemoryCatalogStore(),
      clientFactory: (_, _) => client,
    );
    await catalog.connect('https://books.example', 'alice', 'password');
    await catalog.refresh();
    available = catalog.books.firstWhere((book) => book.title == 'Available');
    missing = catalog.books.firstWhere((book) => book.title == 'Missing');
    layout = LibraryLayout(MemoryLayoutStore());
    downloads = LocalFiles()..files.clear();
    downloads.files[available.editions.single.files.single.key] = Uri.file(
      '/available.m4b',
    );
    store = NoticeStore();
    playback = Playback(
      downloads: downloads,
      engine: TestEngine(),
      store: store,
    );
    await playback.bind(catalog.session, catalog.books);
    await playback.open(available, available.editions.single, autoplay: false);
  });
  tearDown(() async {
    await playback.close();
    downloads.dispose();
    layout.dispose();
    catalog.dispose();
    client.close();
  });

  LibraryServices services() => LibraryServices(
    catalog: catalog,
    layout: layout,
    onReaderNightChanged: (_) {},
    downloads: downloads,
    playback: playback,
  );

  Future<void> show(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: bookfinTheme(Brightness.light),
        home: Scaffold(body: page),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a failed recent Resume explains the error beside its book', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      final file = missing.editions.single.files.single;
      await tester.runAsync(() async {
        downloads.files[file.key] = Uri.file('/missing.m4b');
        await playback.open(missing, missing.editions.single);
        await playback.open(
          available,
          available.editions.single,
          autoplay: false,
        );
        downloads.files.remove(file.key);
      });
      await show(tester, PlayerView(playback: playback));
      await tester.ensureVisible(find.byTooltip('Resume Missing'));
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Resume Missing'));
        await playback.setJumps(10, 30);
      });
      await tester.pumpAndSettle();
      final error = playback.statusNotifier.value.actionNotice!.message;
      expect(
        find.descendant(
          of: find.byType(RecentListeningRow),
          matching: find.text(error),
        ),
        findsOneWidget,
      );
      expect(find.text(error), findsOneWidget);
      await tester.ensureVisible(find.text(error));
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel(RegExp(RegExp.escape(error))),
        findsOneWidget,
      );
      expect(playback.book, available);
    } finally {
      semantics.dispose();
    }
  });

  for (final emptyPlayer in [false, true]) {
    for (final bookmark in [false, true]) {
      testWidgets(
        'failed History ${bookmark ? 'bookmark' : 'action'} stays with its entry with ${emptyPlayer ? 'no' : 'another'} book open',
        (tester) async {
          final file = missing.editions.single.files.single;
          await tester.runAsync(() async {
            downloads.files[file.key] = Uri.file('/missing.m4b');
            await playback.open(missing, missing.editions.single);
            await playback.pause();
            if (bookmark) await playback.addBookmark(title: 'Missing place');
            await playback.open(
              available,
              available.editions.single,
              autoplay: false,
            );
            if (emptyPlayer) {
              await playback.bind(null, []);
              store.values[catalog.session!.scope.key]!['selected'] = null;
              await playback.bind(catalog.session, catalog.books);
            }
            downloads.files.remove(file.key);
          });
          await show(
            tester,
            Builder(
              builder: (context) => TextButton(
                onPressed: () => openHistory(context, playback),
                child: const Text('Show History'),
              ),
            ),
          );
          await tester.tap(find.text('Show History'));
          await tester.pumpAndSettle();
          await tester.tap(
            find.textContaining(bookmark ? 'Missing place' : 'Paused').first,
          );
          await tester.pumpAndSettle();
          await tester.runAsync(() async {
            await tester.tap(find.text('GO TO'));
            await playback.setJumps(10, 30);
          });
          await tester.pumpAndSettle();
          final error = playback.statusNotifier.value.actionNotice!.message;
          expect(find.byType(HistoryTimeline), findsOneWidget);
          expect(
            find.descendant(
              of: find.byType(HistoryTimeline),
              matching: find.text(error),
            ),
            findsOneWidget,
          );
          expect(playback.book, emptyPlayer ? isNull : available);

          downloads.files[file.key] = Uri.file('/missing.m4b');
          await tester.runAsync(() async {
            await tester.tap(find.text('GO TO'));
            await playback.setJumps(10, 30);
          });
          await tester.pumpAndSettle();
          expect(find.byType(HistoryTimeline), findsNothing);
          expect(playback.book, missing);
          expect(playback.statusNotifier.value.actionNotice, isNull);
        },
      );
    }
  }

  for (final surface in ['tab', 'other book', 'player', 'History']) {
    testWidgets('a failed Listen stays out of unrelated $surface content', (
      tester,
    ) async {
      await tester.runAsync(
        () => playback.open(missing, missing.editions.single),
      );
      final error = playback.statusNotifier.value.actionNotice!.message;
      final Widget page = switch (surface) {
        'tab' => TabPage(
          catalog: catalog,
          playback: playback,
          child: const Text('Downloads'),
        ),
        'other book' => BookPage(services: services(), bookId: available.id),
        'player' => PlayerView(playback: playback),
        _ => Builder(
          builder: (context) => TextButton(
            onPressed: () => openHistory(context, playback, book: available),
            child: const Text('Show History'),
          ),
        ),
      };
      await show(tester, page);
      if (surface == 'History') {
        await tester.tap(find.text('Show History'));
        await tester.pumpAndSettle();
      }
      expect(find.text(error), findsNothing);
    });
  }

  testWidgets('Listen shows its error on the book that requested it', (
    tester,
  ) async {
    await show(tester, BookPage(services: services(), bookId: missing.id));
    await tester.runAsync(() => tester.tap(find.text('Listen').first));
    await tester.pumpAndSettle();
    expect(
      playback.statusNotifier.value.actionNotice?.message,
      contains('Download'),
    );
    expect(
      find.text(playback.statusNotifier.value.actionNotice!.message),
      findsOneWidget,
    );
  });

  testWidgets('a current player error is inset like the position control', (
    tester,
  ) async {
    downloads.files.clear();
    await show(tester, PlayerView(playback: playback));
    await tester.runAsync(() => tester.tap(find.byTooltip('Play')));
    await tester.pumpAndSettle();
    final error = find.text(
      playback.statusNotifier.value.actionNotice!.message,
    );
    final control = find.byType(PositionSlider);
    expect(error, findsOneWidget);
    final messageRect = tester.getRect(error);
    final controlRect = tester.getRect(control);
    expect(messageRect.left, greaterThanOrEqualTo(controlRect.left));
    expect(messageRect.right, lessThanOrEqualTo(controlRect.right));
  });

  testWidgets(
    'Play clears its error but keeps recovery visible in the player',
    (tester) async {
      await tester.runAsync(() async {
        await playback.bind(null, []);
        store.recovered = true;
        await playback.bind(catalog.session, catalog.books);
      });
      final file = available.editions.single.files.single;
      final local = downloads.files.remove(file.key)!;
      await show(tester, PlayerView(playback: playback));
      await tester.runAsync(() => tester.tap(find.byTooltip('Play')));
      await tester.pumpAndSettle();
      final error = playback.statusNotifier.value.actionNotice!.message;
      final recovery = playback.statusNotifier.value.recoveryMessage!;
      expect(find.text(error), findsOneWidget);
      expect(find.text(recovery), findsOneWidget);

      downloads.files[file.key] = local;
      await tester.runAsync(() => tester.tap(find.byTooltip('Play')));
      await tester.pumpAndSettle();

      expect(playback.playing, isTrue);
      expect(find.text(error), findsNothing);
      expect(find.text(recovery), findsOneWidget);
    },
  );

  testWidgets(
    'History keeps account recovery and retries saves without an unrelated Listen error',
    (tester) async {
      await tester.runAsync(() async {
        await playback.bind(null, []);
        store.recovered = true;
        await playback.bind(catalog.session, catalog.books);
        store.failSave = true;
        await playback.addBookmark(title: 'A kept place');
        await playback.open(missing, missing.editions.single);
      });
      final error = playback.statusNotifier.value.actionNotice!.message;
      final recovery = playback.statusNotifier.value.recoveryMessage!;
      await show(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => openHistory(context, playback, book: available),
            child: const Text('Show History'),
          ),
        ),
      );
      await tester.tap(find.text('Show History'));
      await tester.pumpAndSettle();
      expect(find.text(error), findsNothing);
      expect(find.text(recovery), findsOneWidget);
      expect(find.text('Retry saving'), findsOneWidget);

      store.failSave = false;
      await tester.runAsync(() => tester.tap(find.text('Retry saving')));
      await tester.pumpAndSettle();

      expect(playback.saveFailed, isFalse);
      expect(find.text('Retry saving'), findsNothing);
      expect(find.text(recovery), findsOneWidget);
      expect(playback.statusNotifier.value.actionNotice?.message, error);
      expect(playback.bookmarks.single.title, 'A kept place');
    },
  );
}
