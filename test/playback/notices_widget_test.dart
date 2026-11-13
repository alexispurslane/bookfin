import 'package:bookfin/catalog/book_page.dart';
import 'package:bookfin/catalog/controller.dart';
import 'package:bookfin/catalog/layout.dart';
import 'package:bookfin/catalog/library_services.dart';
import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/catalog/screen.dart';
import 'package:bookfin/foundation/theme.dart';
import 'package:bookfin/playback/playback.dart';
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
