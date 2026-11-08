import 'dart:async';

import 'package:bookfin/catalog/book_cover.dart';
import 'package:bookfin/catalog/book_page.dart' show BookPage;
import 'package:bookfin/catalog/controller.dart';
import 'package:bookfin/catalog/jellyfin.dart';
import 'package:bookfin/catalog/layout.dart';
import 'package:bookfin/catalog/library_services.dart';
import 'package:bookfin/catalog/library_view.dart';
import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/catalog/shelf.dart';
import 'package:bookfin/downloads/downloads.dart';
import 'package:bookfin/foundation/theme.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback/playback_test.dart' show MemoryResume, TestEngine;
import 'controller_test.dart'
    show FixtureClient, MemoryCatalogStore, MemoryCredentials;
import 'model_test.dart' show entry;

/// Download state that a test sets by hand. It records which editions the
/// library asked about, apart from the questions that Downloads itself asks
/// to update its per-edition watches.
class _Downloads extends Downloads {
  _Downloads() : super(MediaPolicy()..network = MediaNetwork.disconnected);
  final _states = <String, EditionDownload>{};
  final asked = <String>[];
  var _updating = false;

  void set(Edition edition, EditionDownload state) {
    _states[edition.id] = state;
    notifyListeners();
  }

  @override
  void updateWatches() {
    _updating = true;
    try {
      super.updateWatches();
    } finally {
      _updating = false;
    }
  }

  @override
  bool get supported => true;
  @override
  Future<void> bind(JellyfinSession? session, List<Book> books) async {}
  @override
  Future<Uri?> localFile(SourceFile source) async => Uri.file('/fixture.wav');
  @override
  EditionDownload status(Edition edition) {
    if (!_updating) asked.add(edition.id);
    return _states[edition.id] ?? const EditionDownload();
  }

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

/// Playback that records which editions were asked for listening progress.
class _Playback extends Playback {
  _Playback({
    required super.downloads,
    required super.engine,
    required super.store,
  });
  final asked = <String>[];

  @override
  ({int elapsedMs, int totalMs})? progress(Edition edition) {
    asked.add(edition.id);
    return super.progress(edition);
  }
}

/// A layout store that fails the test on any write.
class _ReadOnlyLayoutStore implements LayoutStore {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String value) async =>
      fail('A layout write happened: $value');
}

/// A layout store that keeps what it saved.
class _SavingLayoutStore implements LayoutStore {
  final writes = <String>[];
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String value) async => writes.add(value);
}

/// The widgets that rebuilt while [during] ran.
Future<List<Element>> _rebuiltDuring(Future<void> Function() during) async {
  final rebuilt = <Element>[];
  debugOnRebuildDirtyWidget = (element, _) => rebuilt.add(element);
  try {
    await during();
  } finally {
    debugOnRebuildDirtyWidget = null;
  }
  return rebuilt;
}

/// The titles of the covers among [rebuilt] that sit below a [T] widget.
List<String> _coversBelow<T extends Widget>(List<Element> rebuilt) => [
  for (final element in rebuilt)
    if (element.widget case BookCover(:final title)
        when element.findAncestorWidgetOfExactType<T>() != null)
      title,
];

class _Pushes extends NavigatorObserver {
  final routes = <Route<dynamic>>[];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      routes.add(route);
}

