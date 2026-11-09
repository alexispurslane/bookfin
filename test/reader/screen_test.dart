import 'dart:async';

import 'package:bookfin/catalog/glass.dart' show CoverGlass;
import 'package:bookfin/foundation/theme.dart';
import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/epub/publication.dart';
import 'package:bookfin/reader/epub/viewport.dart';
import 'package:bookfin/reader/screen.dart';
import 'package:bookfin/reader/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback/playback_test.dart' show account, LocalFiles, MemoryResume;
import 'epub/helpers.dart' show loadReaderFont;
import 'native_reader.dart';
import 'publication_test.dart' show epub;
import 'reader_settings.dart';
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
      final navigator = ControlNavigator();
      reader.attachDocument(reader.token, navigator, []);
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(reader: reader, onNightChanged: (_) {}),
        ),
      );
      expect(find.textContaining('Page progress unavailable'), findsOneWidget);
      expect(
        find.byTooltip('Reflow text'),
        findsNothing,
        reason: 'An EPUB has no reflow control.',
      );
      expect(find.byTooltip('Original page'), findsNothing);
      reader.acceptVisible(
        reader.token,
        ReadingLocation.fromJson({
          ...visible.toJson(),
          'chapter': 'River heading',
          'page': 2,
          'pages': 8,
          'progress': .25,
        }),
      );
      await reader.addBookmark(title: 'River mark');
      final bookmark = reader.bookmarks.single;
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('River heading · 25%'), findsOneWidget);
      expect(tester.widget<Slider>(find.byType(Slider)).value, .25);
      reader.acceptVisible(
        reader.token,
        ReadingLocation.fromJson({
          ...visible.toJson(),
          'chapter': 'The bridge',
          'page': 3,
          'pages': 4,
          'progress': .75,
        }),
      );
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('The bridge · 75%'), findsOneWidget);
      expect(tester.widget<Slider>(find.byType(Slider)).value, .75);
      await reader.restoreBookmark(bookmark.id);
      await tester.pumpAndSettle();
      expect(navigator.destinations.single.cfi, visible.cfi);
      expect(find.bySemanticsLabel('The bridge · 75%'), findsOneWidget);
      reader.acceptVisible(
        reader.token,
        ReadingLocation.fromJson({
          ...visible.toJson(),
          'chapter': 'River heading',
          'page': 1,
          'pages': 5,
          'progress': .2,
        }),
      );
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('River heading · 20%'), findsOneWidget);
      expect(tester.widget<Slider>(find.byType(Slider)).value, .2);
      reader.acceptVisible(reader.token, visible);
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel('Chapter 1 · 0%'),
        findsOneWidget,
        reason:
            'A place with no chapter title takes its chapter from the book '
            'map, which lists one chapter for this book without contents.',
      );
      expect(
        tester.widget<Slider>(find.byType(Slider)).value,
        0,
        reason: 'A place with no progress sits at the start of its section.',
      );
      await tester.pumpWidget(const SizedBox());
      reader.dispose();
      downloads.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  /// Opens the reader on [book] at a visible place, with one untitled
  /// bookmark there, and shows the Bookmarks tab of its Contents sheet.
  Future<ReaderSession> openBookmarks(
    WidgetTester tester, {
    ControlNavigator? navigator,
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
    reader.attachDocument(reader.token, navigator ?? ControlNavigator(), []);
    reader.acceptVisible(reader.token, visible);
    await reader.addBookmark();
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [if (navigator != null) PopLog(navigator.log)],
        home: ReaderScreen(reader: reader, onNightChanged: (_) {}),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Contents'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(Tab, 'Bookmarks'));
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

  /// Opens the reader on [book] at a visible place, with [navigator] and the
  /// [contents] entries. [navigator]'s log also records each closed route.
  Future<ReaderSession> openReader(
    WidgetTester tester,
    ControlNavigator navigator, {
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
    reader.attachDocument(reader.token, navigator, contents);
    reader.acceptVisible(reader.token, visible);
    await tester.pumpWidget(
      MaterialApp(
        theme: bookfinTheme(Brightness.light),
        navigatorObservers: [PopLog(navigator.log)],
        home: ReaderScreen(reader: reader, onNightChanged: (_) {}),
      ),
    );
    await tester.pumpAndSettle();
    return reader;
  }

  testWidgets(
    'choosing a contents entry closes the sheet, then goes to that place',
    (tester) async {
      final navigator = ControlNavigator();
      await openReader(
        tester,
        navigator,
        contents: const [
          ContentsEntry('River heading', 'one.xhtml#start'),
          ContentsEntry('The bridge', 'two.xhtml'),
        ],
      );
      await tester.tap(find.byTooltip('Contents'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('The bridge'));
      await tester.pumpAndSettle();
      expect(navigator.log, ['closed a route', 'contents two.xhtml']);
      expect(find.text('The bridge'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets(
    'tapping a reading bookmark closes the sheet and returns to its place',
    (tester) async {
      final navigator = ControlNavigator();
      await openBookmarks(tester, navigator: navigator);
      await tester.tap(find.text('Saved reading place'));
      await tester.pumpAndSettle();
      expect(navigator.destinations.single.cfi, visible.cfi);
      expect(navigator.log, contains('closed a route'));
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
      final navigator = ControlNavigator()
        ..report = ReaderSearchReport([
          ReaderHit(EpubAddress(visible), 'river excerpt'),
        ]);
      final reader = await openReader(tester, navigator);
      await tester.tap(find.byTooltip('Search book'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'river');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      await tester.tap(find.text('river excerpt'));
      await tester.pumpAndSettle();
      expect(navigator.destinations.single.cfi, visible.cfi);
      expect(navigator.log, ['closed a route', 'cancel search']);
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
      final navigator = ControlNavigator();
      await openReader(tester, navigator);
      await tester.tap(find.byTooltip('Search book'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Cancel search'));
      await tester.pumpAndSettle();
      expect(navigator.log, ['closed a route', 'cancel search']);

      navigator.log.clear();
      await tester.tap(find.byTooltip('Search book'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(navigator.log, ['closed a route', 'cancel search']);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets(
    'the reader panels open on the plain sheet that the reader always had',
    (tester) async {
      await openReader(
        tester,
        ControlNavigator(),
        contents: const [ContentsEntry('River heading', 'one.xhtml')],
      );
      final context = tester.element(find.byType(ReaderScreen));
      final surface = Theme.of(context).bottomSheetTheme.backgroundColor;
      for (final panel in ['Contents', 'Search book', 'Reading settings']) {
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
        expect(
          find.descendant(of: sheet, matching: find.byType(CoverGlass)),
          findsNothing,
          reason: panel,
        );
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
      reader.attachDocument(reader.token, ControlNavigator(), [
        const ContentsEntry('River heading', 'one.xhtml#start'),
      ]);
      reader.acceptVisible(reader.token, visible);
      await tester.pumpWidget(
        MaterialApp(
          theme: bookfinTheme(Brightness.light),
          home: ReaderScreen(reader: reader, onNightChanged: (_) {}),
        ),
      );
      await chooseSetting(tester, 'Larger text');
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
      reader.attachDocument(reader.token, ControlNavigator(), []);
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

  group('the native page', () {
    setUpAll(loadReaderFont);

    testWidgets(
      'an EPUB shows the pager\'s page, laid out for the page area',
      (tester) async {
        final reader = await openNative(tester);
        expect(find.byType(EpubViewport), findsOneWidget);
        expect(
          find.textContaining('available in the Android app'),
          findsNothing,
        );
        expect(find.bySemanticsLabel('Laying out the book'), findsNothing);
        final settings = shownOf(reader)!.page.settings;
        final area = tester.getSize(find.byType(EpubViewport));
        expect((settings.width, settings.height), (area.width, area.height));
        expect(
          (reader.visibleAddress! as EpubAddress).location.resource,
          'OPS/text/s0.xhtml',
        );
        await closeNative(tester, reader);
      },
      variant: TargetPlatformVariant({
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
        TargetPlatform.linux,
        TargetPlatform.windows,
      }),
    );

    testWidgets('a swipe to the left shows the next page, and a swipe to the '
        'right shows the page before again', (tester) async {
      final reader = await openNative(tester);
      final first = shownOf(reader)!.page;
      final address = reader.visibleAddress! as EpubAddress;

      await tester.drag(find.byType(EpubViewport), const Offset(-120, 0));
      final next = (await waitForPage(
        tester,
        reader,
        (shown) => !identical(shown.page, first),
      )).page;
      expect(next.section, first.section);
      expect(next.start.compareTo(first.start), greaterThan(0));
      final moved = reader.visibleAddress! as EpubAddress;
      expect(
        moved.location.progress,
        greaterThan(address.location.progress ?? 0),
        reason: 'The next page is the visible place.',
      );

      await tester.drag(find.byType(EpubViewport), const Offset(120, 0));
      final back = (await waitForPage(
        tester,
        reader,
        (shown) => !identical(shown.page, next),
      )).page;
      expect((back.section, back.start), (first.section, first.start));
      await closeNative(tester, reader);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('a tap on a link shows its destination, and the controls '
        'stay', (tester) async {
      final reader = await openNative(tester);
      final pager = reader.pager!;
      final area = tester.getRect(find.byType(EpubViewport));
      Offset? link;
      for (var y = 0.0; y < area.height / 2 && link == null; y += 4) {
        for (var x = 0.0; x < area.width && link == null; x += 8) {
          if (pager.linkAt(Offset(x, y)) != null) link = Offset(x, y);
        }
      }
      expect(link, isNotNull, reason: 'The first page shows the link.');

      await tester.tapAt(area.topLeft + link!);
      await waitForPage(tester, reader, (shown) => shown.page.section == 1);
      await settleReader(
        tester,
        () =>
            (reader.visibleAddress! as EpubAddress).location.resource ==
            'OPS/text/s1.xhtml',
      );
      expect(
        (reader.visibleAddress! as EpubAddress).location.progress,
        greaterThan(.7),
        reason: 'The far shore is near the end of the second chapter.',
      );
      expect(find.byType(ReaderDock), findsOneWidget);
      await closeNative(tester, reader);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  });
}

/// Adds 'closed a route' to [log] each time a route closes.
class PopLog extends NavigatorObserver {
  PopLog(this.log);
  final List<String> log;
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      log.add('closed a route');
}

class ControlNavigator implements DocumentNavigator {
  final destinations = <ReadingLocation>[];

  /// The section and the progress of each seek, in order.
  final seeks = <(int, double)>[];

  /// Whether each seek fails.
  bool failSeeks = false;

  /// What the navigator did, in order, apart from [destinations].
  final log = <String>[];

  /// What a search finds.
  ReaderSearchReport report = const ReaderSearchReport(
    [],
    error: 'Search is incomplete. Chapter failed.',
  );
  @override
  Future<void> cancelSearch(int request) async => log.add('cancel search');
  @override
  Future<void> contents(String href) async => log.add('contents $href');
  @override
  Future<void> display(ReaderAddress address) async {
    destinations.add((address as EpubAddress).location);
  }

  @override
  Future<void> move(bool forward) async {}
  @override
  Future<void> seek(int part, double progress) async {
    if (failSeeks) throw StateError('The seek did not finish.');
    seeks.add((part, progress));
  }

  @override
  Future<ReaderSearchReport> search(String query, int request) async => report;

  /// The section, the progress and the width of each page preview, in
  /// order.
  final previews = <(int, double, double)>[];

  /// Notes each page preview, which then waits for ever.
  @override
  Future<PagePreview> preview(
    BookPlace place,
    double width,
    Future<void> abandon,
  ) {
    previews.add((place.part, place.progress, width));
    return Completer<PagePreview>().future;
  }
}
