import 'package:bookfin/catalog/book_cover.dart';
import 'package:bookfin/catalog/controller.dart';
import 'package:bookfin/catalog/jellyfin.dart';
import 'package:bookfin/catalog/layout.dart';
import 'package:bookfin/catalog/library_view.dart' show LibraryShelf;
import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/catalog/screen.dart';
import 'package:bookfin/downloads/downloads.dart';
import 'package:bookfin/foundation/theme.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:bookfin/playback/screen.dart' show PlayerView;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback/playback_test.dart' show MemoryResume, TestEngine;
import 'controller_test.dart'
    show FixtureClient, MemoryCatalogStore, MemoryCredentials;
import 'layout_test.dart' show MemoryLayoutStore;
import 'model_test.dart' show entry;
import '../real_time.dart';

/// Download state that a test sets by hand. Every file is on the phone, so
/// the player can open any book.
class _Downloads extends Downloads {
  _Downloads() : super(MediaPolicy()..network = MediaNetwork.disconnected);
  final _states = <String, EditionDownload>{};

  void set(Edition edition, EditionDownload state) {
    _states[edition.id] = state;
    notifyListeners();
  }

  @override
  bool get supported => true;
  @override
  Future<void> bind(JellyfinSession? session, List<Book> books) async {}
  @override
  Future<Uri?> localFile(SourceFile source) async => Uri.file('/fixture.wav');
  @override
  EditionDownload status(Edition edition) =>
      _states[edition.id] ?? const EditionDownload();
  @override
  Future<void> request(Edition edition) async {}
  @override
  Future<void> cancel(Edition edition) async {}
  @override
  Future<void> remove(Edition edition) async {}
  @override
  Future<void> get idle async {}
  @override
  void checkInvariants() {}
}

/// How many times each widget type rebuilt while [during] ran.
Future<Map<Type, int>> _rebuildsDuring(Future<void> Function() during) async {
  final counts = <Type, int>{};
  debugOnRebuildDirtyWidget = (element, _) => counts.update(
    element.widget.runtimeType,
    (count) => count + 1,
    ifAbsent: () => 1,
  );
  try {
    await during();
  } finally {
    debugOnRebuildDirtyWidget = null;
  }
  return counts;
}

