import 'dart:async';

import 'package:bookfin/catalog/book_cover.dart';
import 'package:bookfin/catalog/controller.dart';
import 'package:bookfin/catalog/library_view.dart' show BookRow;
import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/catalog/screen.dart';
import 'package:bookfin/foundation/theme.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:bookfin/playback/recent.dart' show listenedWhen;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../catalog/controller_test.dart'
    show FixtureClient, MemoryCredentials, MemoryCatalogStore;
import '../catalog/model_test.dart' show entry;
import 'playback_test.dart' show LocalFiles, TestEngine, MemoryResume;

void main() {
  late FixtureClient client;
  late CatalogController catalog;
  late LocalFiles downloads;
  late MemoryResume store;
  late Playback playback;
  Book book(String title) =>
      catalog.books.singleWhere((book) => book.title == title);
  Edition audio(Book book) =>
      book.editions.firstWhere((edition) => edition.kind == EditionKind.audio);

  Playback newPlayback() =>
      Playback(downloads: downloads, engine: TestEngine(), store: store);

  /// Listens to each title in turn, so the last title is the newest.
  Future<void> listen(List<String> titles) async {
    for (final title in titles) {
      await playback.open(book(title), audio(book(title)));
      await playback.jump(forward: true);
      await playback.pause();
    }
    await playback.flush();
  }

  /// Starts the app again with the same records but nothing open.
  Future<void> relaunchWithNothingOpen() async {
    final account = catalog.session!.scope.key;
    await playback.close();
    store.values[account] = {...store.values[account]!, 'selected': null};
    playback = newPlayback();
    await playback.bind(catalog.session, catalog.books);
  }

  setUp(() async {
    client = FixtureClient(Uri.parse('https://books.example'))
      ..entries = [
        entry('frost', title: 'First Frost', source: 'frost'),
        entry('tide', title: 'Tidewater', source: 'tide'),
        entry('quiet', title: 'A Map of Quiet Rooms', source: 'quiet'),
      ];
    catalog = CatalogController(
      credentials: MemoryCredentials(),
      store: MemoryCatalogStore(),
      clientFactory: (_, _) => client,
    );
    downloads = LocalFiles();
    store = MemoryResume();
    await catalog.connect('https://books.example', 'alice', 'fixture-password');
    await catalog.refresh(selected: {'books'});
    for (final book in catalog.books) {
      for (final file in audio(book).files) {
        downloads.files[file.key] = Uri.file('/fixture.wav');
      }
    }
    playback = newPlayback();
    await playback.bind(catalog.session, catalog.books);
  });
  tearDown(() async {
    await playback.close();
    downloads.dispose();
    catalog.dispose();
    client.close();
  });

  Future<void> showListening(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: bookfinTheme(Brightness.light),
        home: CatalogHome(
          catalog: catalog,
          onAppearance: () {},
          onReaderNightChanged: (_) {},
          downloads: downloads,
          playback: playback,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Listening'));
    await tester.pumpAndSettle();
  }

  /// Runs fake and real time until [work] ends. A tap starts playback work in
  /// fake time, and that work also waits on real file reads.
  Future<void> finish(WidgetTester tester, Future<void> work) async {
    var done = false;
    unawaited(work.whenComplete(() => done = true));
    for (var step = 0; !done && step < 100; step++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(done, isTrue);
  }

  double top(WidgetTester tester, String title) =>
      tester.getTopLeft(find.text(title)).dy;

  test('recent listening names the day it happened', () {
    final now = DateTime(2026, 11, 7, 9);
    expect(listenedWhen(DateTime(2026, 11, 7, 0, 5), now), 'Today');
    expect(listenedWhen(DateTime(2026, 11, 6, 23, 50), now), 'Yesterday');
    expect(listenedWhen(DateTime(2026, 11, 3, 12), now), 'Tuesday');
    expect(listenedWhen(DateTime(2026, 10, 12, 12), now), '12 Oct');
    expect(listenedWhen(DateTime(2025, 12, 30, 12), now), '30 Dec 2025');
  });

  test('recent listening lists each book once, newest first', () async {
    await listen(['First Frost', 'Tidewater', 'First Frost']);

    expect(
      [for (final recent in playback.recent) recent.book.title],
      ['First Frost', 'Tidewater'],
    );
    expect(playback.recent.first.edition, audio(book('First Frost')));
  });

  testWidgets(
    'with nothing open, Listening shows recently listened books with covers, newest first',
    (tester) async {
      await tester.runAsync(() async {
        await listen(['Tidewater', 'First Frost']);
        await relaunchWithNothingOpen();
      });
      expect(playback.book, isNull);

      await showListening(tester);

      expect(find.text('First Frost'), findsOneWidget);
      expect(find.text('Tidewater'), findsOneWidget);
      expect(find.text('A Map of Quiet Rooms'), findsNothing);
      expect(top(tester, 'First Frost'), lessThan(top(tester, 'Tidewater')));
      expect(find.byType(BookCover), findsNWidgets(2));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('tapping a recently listened book resumes it in the player', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await listen(['Tidewater', 'First Frost']);
      await relaunchWithNothingOpen();
    });
    await showListening(tester);

    await tester.tap(find.text('Tidewater'));
    await finish(tester, playback.flush());
    await tester.pump();

    expect(playback.book?.title, 'Tidewater');
    expect(find.text('NOW LISTENING'), findsOneWidget);
    expect(playback.editionMilliseconds, greaterThan(0));
    // Close in fake time too, because the tap made fake-time playback work.
    await finish(tester, playback.close());
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'while a book is open, the player shows its cover and other recent books follow it',
    (tester) async {
      await tester.runAsync(() => listen(['Tidewater', 'First Frost']));
      await showListening(tester);

      expect(find.text('NOW LISTENING'), findsOneWidget);
      expect(find.text('First Frost'), findsOneWidget);
      expect(find.byType(BookCover), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Tidewater'), 200);
      expect(
        find.descendant(
          of: find.widgetWithText(BookRow, 'Tidewater'),
          matching: find.byType(BookCover),
        ),
        findsOneWidget,
      );
      expect(find.widgetWithText(BookRow, 'First Frost'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
