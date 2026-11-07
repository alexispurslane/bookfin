import 'package:bookfin/catalog/glass.dart' show CoverGlass;
import 'package:bookfin/reader/screen.dart';
import 'package:bookfin/reader/session.dart';
import 'package:bookfin/foundation/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_epub_viewer/publication.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback/playback_test.dart' show account, LocalFiles, MemoryResume;
import 'publication_test.dart' show epub;
import 'session_test.dart' show source, edition, book, visible;

void main() {
  testWidgets(
    'chapter and progress follow visible pages, including after restore',
    (tester) async {
      final downloads = LocalFiles()
        ..files[source.key] = Uri.file('/verified.epub');
      final reader = ReaderSession(
        downloads: downloads,
        store: MemoryResume(),
        load: (_) async => Publication.admit(epub()),
      );
      await reader.bind(account(), [book]);
      await reader.open(book, edition);
      final port = ControlPort();
      reader.attach(reader.token, port, []);
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(reader: reader, onNightChanged: (_) {}),
        ),
      );
      expect(find.textContaining('Page progress unavailable'), findsOneWidget);
      reader.acceptVisible(
        reader.token,
        ReadingLocation.fromJson({
          ...visible.toJson(),
          'chapter': 'River heading',
          'page': 2,
          'pages': 8,
        }),
      );
      await reader.addBookmark(title: 'River mark');
      final bookmark = reader.bookmarks.single;
      await tester.pumpAndSettle();
      expect(find.text('River heading · Page 2 of 8'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        .25,
      );
      reader.acceptVisible(
        reader.token,
        ReadingLocation.fromJson({
          ...visible.toJson(),
          'chapter': 'The bridge',
          'page': 3,
          'pages': 4,
        }),
      );
      await tester.pumpAndSettle();
      expect(find.text('The bridge · Page 3 of 4'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        .75,
      );
      await reader.restoreBookmark(bookmark.id);
      await tester.pumpAndSettle();
      expect(port.destinations.single.cfi, visible.cfi);
      expect(find.text('The bridge · Page 3 of 4'), findsOneWidget);
      reader.acceptVisible(
        reader.token,
        ReadingLocation.fromJson({
          ...visible.toJson(),
          'chapter': 'River heading',
          'page': 1,
          'pages': 5,
        }),
      );
      await tester.pumpAndSettle();
      expect(find.text('River heading · Page 1 of 5'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        .2,
      );
      reader.acceptVisible(reader.token, visible);
      await tester.pumpAndSettle();
      expect(find.textContaining('Page progress unavailable'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await tester.pumpWidget(const SizedBox());
      reader.dispose();
      downloads.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  /// Opens the reader on [book] at a visible place, with one untitled
  /// bookmark there, and shows its bookmarks panel.
  Future<ReaderSession> openBookmarks(
    WidgetTester tester, {
    ControlPort? port,
  }) async {
    final downloads = LocalFiles()
      ..files[source.key] = Uri.file('/verified.epub');
    final reader = ReaderSession(
      downloads: downloads,
      store: MemoryResume(),
      load: (_) async => Publication.admit(epub()),
    );
    addTearDown(() {
      reader.dispose();
      downloads.dispose();
    });
    await reader.bind(account(), [book]);
    await reader.open(book, edition);
    reader.attach(reader.token, port ?? ControlPort(), []);
    reader.acceptVisible(reader.token, visible);
    await reader.addBookmark();
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [if (port != null) PopLog(port.log)],
        home: ReaderScreen(reader: reader, onNightChanged: (_) {}),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Reading bookmarks'));
    await tester.pumpAndSettle();
    return reader;
  }

  testWidgets(
    'an untitled reading bookmark names the day and time it was saved',
    (tester) async {
      final reader = await openBookmarks(tester);
      final saved = reader.bookmarks.single.createdAt.toLocal();
      final time = const DefaultMaterialLocalizations().formatTimeOfDay(
        TimeOfDay.fromDateTime(saved),
      );
      expect(find.text('Today, $time'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets('deleting a reading bookmark asks first and Cancel keeps it', (
    tester,
  ) async {
    final reader = await openBookmarks(tester);
    Future<void> askToDelete() async {
      await tester.tap(find.byTooltip('Edit reading bookmark'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete reading bookmark?'), findsOneWidget);
    }

    await askToDelete();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(reader.bookmarks, hasLength(1));

    await askToDelete();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(reader.bookmarks, isEmpty);
    await tester.pumpWidget(const SizedBox());
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  /// Opens the reader on [book] at a visible place, with [port] as its
  /// navigator and the [contents] entries. [port]'s log also records each
  /// closed route.
  Future<ReaderSession> openReader(
    WidgetTester tester,
    ControlPort port, {
    List<ContentsEntry> contents = const [],
  }) async {
    final downloads = LocalFiles()
      ..files[source.key] = Uri.file('/verified.epub');
    final reader = ReaderSession(
      downloads: downloads,
      store: MemoryResume(),
      load: (_) async => Publication.admit(epub()),
    );
    addTearDown(() {
      reader.dispose();
      downloads.dispose();
    });
    await reader.bind(account(), [book]);
    await reader.open(book, edition);
    reader.attach(reader.token, port, contents);
    reader.acceptVisible(reader.token, visible);
    await tester.pumpWidget(
      MaterialApp(
        theme: bookfinTheme(Brightness.light),
        navigatorObservers: [PopLog(port.log)],
        home: ReaderScreen(reader: reader, onNightChanged: (_) {}),
      ),
    );
    await tester.pumpAndSettle();
    return reader;
  }

  testWidgets(
    'choosing a contents entry closes the sheet, then goes to that place',
    (tester) async {
      final port = ControlPort();
      await openReader(
        tester,
        port,
        contents: const [
          ContentsEntry('River heading', 'one.xhtml#start'),
          ContentsEntry('The bridge', 'two.xhtml'),
        ],
      );
      await tester.tap(find.byTooltip('Contents'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('The bridge'));
      await tester.pumpAndSettle();
      expect(port.log, ['closed a route', 'contents two.xhtml']);
      expect(find.text('The bridge'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets(
    'tapping a reading bookmark closes the sheet and returns to its place',
    (tester) async {
      final port = ControlPort();
      await openBookmarks(tester, port: port);
      await tester.tap(find.text('Saved reading place'));
      await tester.pumpAndSettle();
      expect(port.destinations.single.cfi, visible.cfi);
      expect(port.log, contains('closed a route'));
      expect(find.text('Saved reading place'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets(
    'editing a reading bookmark opens the shared bookmark editor, and the '
    'reader saves what it returns',
    (tester) async {
      final reader = await openBookmarks(tester);
      Future<void> edit({required String title, required String button}) async {
        await tester.tap(find.byTooltip('Edit reading bookmark'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Edit title and note'));
        await tester.pumpAndSettle();
        expect(find.text('Edit reading bookmark'), findsOneWidget);
        // The reader keeps its own plain look, so its editor is no glass pane.
        expect(
          find.ancestor(
            of: find.text('Edit reading bookmark'),
            matching: find.byType(CoverGlass),
          ),
          findsNothing,
        );
        expect(
          find.ancestor(
            of: find.text('Edit reading bookmark'),
            matching: find.byType(AlertDialog),
          ),
          findsOneWidget,
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Title (optional)'),
          title,
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Note (optional)'),
          'Where the road bends',
        );
        await tester.tap(find.text(button));
        await tester.pumpAndSettle();
      }

      await edit(title: 'River mark', button: 'Save bookmark');
      expect(reader.bookmarks.single.title, 'River mark');
      expect(reader.bookmarks.single.note, 'Where the road bends');
      expect(find.text('River mark'), findsOneWidget, reason: 'the panel row');

      await edit(title: 'Discarded', button: 'Cancel');
      expect(reader.bookmarks.single.title, 'River mark');
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets(
    'choosing a search hit goes to it, and the search ends with the sheet',
    (tester) async {
      final port = ControlPort()
        ..report = const SearchReport([SearchHit(visible, 'river excerpt')]);
      final reader = await openReader(tester, port);
      await tester.tap(find.byTooltip('Search book'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'river');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      await tester.tap(find.text('river excerpt'));
      await tester.pumpAndSettle();
      expect(port.destinations.single.cfi, visible.cfi);
      expect(port.log, ['closed a route', 'cancel search']);
      expect(reader.hits, isEmpty);
      expect(find.text('river excerpt'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets(
    'closing search with its button or a tap outside the sheet ends the '
    'search',
    (tester) async {
      final port = ControlPort();
      await openReader(tester, port);
      await tester.tap(find.byTooltip('Search book'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Cancel search'));
      await tester.pumpAndSettle();
      expect(port.log, ['closed a route', 'cancel search']);

      port.log.clear();
      await tester.tap(find.byTooltip('Search book'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(port.log, ['closed a route', 'cancel search']);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets(
    'the reader panels open on the plain sheet that the reader always had',
    (tester) async {
      await openReader(
        tester,
        ControlPort(),
        contents: const [ContentsEntry('River heading', 'one.xhtml')],
      );
      final context = tester.element(find.byType(ReaderScreen));
      final surface = Theme.of(context).bottomSheetTheme.backgroundColor;
      for (final panel in ['Contents', 'Search book', 'Reading bookmarks']) {
        await tester.tap(find.byTooltip(panel));
        await tester.pumpAndSettle();
        final sheet = find.byType(BottomSheet);
        expect(tester.widget<BottomSheet>(sheet).showDragHandle, isTrue);
        expect(
          tester
              .widget<Material>(
                find
                    .descendant(of: sheet, matching: find.byType(Material))
                    .first,
              )
              .color,
          surface,
          reason: '$panel sheet surface',
        );
        expect(find.byType(CoverGlass), findsNothing, reason: panel);
        await tester.tapAt(const Offset(20, 20));
        await tester.pumpAndSettle();
      }
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets(
    'production reading controls save a bookmark and change text size',
    (tester) async {
      final downloads = LocalFiles()
        ..files[source.key] = Uri.file('/verified.epub');
      final reader = ReaderSession(
        downloads: downloads,
        store: MemoryResume(),
        load: (_) async => Publication.admit(epub()),
      );
      await reader.bind(account(), [book]);
      await reader.open(book, edition);
      reader.attach(reader.token, ControlPort(), [
        const ContentsEntry('River heading', 'one.xhtml#start'),
      ]);
      reader.acceptVisible(reader.token, visible);
      await tester.pumpWidget(
        MaterialApp(
          theme: bookfinTheme(Brightness.light),
          home: ReaderScreen(reader: reader, onNightChanged: (_) {}),
        ),
      );
      await tester.tap(find.byTooltip('Larger text'));
      await tester.pumpAndSettle();
      expect(reader.fontSize, 22);
      await tester.tap(find.byTooltip('Bookmark this place'));
      await tester.pumpAndSettle();
      expect(reader.bookmarks, hasLength(1));
      await tester.tap(find.byTooltip('Contents'));
      await tester.pumpAndSettle();
      expect(find.text('River heading'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      reader.dispose();
      downloads.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets(
    'incomplete search is visible and large controls do not overflow',
    (tester) async {
      final downloads = LocalFiles()
        ..files[source.key] = Uri.file('/verified.epub');
      final reader = ReaderSession(
        downloads: downloads,
        store: MemoryResume(),
        load: (_) async => Publication.admit(epub()),
      );
      await reader.bind(account(), [book]);
      await reader.open(book, edition);
      reader.attach(reader.token, ControlPort(), []);
      await tester.pumpWidget(
        MaterialApp(
          theme: bookfinTheme(Brightness.light),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: ReaderScreen(reader: reader, onNightChanged: (_) {}),
        ),
      );
      await tester.tap(find.byTooltip('Search book'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'river');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(
        find.text('Search is incomplete. Chapter failed.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      reader.dispose();
      downloads.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );
}

/// Adds 'closed a route' to [log] each time a route closes.
class PopLog extends NavigatorObserver {
  PopLog(this.log);
  final List<String> log;
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      log.add('closed a route');
}

class ControlPort implements NavigatorPort {
  final destinations = <ReadingLocation>[];

  /// What the port did, in order, apart from [destinations].
  final log = <String>[];

  /// What a search finds.
  SearchReport report = const SearchReport(
    [],
    error: 'Search is incomplete. Chapter failed.',
  );
  @override
  Future<void> cancelSearch(int request) async => log.add('cancel search');
  @override
  Future<void> configure({
    required double fontSize,
    required bool night,
  }) async {}
  @override
  Future<void> contents(String href) async => log.add('contents $href');
  @override
  Future<void> display(ReadingLocation location) async {
    destinations.add(location);
  }

  @override
  Future<void> move(bool forward) async {}
  @override
  Future<SearchReport> search(String query, int request) async => report;
}
