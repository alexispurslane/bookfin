import 'package:bookfin/catalog/book_cover.dart';
import 'package:bookfin/catalog/book_page.dart';
import 'package:bookfin/catalog/controller.dart';
import 'package:bookfin/catalog/jellyfin.dart';
import 'package:bookfin/catalog/layout.dart';
import 'package:bookfin/catalog/library_services.dart';
import 'package:bookfin/catalog/library_view.dart' show SearchPage, SeriesPage;
import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/downloads/downloads.dart';
import 'package:bookfin/downloads/screen.dart';
import 'package:bookfin/foundation/theme.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:bookfin/playback/screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'controller_test.dart'
    show MemoryCatalogStore, MemoryCredentials, FixtureClient;
import 'layout_test.dart' show MemoryLayoutStore;
import 'model_test.dart' show entry;
import '../playback/playback_test.dart'
    show LocalFiles, MemoryResume, TestEngine, account, first, title, recording;
import '../real_time.dart';
import '../downloads/verified_reads.dart';

void main() {
  late _RecordingCatalog catalog;
  late FixtureClient client;
  late StaticDownloads downloads;
  setUp(() async {
    client = FixtureClient(Uri.parse('https://books.example'));
    catalog = _RecordingCatalog(
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
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await finish(
      tester,
      catalog.connect('https://books.example', 'alice', 'password'),
    );
    await finish(tester, catalog.refresh());
    await tester.pumpWidget(
      MaterialApp(
        theme: bookfinTheme(Brightness.light),
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

  testWidgets(
    'removing a download from the book page asks the same question as Downloads',
    (tester) async {
      downloads.state = const EditionDownload(
        phase: DownloadPhase.downloaded,
        bytes: 1000,
        totalBytes: 1000,
        completeFiles: 1,
        totalFiles: 1,
      );
      await showBook(tester);
      // The edition's own controls remove it. Listen plays a downloaded book.
      await tester.tap(find.widgetWithText(TextButton, 'Remove'));
      await tester.pumpAndSettle();
      expect(find.text('Remove download?'), findsOneWidget);
      expect(find.textContaining('pause or switch books'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Remove download'));
      await tester.pumpAndSettle();
      expect(downloads.calls, ['remove']);
    },
  );

  testWidgets(
    'a partial download offers Retry and Remove on the book page and in Downloads',
    (tester) async {
      downloads.state = const EditionDownload(
        phase: DownloadPhase.partial,
        bytes: 400,
        totalBytes: 1000,
        totalFiles: 1,
      );
      await showBook(tester);
      // Listen retries the partial download, as everywhere else.
      expect(find.byTooltip('Partial. Retry download'), findsOneWidget);
      expect(find.byTooltip('Download'), findsNothing);
      // The edition's own controls.
      expect(find.widgetWithText(OutlinedButton, 'Retry'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Remove'), findsOneWidget);

      await tester.pumpWidget(
        MaterialApp(
          theme: bookfinTheme(Brightness.light),
          home: Scaffold(
            body: DownloadsPage(downloads: downloads, books: catalog.books),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Retry download'), findsOneWidget);
      expect(find.byTooltip('Remove download'), findsOneWidget);
      expect(find.byTooltip('Download'), findsNothing);
    },
  );

  testWidgets('a failed download retries from the book page button', (
    tester,
  ) async {
    downloads.state = const EditionDownload(
      phase: DownloadPhase.failed,
      totalFiles: 1,
    );
    await showBook(tester);
    await tester.tap(find.byTooltip('Download failed. Retry download'));
    await tester.pumpAndSettle();
    expect(downloads.calls, ['request']);
    expect(find.widgetWithText(TextButton, 'Remove'), findsOneWidget);
  });

  testWidgets('a chapter an hour in reads as hours, minutes and seconds', (
    tester,
  ) async {
    const twoHours = 72000000000;
    client.entries = [
      entry(
        'one',
        fields: {
          'RunTimeTicks': twoHours,
          'MediaSources': [
            {
              'Id': 'source',
              'Container': 'm4b',
              'Size': 1000,
              'RunTimeTicks': twoHours,
            },
          ],
          'Chapters': [
            {'Name': 'Opening', 'StartPositionTicks': 0},
            {'Name': 'Night falls', 'StartPositionTicks': 39000000000},
          ],
        },
      ),
    ];
    await showBook(tester);
    await tester.scrollUntilVisible(find.byType(ExpansionTile), 200);
    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Night falls'),
        matching: find.text('1:05:00'),
      ),
      findsOneWidget,
    );
  });

  group('a player opened from a library page', () {
    late LocalFiles files;
    late Playback playback;
    setUp(() async {
      files = LocalFiles();
      playback = Playback(
        downloads: files,
        engine: TestEngine(),
        store: MemoryResume(),
      );
      await playback.bind(account(), [title]);
      await playback.open(title, recording, autoplay: false);
    });
    tearDown(() async {
      await playback.close();
      files.dispose();
    });

    /// Opens the player from the mini player on [page] and its More menu.
    Future<void> openMore(WidgetTester tester, Widget page) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(theme: bookfinTheme(Brightness.light), home: page),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Open player'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More player actions'));
      await tester.pumpAndSettle();
    }

    LibraryServices services() => LibraryServices(
      catalog: catalog,
      layout: LibraryLayout(MemoryLayoutStore()),
      onReaderNightChanged: (_) {},
      playback: playback,
    );

    testWidgets('on search offers the book details', (tester) async {
      await finish(
        tester,
        catalog.connect('https://books.example', 'alice', 'password'),
      );
      await openMore(tester, SearchPage(services: services()));
      expect(find.text('Book details'), findsOneWidget);
    });

    testWidgets('on a book page offers the book details', (tester) async {
      await finish(
        tester,
        catalog.connect('https://books.example', 'alice', 'password'),
      );
      await finish(tester, catalog.refresh());
      await openMore(
        tester,
        BookPage(services: services(), bookId: catalog.books.single.id),
      );
      expect(find.text('Book details'), findsOneWidget);
    });

    testWidgets('a playback problem reads as an error on the book page', (
      tester,
    ) async {
      await finish(
        tester,
        catalog.connect('https://books.example', 'alice', 'password'),
      );
      await finish(tester, catalog.refresh());
      await tester.runAsync(() async {
        files.files.clear();
        await playback.bind(catalog.session, catalog.books);
        final book = catalog.books.single;
        await playback.open(book, book.editions.single);
      });
      final problem = playback.statusNotifier.value.actionNotice!.message;
      await tester.pumpWidget(
        MaterialApp(
          theme: bookfinTheme(Brightness.light),
          home: BookPage(services: services(), bookId: catalog.books.single.id),
        ),
      );
      await tester.pumpAndSettle();
      final shown = tester.renderObject<RenderParagraph>(find.text(problem));
      expect(
        shown.text.style?.color,
        Theme.of(tester.element(find.text(problem))).colorScheme.error,
      );
    });
  });

  group('the book page follows only its own state', () {
    late TestEngine engine;
    late _Playback playback;
    late LibraryServices services;
    late List<String> log;
    setUp(() async {
      client.entries = [
        _hour('frost', 'First Frost'),
        _hour('tide', 'Tidewater'),
      ];
      await catalog.connect('https://books.example', 'alice', 'password');
      await catalog.refresh();
      engine = TestEngine();
      playback = _Playback(
        downloads: downloads,
        engine: engine,
        store: MemoryResume(),
      );
      log = playback.log;
      services = LibraryServices(
        catalog: catalog,
        layout: LibraryLayout(MemoryLayoutStore()),
        onReaderNightChanged: (_) {},
        downloads: downloads,
        playback: playback,
      );
    });

    Book book(String title) =>
        catalog.books.singleWhere((book) => book.title == title);
    Edition audio(String title) => book(title).editions.single;

    /// A widget test whose player closes before fake time ends, because
    /// closing waits on work that fake time does not run.
    void testPage(
      String description,
      Future<void> Function(WidgetTester) body,
    ) => testWidgets(description, (tester) async {
      try {
        await body(tester);
      } finally {
        await finish(tester, playback.close());
      }
    });

    /// Shows the page of First Frost, with the player bound to the library.
    Future<void> showFirstFrost(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: bookfinTheme(Brightness.light),
          navigatorObservers: [_Pushes(log)],
          home: BookPage(services: services, bookId: book('First Frost').id),
        ),
      );
      await finish(tester, playback.bind(catalog.session, catalog.books));
      await tester.pumpAndSettle();
      log.clear();
    }

    /// Opens [title] in the player and plays one tick, so that later ticks
    /// change only the position.
    Future<void> play(WidgetTester tester, String title) async {
      await finish(
        tester,
        playback.open(book(title), audio(title), autoplay: false),
      );
      engine.emit(0, 600000, playing: true);
      await tester.pumpAndSettle();
    }

    testPage('a playing tick of another book redraws nothing on the page', (
      tester,
    ) async {
      await showFirstFrost(tester);
      await play(tester, 'Tidewater');
      final rebuilt = await _rebuiltDuring(() async {
        engine.emit(0, 660000, playing: true);
        await tester.pump();
      });
      expect(_onPage(rebuilt), isEmpty);
    });

    testPage('a playing tick of this book redraws only its progress', (
      tester,
    ) async {
      await showFirstFrost(tester);
      await play(tester, 'First Frost');
      expect(find.text('16% · 50 m left'), findsOneWidget);
      final rebuilt = _onPage(
        await _rebuiltDuring(() async {
          engine.emit(0, 1200000, playing: true);
          await tester.pump();
        }),
      );
      expect(find.text('33% · 40 m left'), findsOneWidget);
      expect(
        rebuilt.map((element) => element.widget),
        contains(isA<ProgressLine>()),
      );
      expect(rebuilt.where((element) => !_onlyProgress(element)), isEmpty);
    });

    testPage(
      'a download notice for this book’s edition redraws only that edition’s download controls',
      (tester) async {
        await showFirstFrost(tester);
        final frost = audio('First Frost');
        downloads.set(
          frost,
          const EditionDownload(
            phase: DownloadPhase.downloading,
            bytes: 10,
            totalBytes: 1000,
            totalFiles: 1,
          ),
        );
        await tester.pump();
        final rebuilt = _onPage(
          await _rebuiltDuring(() async {
            downloads.set(
              frost,
              const EditionDownload(
                phase: DownloadPhase.downloading,
                bytes: 20,
                totalBytes: 1000,
                totalFiles: 1,
              ),
            );
            await tester.pump();
          }),
        );
        expect(rebuilt, isNotEmpty);
        expect(
          rebuilt.where((element) => !_inDownloadControls(element, frost)),
          isEmpty,
        );
      },
    );

    testPage('a refresh that changes nothing redraws nothing on the page', (
      tester,
    ) async {
      await showFirstFrost(tester);
      final rebuilt = await _rebuiltDuring(() async {
        await finish(tester, catalog.refresh());
        await tester.pump();
      });
      expect(_onPage(rebuilt), isEmpty);
    });

    testPage('Listen opens a downloaded edition, then the player', (
      tester,
    ) async {
      downloads.state = const EditionDownload(
        phase: DownloadPhase.downloaded,
        totalFiles: 1,
        completeFiles: 1,
      );
      await showFirstFrost(tester);
      await tester.tap(find.text('Listen'));
      for (var step = 0; step < 100 && !log.contains('push'); step++) {
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump(const Duration(milliseconds: 10));
      }
      await tester.pumpAndSettle();
      expect(log, ['open ${audio('First Frost').id}', 'push']);
      expect(find.byType(PlayerView), findsOneWidget);
    });

    testPage('Separate source asks first and separates only after a yes', (
      tester,
    ) async {
      await showFirstFrost(tester);
      final file = audio('First Frost').files.single;
      // The page scrolls; the mini player below it has a scrollable too.
      // At its end, the page keeps its last button above the mini player.
      final page = find.byType(Scrollable).first;
      Future<void> toEnd() async {
        await tester.drag(page, const Offset(0, -3000));
        await tester.pumpAndSettle();
      }

      Future<void> separate() async {
        await toEnd();
        await tester.tap(find.text('Separate source'));
        await tester.pumpAndSettle();
        expect(find.text('Separate this source?'), findsOneWidget);
      }

      await toEnd();
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();
      await separate();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(catalog.separated, isEmpty);
      await separate();
      await tester.tap(find.widgetWithText(FilledButton, 'Separate'));
      await tester.pumpAndSettle();
      expect(catalog.separated, [file.key]);
    });
  });

  group('the book page finds its place in the library', () {
    setUp(() async {
      client.entries = [
        for (final (index, title) in ['Graft', 'Windfall'].indexed)
          entry(
            title,
            title: title,
            source: title,
            fields: {
              'SeriesName': 'The Orchard Cycle',
              'IndexNumber': index + 1,
            },
          ),
        entry(
          'graft-ink',
          title: 'Graft',
          type: 'Book',
          source: 'graft-ink',
          container: 'epub',
        ),
      ];
      await catalog.connect('https://books.example', 'alice', 'password');
      await catalog.refresh();
    });

    Future<void> showGraft(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: bookfinTheme(Brightness.light),
          home: BookPage(
            services: LibraryServices(
              catalog: catalog,
              layout: LibraryLayout(MemoryLayoutStore()),
              onReaderNightChanged: (_) {},
            ),
            bookId: catalog.books
                .singleWhere(
                  (book) =>
                      book.title == 'Graft' &&
                      book.editions.single.kind == EditionKind.audio,
                )
                .id,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the page links its series and counts its possible matches', (
      tester,
    ) async {
      await showGraft(tester);
      expect(
        find.text('1 possible match · Confirmation required'),
        findsOneWidget,
      );
      await tester.tap(find.text('The Orchard Cycle · Book 1  ›'));
      await tester.pumpAndSettle();
      expect(find.byType(SeriesPage), findsOneWidget);
    });

    testWidgets('a correction of the book shows on its open page', (
      tester,
    ) async {
      await showGraft(tester);
      final graft = catalog.books.firstWhere(
        (book) => book.editions.single.kind == EditionKind.audio,
      );
      await tester.runAsync(
        () => catalog.correctBook(
          graft.id,
          const BookDetails(title: 'Grafting', author: 'A. Writer'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Grafting'), findsOneWidget);
      expect(find.textContaining('The Orchard Cycle'), findsNothing);
    });
  });

  group('the parts of the book page report what happened', () {
    late List<String> log;
    setUp(() => log = []);

    Future<void> show(WidgetTester tester, Widget part) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: bookfinTheme(Brightness.light),
          navigatorObservers: [_Pushes(log)],
          home: Scaffold(body: SingleChildScrollView(child: part)),
        ),
      );
      log.clear();
    }

    testWidgets('the main actions report Listen and Read with their edition', (
      tester,
    ) async {
      await show(
        tester,
        BookActions(
          listening: recording,
          reading: _ebook,
          downloads: null,
          onListen: (edition) => log.add('listen ${edition.id}'),
          onRead: (edition) => log.add('read ${edition.id}'),
          onDownload: (edition, action) => log.add('download ${edition.id}'),
        ),
      );
      await tester.tap(find.text('Listen'));
      await tester.tap(find.text('Read'));
      await tester.pumpAndSettle();
      expect(log, ['listen ${recording.id}', 'read ${_ebook.id}']);
    });

    group('Listen and Read', () {
      late StaticDownloads editions;
      setUp(() => editions = StaticDownloads());

      const downloaded = EditionDownload(
        phase: DownloadPhase.downloaded,
        bytes: 1000,
        totalBytes: 1000,
        completeFiles: 1,
        totalFiles: 1,
      );

      Widget actions() => BookActions(
        listening: recording,
        reading: _ebook,
        downloads: editions,
        onListen: (edition) => log.add('listen ${edition.id}'),
        onRead: (edition) => log.add('read ${edition.id}'),
        onDownload: (edition, action) =>
            log.add('${action.name} ${edition.id}'),
      );

      Finder button(String label) => find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate(
          (widget) => widget is ButtonStyleButton,
        ),
      );

      Finder icon(String label, IconData data) =>
          find.descendant(of: button(label), matching: find.byIcon(data));

      testWidgets('are two buttons of the same kind and the same width', (
        tester,
      ) async {
        editions.state = downloaded;
        await show(tester, actions());

        final listen = tester.widget(button('Listen'));
        final read = tester.widget(button('Read'));
        expect(listen.runtimeType, read.runtimeType);
        expect(
          tester.getSize(button('Listen')).width,
          tester.getSize(button('Read')).width,
        );
        expect(find.byType(DownloadButton), findsNothing);
      });

      testWidgets('play and open downloaded editions, each with its own icon', (
        tester,
      ) async {
        editions.state = downloaded;
        await show(tester, actions());

        expect(
          find.descendant(
            of: button('Listen'),
            matching: find.byType(PlayStateIcon),
          ),
          findsOneWidget,
        );
        expect(icon('Read', Icons.menu_book_outlined), findsOneWidget);
        expect(find.byIcon(Icons.download_rounded), findsNothing);
        await tester.tap(button('Listen'));
        await tester.tap(button('Read'));
        await tester.pumpAndSettle();
        expect(log, ['listen ${recording.id}', 'read ${_ebook.id}']);
      });

      testWidgets('show a download icon on each edition that is not '
          'downloaded, and a tap downloads that edition', (tester) async {
        editions.set(recording, downloaded);
        editions.set(_ebook, const EditionDownload(totalFiles: 1));
        await show(tester, actions());

        expect(
          find.descendant(
            of: button('Listen'),
            matching: find.byType(PlayStateIcon),
          ),
          findsOneWidget,
        );
        expect(icon('Read', Icons.download_rounded), findsOneWidget);
        await tester.tap(button('Read'));
        await tester.pumpAndSettle();
        expect(log, ['request ${_ebook.id}']);
      });

      testWidgets('show a download icon on both when neither edition is '
          'downloaded', (tester) async {
        editions.state = const EditionDownload(totalFiles: 1);
        await show(tester, actions());

        expect(icon('Listen', Icons.download_rounded), findsOneWidget);
        expect(icon('Read', Icons.download_rounded), findsOneWidget);
        await tester.tap(button('Listen'));
        await tester.pumpAndSettle();
        expect(log, ['request ${recording.id}']);
      });

      testWidgets('show the progress of a download, and a tap cancels it', (
        tester,
      ) async {
        editions.set(recording, downloaded);
        editions.set(
          _ebook,
          const EditionDownload(
            phase: DownloadPhase.downloading,
            bytes: 300,
            totalBytes: 1000,
            totalFiles: 1,
          ),
        );
        await show(tester, actions());

        expect(
          find.descendant(
            of: button('Read'),
            matching: find.byType(CircularProgressIndicator),
          ),
          findsOneWidget,
        );
        await tester.tap(button('Read'));
        await tester.pump();
        expect(log, ['cancel ${_ebook.id}']);
      });

      testWidgets('retry a failed download', (tester) async {
        editions.set(recording, downloaded);
        editions.set(
          _ebook,
          const EditionDownload(phase: DownloadPhase.failed, totalFiles: 1),
        );
        await show(tester, actions());

        expect(icon('Read', Icons.refresh_rounded), findsOneWidget);
        await tester.tap(button('Read'));
        await tester.pumpAndSettle();
        expect(log, ['retry ${_ebook.id}']);
      });

      testWidgets('turn into the downloaded action when the download ends', (
        tester,
      ) async {
        editions.set(recording, downloaded);
        editions.set(_ebook, const EditionDownload(totalFiles: 1));
        await show(tester, actions());

        editions.set(_ebook, downloaded);
        await tester.pump();

        expect(icon('Read', Icons.menu_book_outlined), findsOneWidget);
        await tester.tap(button('Read'));
        await tester.pumpAndSettle();
        expect(log, ['read ${_ebook.id}']);
      });
    });

    testWidgets(
      'an edition panel reports Listen, file order and Separate source, and asks nothing itself',
      (tester) async {
        await show(
          tester,
          EditionPanel(
            edition: recording,
            downloads: null,
            onListen: () => log.add('listen'),
            onOrderFiles: () => log.add('order files'),
            onSeparate: (file) => log.add('separate ${file.key}'),
            onDownload: (action) => log.add('download $action'),
          ),
        );
        await tester.tap(find.text('Listen'));
        await tester.tap(find.text('Correct file order'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Part one'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Separate source'));
        await tester.pumpAndSettle();
        expect(find.text('Separate this source?'), findsNothing);
        expect(log, ['listen', 'order files', 'separate ${first.key}']);
      },
    );
  });
}

/// Downloads that report [state] for every edition without a state of its
/// own, and record the changes asked of them.
class StaticDownloads extends Downloads with VerifiedReads {
  StaticDownloads() : super(MediaPolicy());
  EditionDownload state = const EditionDownload();
  final _states = <String, EditionDownload>{};
  final calls = <String>[];

  /// Gives [edition] its own [state], and notifies as a download does.
  void set(Edition edition, EditionDownload state) {
    _states[edition.id] = state;
    notifyListeners();
  }

  @override
  bool get supported => true;
  @override
  Future<void> bind(JellyfinSession? session, List<Book> books) async {}
  @override
  EditionDownload status(Edition edition) => _states[edition.id] ?? state;
  @override
  Future<void> request(Edition edition) async => calls.add('request');
  @override
  Future<void> cancel(Edition edition) async => calls.add('cancel');
  @override
  Future<void> remove(Edition edition) async => calls.add('remove');
  @override
  Future<Uri?> localFile(SourceFile source) async => Uri.file('/fixture.wav');
  @override
  Future<void> get idle async {}
  @override
  void checkInvariants() {}
}

/// A catalog that records the sources it was asked to separate, and keeps
/// its books.
class _RecordingCatalog extends CatalogController {
  _RecordingCatalog({
    required super.credentials,
    required super.store,
    super.clientFactory,
  });
  final separated = <String>[];

  @override
  Future<void> separateEdition(String editionId) async =>
      separated.add(editionId);
}

/// Playback that writes each edition that it opens to [log].
class _Playback extends Playback {
  _Playback({
    required super.downloads,
    required super.engine,
    required super.store,
  });
  final log = <String>[];

  @override
  Future<void> open(Book book, Edition edition, {bool autoplay = true}) {
    log.add('open ${edition.id}');
    return super.open(book, edition, autoplay: autoplay);
  }
}

/// Writes each pushed route to [log].
class _Pushes extends NavigatorObserver {
  _Pushes(this.log);
  final List<String> log;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      log.add('push');
}

/// An audiobook of one hour in one file, with the item id [id].
CatalogEntry _hour(String id, String title) => entry(
  id,
  title: title,
  source: id,
  fields: {
    'RunTimeTicks': 36000000000,
    'MediaSources': [
      {'Id': id, 'Container': 'm4b', 'Size': 1000, 'RunTimeTicks': 36000000000},
    ],
  },
);

const _ebook = Edition(
  id: 'ink:ink',
  kind: EditionKind.text,
  label: 'EPUB',
  files: [
    SourceFile(
      itemId: 'ink',
      displayName: 'Inkwell',
      mediaSourceId: 'ink',
      revision: 'r1',
      durationMs: null,
      container: 'epub',
      sizeBytes: 2000,
    ),
  ],
  memberIds: ['ink:ink'],
);

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

/// The rebuilt widgets of the page itself, without the mini player, which
/// follows the player on its own.
List<Element> _onPage(List<Element> rebuilt) => [
  for (final element in rebuilt)
    if (element.mounted &&
        element.widget is! PlaybackMiniPlayer &&
        element.findAncestorWidgetOfExactType<PlaybackMiniPlayer>() == null)
      element,
];

/// Each widget at or below [element].
Iterable<Widget> _below(Element element) sync* {
  final found = <Widget>[];
  void visit(Element element) {
    found.add(element.widget);
    element.visitChildren(visit);
  }

  visit(element);
  yield* found;
}

/// Whether [element] shows nothing but the listening progress of the book:
/// its percentage and time left, its History button and its line.
bool _onlyProgress(Element element) => _below(element).every(
  (widget) => switch (widget) {
    Text(:final data?) =>
      data.endsWith(' left') || data == 'Finished' || data == 'History',
    StageCover() ||
    BookCover() ||
    DownloadButton() ||
    DownloadControls() => false,
    _ => true,
  },
);

/// Whether [element] is part of the download controls of [edition], of its
/// round download button, or of the main action that follows its download.
bool _inDownloadControls(
  Element element,
  Edition edition,
) => switch (element.widget) {
  DownloadControls(edition: final shown) ||
  DownloadButton(edition: final shown) ||
  EditionAction(edition: final shown) => shown.id == edition.id,
  _ =>
    element.findAncestorWidgetOfExactType<DownloadControls>()?.edition.id ==
            edition.id ||
        element.findAncestorWidgetOfExactType<DownloadButton>()?.edition.id ==
            edition.id ||
        element.findAncestorWidgetOfExactType<EditionAction>()?.edition.id ==
            edition.id,
};