void main() {
  late FixtureClient client;
  late CatalogController catalog;
  late _Downloads downloads;
  late Playback playback;
  late TestEngine engine;
  late LibraryLayout layout;
  Book book(String title) =>
      catalog.books.singleWhere((book) => book.title == title);
  Edition audio(Book book) =>
      book.editions.firstWhere((edition) => edition.kind == EditionKind.audio);

  setUp(() async {
    client = FixtureClient(Uri.parse('https://books.example'))
      ..entries = [
        entry('frost', title: 'First Frost', source: 'frost'),
        entry('tide', title: 'Tidewater', source: 'tide'),
        for (final (index, title) in ['Graft', 'Windfall'].indexed)
          entry(
            title,
            title: title,
            source: title,
            fields: {'SeriesName': 'The Orchard Cycle', 'IndexNumber': index},
          ),
      ];
    catalog = CatalogController(
      credentials: MemoryCredentials(),
      store: MemoryCatalogStore(),
      clientFactory: (_, _) => client,
    );
    await catalog.connect('https://books.example', 'alice', 'password');
    await catalog.refresh(selected: {'books'});
    downloads = _Downloads();
    engine = TestEngine();
    playback = Playback(
      downloads: downloads,
      engine: engine,
      store: MemoryResume(),
    );
    layout = LibraryLayout(MemoryLayoutStore());
  });
  tearDown(() async {
    await playback.close();
    downloads.dispose();
    layout.dispose();
    catalog.dispose();
    client.close();
  });

  /// Shows the app with First Frost open in the player at 5 seconds.
  Future<void> showListening(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: bookfinTheme(Brightness.light),
        home: CatalogHome(
          catalog: catalog,
          layout: layout,
          onAppearance: () {},
          onReaderNightChanged: (_) {},
          downloads: downloads,
          playback: playback,
        ),
      ),
    );
    await finish(tester, playback.bind(catalog.session, catalog.books));
    final frost = book('First Frost');
    await finish(tester, playback.open(frost, audio(frost), autoplay: false));
    engine.emit(0, 5000);
    await tester.pumpAndSettle();
  }

  /// A widget test whose player closes before fake time ends, because closing
  /// waits on work that fake time does not run.
  void testApp(String description, Future<void> Function(WidgetTester) body) =>
      testWidgets(description, (tester) async {
        try {
          await body(tester);
        } finally {
          await finish(tester, playback.close());
        }
      });

  var tick = 5000;

  /// One player tick: the position moves on by 200 milliseconds.
  Future<void> playerTick(WidgetTester tester) async {
    engine.emit(0, tick += 200, playing: true);
    await tester.pump();
  }

  testApp(
    'player ticks, download progress and catalog refreshes leave the app shell unbuilt',
    (tester) async {
      await showListening(tester);
      final tide = audio(book('Tidewater'));
      final rebuilt = await _rebuildsDuring(() async {
        await playerTick(tester);
        downloads.set(
          tide,
          const EditionDownload(phase: DownloadPhase.downloading, bytes: 10),
        );
        await tester.pump();
        await finish(tester, catalog.refresh());
        await tester.pump();
      });
      expect(rebuilt[NavigationBar], isNull);
    },
  );

  testApp('signing out still switches the shell to the sign-in screen', (
    tester,
  ) async {
    await showListening(tester);
    await finish(tester, catalog.signOut());
    await tester.pumpAndSettle();
    expect(find.text('Your library starts here.'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testApp('player ticks and download progress do not regroup the library', (
    tester,
  ) async {
    await showListening(tester);
    final tide = audio(book('Tidewater'));
    final rebuilt = await _rebuildsDuring(() async {
      await playerTick(tester);
      downloads.set(
        tide,
        const EditionDownload(phase: DownloadPhase.downloading, bytes: 10),
      );
      await tester.pump();
    });
    expect(rebuilt[RefreshIndicator], isNull);
  });

  testApp('the playing book’s library tile follows the player', (tester) async {
    await showListening(tester);
    double progress() => tester
        .widget<ProgressLine>(
          find.descendant(
            of: find.byType(LibraryShelf),
            matching: find.byType(ProgressLine),
          ),
        )
        .value!;
    final before = progress();
    engine.emit(0, 45000, playing: true);
    await tester.pump();
    expect(progress(), greaterThan(before));
  });

  testApp(
    'a finished download marks its cover and joins the Downloaded filter',
    (tester) async {
      await showListening(tester);
      List<String> marked() => [
        for (final cover in tester.widgetList<BookCover>(
          find.byType(BookCover),
        ))
          if (cover.downloaded) cover.title,
      ];
      // The mini player also shows the open book's title.
      Finder onShelf(String title) => find.descendant(
        of: find.byType(LibraryShelf),
        matching: find.text(title),
      );
      expect(marked(), isEmpty);
      downloads.set(
        audio(book('Tidewater')),
        const EditionDownload(phase: DownloadPhase.downloaded),
      );
      await tester.pump();
      expect(marked(), ['Tidewater']);
      await tester.tap(find.text('Downloaded'));
      await tester.pumpAndSettle();
      expect(onShelf('Tidewater'), findsOneWidget);
      expect(onShelf('First Frost'), findsNothing);
      downloads.set(
        audio(book('First Frost')),
        const EditionDownload(phase: DownloadPhase.downloaded),
      );
      await tester.pump();
      expect(onShelf('First Frost'), findsOneWidget);
    },
  );

  testApp('the listening tab draws its own stage without a top bar', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: bookfinTheme(Brightness.light),
        home: CatalogHome(
          catalog: catalog,
          layout: layout,
          onAppearance: () {},
          onReaderNightChanged: (_) {},
          downloads: downloads,
          playback: playback,
        ),
      ),
    );
    await finish(tester, playback.bind(catalog.session, catalog.books));
    await tester.tap(find.text('Listening'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Listening'), findsOneWidget);
    final frost = book('First Frost');
    await finish(tester, playback.open(frost, audio(frost), autoplay: false));
    await tester.pumpAndSettle();
    expect(find.byType(AppBar), findsNothing);
  });

  testApp(
    'a tab’s top bar sits below the status bar, and the open player reaches it',
    (tester) async {
      tester.view.padding = FakeViewPadding(
        top: 24 * tester.view.devicePixelRatio,
      );
      addTearDown(tester.view.resetPadding);
      await showListening(tester);
      final bar = tester.getRect(find.widgetWithText(AppBar, 'Library'));
      expect(bar.top, 0);
      expect(bar.height, kToolbarHeight + 24);
      expect(tester.getTopLeft(find.byType(LibraryShelf)).dy, bar.bottom);
      await tester.tap(find.text('Listening'));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byType(PlayerView)).dy, 0);
      expect(
        MediaQuery.paddingOf(tester.element(find.byType(PlayerView))).top,
        24,
      );
    },
  );

  for (final (page, open) in <(String, Future<void> Function(WidgetTester))>[
    (
      'book page',
      (tester) async {
        await tester.tap(
          find.descendant(
            of: find.byType(LibraryShelf),
            matching: find.text('First Frost'),
          ),
        );
        await tester.pumpAndSettle();
      },
    ),
    (
      'series page',
      (tester) async {
        await tester.tap(find.text('The Orchard Cycle'));
        await tester.pumpAndSettle();
      },
    ),
    (
      'search page',
      (tester) async {
        await tester.tap(find.byTooltip('Search'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'r');
        await tester.pumpAndSettle();
      },
    ),
  ]) {
    testApp('a player tick does not rescan the library on the $page', (
      tester,
    ) async {
      await showListening(tester);
      await open(tester);
      final rebuilt = await _rebuildsDuring(() => playerTick(tester));
      expect(rebuilt[AppBar], isNull);
    });
  }
}