void main() {
  late FixtureClient client;
  late CatalogController catalog;
  late _Downloads downloads;
  late _Playback playback;
  late TestEngine engine;
  late LibraryLayout layout;
  late LibraryServices services;
  late _Pushes pushes;

  Book book(String title) =>
      catalog.books.singleWhere((book) => book.title == title);
  Edition audio(Book book) =>
      book.editions.firstWhere((edition) => edition.kind == EditionKind.audio);

  setUp(() async {
    client = FixtureClient(Uri.parse('https://books.example'))
      ..entries = [
        entry('frost', title: 'First Frost', source: 'frost'),
        entry('tide', title: 'Tidewater', source: 'tide'),
        entry(
          'ink',
          title: 'Inkwell',
          type: 'Book',
          source: 'ink',
          container: 'epub',
        ),
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
    playback = _Playback(
      downloads: downloads,
      engine: engine,
      store: MemoryResume(),
    );
    layout = LibraryLayout(_SavingLayoutStore());
    services = LibraryServices(
      catalog: catalog,
      layout: layout,
      onReaderNightChanged: (_) {},
      downloads: downloads,
      playback: playback,
    );
    pushes = _Pushes();
  });
  tearDown(() async {
    await playback.close();
    downloads.dispose();
    layout.dispose();
    catalog.dispose();
    client.close();
  });

  /// Runs fake and real time until [work] ends.
  Future<void> finish(WidgetTester tester, Future<void> work) async {
    var done = false;
    unawaited(work.whenComplete(() => done = true));
    for (var step = 0; !done && step < 100; step++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(done, isTrue);
  }

  /// Completes when no catalog refresh runs.
  Future<void> refreshEnded() {
    final ended = Completer<void>();
    void follow() {
      if (catalog.statusNotifier.value.refreshing || ended.isCompleted) return;
      catalog.statusNotifier.removeListener(follow);
      ended.complete();
    }

    catalog.statusNotifier.addListener(follow);
    follow();
    return ended.future;
  }

  /// A widget test whose player closes before fake time ends, because closing
  /// waits on work that fake time does not run.
  void testLibrary(
    String description,
    Future<void> Function(WidgetTester) body,
  ) => testWidgets(description, (tester) async {
    try {
      await body(tester);
    } finally {
      await finish(tester, playback.close());
    }
  });

  /// Shows the Library tab in the list view, which shows every entry on a
  /// small test screen.
  Future<void> showLibrary(WidgetTester tester) async {
    layout.view = LibraryView.list;
    await tester.pumpWidget(
      MaterialApp(
        theme: bookfinTheme(Brightness.light),
        navigatorObservers: [pushes],
        home: Scaffold(
          body: services.coverScope(LibraryTab(services: services)),
        ),
      ),
    );
    await finish(tester, playback.bind(catalog.session, catalog.books));
    await tester.pumpAndSettle();
  }

  /// Opens First Frost in the player, and plays one tick, so that later ticks
  /// change only the position.
  Future<void> playFirstFrost(WidgetTester tester) async {
    final frost = book('First Frost');
    await finish(tester, playback.open(frost, audio(frost), autoplay: false));
    engine.emit(0, 5000, playing: true);
    await tester.pumpAndSettle();
  }

  Finder onShelf(String title) => find.descendant(
    of: find.byType(LibraryShelf),
    matching: find.text(title),
  );

  List<String> shelfTitles(WidgetTester tester) => [
    for (final cover in tester.widgetList<BookCover>(
      find.descendant(
        of: find.byType(LibraryShelf),
        matching: find.byType(BookCover),
      ),
    ))
      cover.title,
  ];

  bool chosen(WidgetTester tester, String filter) => tester
      .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, filter))
      .selected;

  group('each shelf tile follows only its own book', () {
    testLibrary('a playing tick redraws only the playing book’s tile', (
      tester,
    ) async {
      await showLibrary(tester);
      await playFirstFrost(tester);
      final rebuilt = await _rebuiltDuring(() async {
        engine.emit(0, 45000, playing: true);
        await tester.pump();
      });
      expect(_coversBelow<LibraryShelf>(rebuilt), ['First Frost']);
    });

    testLibrary(
      'a playing tick asks no other book for its listening progress',
      (tester) async {
        await showLibrary(tester);
        await playFirstFrost(tester);
        playback.asked.clear();
        engine.emit(0, 45000, playing: true);
        await tester.pump();
        expect(
          playback.asked.where((id) => id != audio(book('First Frost')).id),
          isEmpty,
        );
      },
    );

    testLibrary(
      'a download notice for one edition redraws only its book’s tile',
      (tester) async {
        await showLibrary(tester);
        final tide = audio(book('Tidewater'));
        final rebuilt = await _rebuiltDuring(() async {
          downloads.set(
            tide,
            const EditionDownload(phase: DownloadPhase.downloaded),
          );
          await tester.pump();
        });
        expect(_coversBelow<LibraryShelf>(rebuilt), ['Tidewater']);
      },
    );

    testLibrary(
      'a download notice for one edition asks no other book for its download state',
      (tester) async {
        await showLibrary(tester);
        final tide = audio(book('Tidewater'));
        downloads.asked.clear();
        downloads.set(
          tide,
          const EditionDownload(phase: DownloadPhase.downloading, bytes: 10),
        );
        await tester.pump();
        expect(downloads.asked.where((id) => id != tide.id), isEmpty);
      },
    );

    testLibrary('a refresh that changes nothing redraws no tile and no shelf', (
      tester,
    ) async {
      await showLibrary(tester);
      final rebuilt = await _rebuiltDuring(() async {
        await finish(tester, catalog.refresh());
        await tester.pump();
      });
      final types = {for (final element in rebuilt) element.widget.runtimeType};
      expect(types, isNot(contains(BookCover)));
      expect(types, isNot(contains(RefreshIndicator)));
      expect(types, isNot(contains(ChoiceChip)));
    });
  });

  group('when Jellyfin cannot be reached', () {
    testLibrary(
      'the shelf shows only downloaded books and keeps the chosen filter',
      (tester) async {
        await showLibrary(tester);
        await tester.tap(find.text('Ebooks'));
        await tester.pumpAndSettle();
        expect(shelfTitles(tester), ['Inkwell']);
        downloads.set(
          audio(book('Tidewater')),
          const EditionDownload(phase: DownloadPhase.downloaded),
        );
        client.failure = const CatalogFailure(CatalogFailureKind.unavailable);
        await finish(tester, catalog.refresh());
        await tester.pumpAndSettle();
        expect(shelfTitles(tester), ['Tidewater']);
        expect(chosen(tester, 'Ebooks'), isTrue);
        expect(chosen(tester, 'Downloaded'), isFalse);
      },
    );

    testLibrary(
      'a later refresh that reaches Jellyfin brings the chosen shelf back',
      (tester) async {
        await showLibrary(tester);
        await tester.tap(find.text('Ebooks'));
        await tester.pumpAndSettle();
        downloads.set(
          audio(book('Tidewater')),
          const EditionDownload(phase: DownloadPhase.downloaded),
        );
        client.failure = const CatalogFailure(CatalogFailureKind.unavailable);
        await finish(tester, catalog.refresh());
        await tester.pumpAndSettle();
        client.failure = null;
        await finish(tester, catalog.refresh());
        await tester.pumpAndSettle();
        expect(shelfTitles(tester), ['Inkwell']);
        expect(chosen(tester, 'Ebooks'), isTrue);
      },
    );

    testLibrary('a book downloaded while offline joins the shelf', (
      tester,
    ) async {
      await showLibrary(tester);
      client.failure = const CatalogFailure(CatalogFailureKind.unavailable);
      await finish(tester, catalog.refresh());
      await tester.pumpAndSettle();
      expect(shelfTitles(tester), isEmpty);
      expect(find.text('No downloaded books yet.'), findsOneWidget);
      downloads.set(
        audio(book('First Frost')),
        const EditionDownload(phase: DownloadPhase.downloaded),
      );
      await tester.pumpAndSettle();
      expect(shelfTitles(tester), ['First Frost']);
    });

    const notice = 'Cannot reach Jellyfin. Showing downloaded books.';

    testLibrary('the library says so and offers Retry', (tester) async {
      await showLibrary(tester);
      client.failure = const CatalogFailure(CatalogFailureKind.unavailable);
      await finish(tester, catalog.refresh());
      await tester.pumpAndSettle();
      expect(find.text(notice), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
    });

    testLibrary(
      'Retry refreshes, and a refresh that reaches Jellyfin clears the notice and brings the full library back',
      (tester) async {
        await showLibrary(tester);
        client.failure = const CatalogFailure(CatalogFailureKind.unavailable);
        await finish(tester, catalog.refresh());
        await tester.pumpAndSettle();
        expect(shelfTitles(tester), isEmpty);
        client.failure = null;
        await tester.tap(find.widgetWithText(TextButton, 'Retry'));
        await finish(tester, refreshEnded());
        await tester.pumpAndSettle();
        expect(find.text(notice), findsNothing);
        expect(find.widgetWithText(TextButton, 'Retry'), findsNothing);
        expect(shelfTitles(tester), hasLength(4));
      },
    );

    testLibrary('the notice stays while a retry runs', (tester) async {
      await showLibrary(tester);
      client.failure = const CatalogFailure(CatalogFailureKind.unavailable);
      await finish(tester, catalog.refresh());
      await tester.pumpAndSettle();
      client.failure = null;
      client.pendingCatalog = Completer();
      await tester.tap(find.widgetWithText(TextButton, 'Retry'));
      await tester.pump();
      expect(catalog.statusNotifier.value.refreshing, isTrue);
      expect(find.text(notice), findsOneWidget);
      client.pendingCatalog!.complete(client.entries);
      await finish(tester, refreshEnded());
      await tester.pumpAndSettle();
      expect(find.text(notice), findsNothing);
    });
  });

  group('a refresh', () {
    Finder progressLine() => find.byWidgetPredicate(
      (widget) => widget is LinearProgressIndicator && widget.value == null,
    );

    testLibrary('that ends within 1.5 seconds shows no progress line', (
      tester,
    ) async {
      await showLibrary(tester);
      client.pendingCatalog = Completer();
      final refreshing = catalog.refresh();
      await tester.pump();
      expect(progressLine(), findsNothing);
      await tester.pump(const Duration(milliseconds: 1400));
      expect(progressLine(), findsNothing);
      client.pendingCatalog!.complete(client.entries);
      await finish(tester, refreshing);
      await tester.pump(const Duration(seconds: 1));
      expect(progressLine(), findsNothing);
    });

    testLibrary(
      'that runs longer than 1.5 seconds shows a progress line until it ends',
      (tester) async {
        await showLibrary(tester);
        client.pendingCatalog = Completer();
        final refreshing = catalog.refresh();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1400));
        expect(progressLine(), findsNothing);
        await tester.pump(const Duration(milliseconds: 200));
        expect(progressLine(), findsOneWidget);
        client.pendingCatalog!.complete(client.entries);
        await finish(tester, refreshing);
        await tester.pump();
        expect(progressLine(), findsNothing);
      },
    );

    testLibrary(
      'in the background that Jellyfin answers but that fails shows nothing',
      (tester) async {
        await showLibrary(tester);
        client.failure = const CatalogFailure(CatalogFailureKind.incomplete);
        await finish(tester, catalog.refresh());
        await tester.pumpAndSettle();
        expect(find.byType(StatusMessage), findsNothing);
        expect(shelfTitles(tester), hasLength(4));
      },
    );

    testLibrary(
      'that the person pulls for and that Jellyfin answers but that fails shows its failure',
      (tester) async {
        await showLibrary(tester);
        client.failure = const CatalogFailure(CatalogFailureKind.incomplete);
        await tester.fling(
          find.descendant(
            of: find.byType(LibraryShelf),
            matching: find.byType(CustomScrollView),
          ),
          const Offset(0, 400),
          1000,
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await finish(tester, refreshEnded());
        await tester.pumpAndSettle();
        expect(
          find.text(
            'The catalog changed or the refresh was incomplete. Try again.',
          ),
          findsOneWidget,
        );
      },
    );
  });

  group('the pages own navigation', () {
    testLibrary(
      'a tapped shelf entry reports its item and opens nothing itself',
      (tester) async {
        final opened = <ShelfItem>[];
        await tester.pumpWidget(
          MaterialApp(
            navigatorObservers: [pushes],
            home: Scaffold(
              body: CustomScrollView(
                slivers: [
                  ShelfEntries(
                    services: services,
                    items: [ShelfBook(book('First Frost'))],
                    onOpen: opened.add,
                  ),
                ],
              ),
            ),
          ),
        );
        pushes.routes.clear();
        await tester.tap(find.text('First Frost'));
        await tester.pumpAndSettle();
        expect(opened, [
          isA<ShelfBook>().having(
            (item) => item.book.title,
            'title',
            'First Frost',
          ),
        ]);
        expect(pushes.routes, isEmpty);
      },
    );

    testLibrary('tapping a book on the shelf opens its page', (tester) async {
      await showLibrary(tester);
      await tester.tap(onShelf('First Frost'));
      await tester.pumpAndSettle();
      expect(find.byType(BookPage), findsOneWidget);
    });

    testLibrary('tapping a series on the shelf opens the series in order', (
      tester,
    ) async {
      await showLibrary(tester);
      await tester.tap(onShelf('The Orchard Cycle'));
      await tester.pumpAndSettle();
      expect(find.byType(SeriesPage), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(SeriesPage),
          matching: find.text('Windfall'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(BookPage), findsOneWidget);
    });

    testLibrary('tapping a search result opens its book', (tester) async {
      await showLibrary(tester);
      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'tide');
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(SearchPage),
          matching: find.text('Tidewater'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(BookPage), findsOneWidget);
    });
  });

  group('the layout toggle', () {
    testWidgets('reports the chosen view and writes nothing', (tester) async {
      final readOnly = LibraryLayout(_ReadOnlyLayoutStore());
      addTearDown(readOnly.dispose);
      final chosenViews = <LibraryView>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LayoutToggle(
              layout: LibraryServices(
                catalog: catalog,
                layout: readOnly,
                onReaderNightChanged: (_) {},
              ).shelfLayout,
              onChanged: chosenViews.add,
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Show as list'));
      await tester.pumpAndSettle();
      expect(chosenViews, [LibraryView.list]);
      expect(readOnly.view, LibraryView.grid);
    });

    testLibrary('the library tab saves the view that its toggle reports', (
      tester,
    ) async {
      await showLibrary(tester);
      await tester.tap(find.byTooltip('Show as grid'));
      await tester.pumpAndSettle();
      expect(layout.view, LibraryView.grid);
    });
  });

  group('library pages follow the library, not the refresh', () {
    testLibrary('a refresh that changes nothing redraws no search result', (
      tester,
    ) async {
      await showLibrary(tester);
      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'r');
      await tester.pumpAndSettle();
      final rebuilt = await _rebuiltDuring(() async {
        await finish(tester, catalog.refresh());
        await tester.pump();
      });
      expect(_coversBelow<SearchPage>(rebuilt), isEmpty);
    });

    testLibrary(
      'a refresh that changes nothing redraws no book of an open series',
      (tester) async {
        await showLibrary(tester);
        await tester.tap(onShelf('The Orchard Cycle'));
        await tester.pumpAndSettle();
        final rebuilt = await _rebuiltDuring(() async {
          await finish(tester, catalog.refresh());
          await tester.pump();
        });
        expect(_coversBelow<SeriesPage>(rebuilt), isEmpty);
      },
    );

    testLibrary(
      'search results follow a library that changes under the query',
      (tester) async {
        await showLibrary(tester);
        await tester.tap(find.byTooltip('Search'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'frost');
        await tester.pumpAndSettle();
        Finder result(String title) => find.descendant(
          of: find.byType(SearchPage),
          matching: find.text(title),
        );
        expect(result('First Frost'), findsOneWidget);
        expect(result('Frost Fair'), findsNothing);
        client.entries = [
          ...client.entries,
          entry('fair', title: 'Frost Fair', source: 'fair'),
        ];
        await finish(tester, catalog.refresh());
        await tester.pumpAndSettle();
        expect(result('Frost Fair'), findsOneWidget);
      },
    );
  });

  group('the shelf filter chips', () {
    /// Shows the filter chips with [selected] chosen, and returns the
    /// filters that they report.
    Future<List<ShelfFilter>> showChips(
      WidgetTester tester,
      ShelfFilter selected,
    ) async {
      final reported = <ShelfFilter>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: bookfinTheme(Brightness.light),
          home: Scaffold(
            body: ShelfFilterChips(selected: selected, onChanged: reported.add),
          ),
        ),
      );
      return reported;
    }

    bool marked(WidgetTester tester, String label) => tester
        .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label))
        .selected;

    testWidgets('mark the chosen filter and no other', (tester) async {
      await showChips(tester, ShelfFilter.ebooks);
      expect(marked(tester, 'Ebooks'), isTrue);
      for (final label in ['All', 'Audio', 'Downloaded']) {
        expect(marked(tester, label), isFalse, reason: label);
      }
    });

    testWidgets('report a tapped filter and leave the choice to their owner', (
      tester,
    ) async {
      final reported = await showChips(tester, ShelfFilter.all);
      await tester.tap(find.text('Audio'));
      await tester.pumpAndSettle();
      expect(reported, [ShelfFilter.audio]);
      expect(marked(tester, 'All'), isTrue);
      expect(marked(tester, 'Audio'), isFalse);
    });
  });
}
