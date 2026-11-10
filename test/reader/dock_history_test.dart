// The reader's dock gives ebooks the player's bookmarks, Undo and History:
// a Bookmark tool that reads Bookmarked on a bookmarked page, the player's
// Undo row above the place label after a jump, and a History tool that
// opens the shared History timeline. The reader screen is the controller,
// and every layer over the page is glass.
import 'package:bookfin/catalog/glass.dart' show CoverGlass;
import 'package:bookfin/foundation/theme.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:bookfin/playback/screen.dart' show UndoNotice;
import 'package:bookfin/playback/timeline.dart' show HistoryTimeline;
import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/epub/viewport.dart';
import 'package:bookfin/reader/scope.dart';
import 'package:bookfin/reader/screen.dart';
import 'package:bookfin/reader/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback/playback_test.dart'
    show LocalFiles, MemoryResume, TestEngine, account, recording, title;
import 'book_map_test.dart' show contents, threeSections;
import 'screen_test.dart' show ControlNavigator;
import 'session_test.dart' show source, edition, book;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final publication = threeSections();
  const sections = ['OPS/one.xhtml', 'OPS/two.xhtml', 'OPS/three.xhtml'];
  int size(String resource) => publication.resources[resource]!.length;
  final whole = sections.map(size).reduce((a, b) => a + b);

  /// A place [progress] of the way through section [resource], as the
  /// viewport reports it.
  ReadingLocation at(String resource, double progress, {String? chapter}) =>
      ReadingLocation.fromJson({
        'cfi': 'epubcfi(/6/4!/4/2/1:0)',
        'resource': resource,
        'quote': '',
        'chapter': ?chapter,
        'progress': progress,
      });

  /// The share of the book, in percent, of a place [progress] of the way
  /// through "two", as the dock names a place before the pages are known.
  int percentInTwo(double progress) =>
      ((size(sections[0]) + size(sections[1]) * progress) / whole * 100)
          .round();

  Finder inDock(Finder finder) =>
      find.descendant(of: find.byType(ReaderDock), matching: finder);

  /// Opens the three-section book a quarter of the way through "two" and
  /// shows the reader under the library's [ReaderScope], as the app does.
  /// The navigator shows each place that the session asks for at once.
  /// With [playback], the dock offers that audiobook.
  Future<(ReaderSession, _ShowingNavigator)> openReader(
    WidgetTester tester, {
    Playback? playback,
  }) async {
    final downloads = LocalFiles()
      ..files[source.key] = Uri.file('/verified.epub');
    final reader = ReaderSession(
      downloads: downloads,
      store: MemoryResume(),
      load: (_) async => publication,
    );
    addTearDown(() {
      reader.dispose();
      downloads.dispose();
    });
    await reader.bind(account(), [book]);
    await reader.open(book, edition);
    final navigator = _ShowingNavigator(
      sections,
      (location) => reader.acceptVisible(reader.token, location),
    );
    reader.attachDocument(reader.token, navigator, contents);
    await tester.runAsync(pumpEventQueue);
    reader.acceptVisible(
      reader.token,
      at('OPS/two.xhtml', .25, chapter: 'Two'),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: bookfinTheme(Brightness.light),
        home: ReaderScope(
          reader: reader,
          show: (_) {},
          child: ReaderScreen(
            reader: reader,
            onNightChanged: (_) {},
            playback: playback,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (reader, navigator);
  }

  /// The section and the progress of the shown place.
  (String, double?) shown(ReaderSession reader) {
    final location = (reader.visibleAddress! as EpubAddress).location;
    return (location.resource, location.progress);
  }

  /// Matches the [shown] place [progress] of the way through [resource].
  Matcher isAt(String resource, double progress) => isA<(String, double?)>()
      .having((place) => place.$1, 'section', resource)
      .having((place) => place.$2, 'progress', closeTo(progress, 1e-9));

  group('the Bookmark tool', () {
    testWidgets('a tap saves one untitled bookmark at the shown place, and '
        'the tool then reads Bookmarked', (tester) async {
      final (reader, _) = await openReader(tester);

      await tester.tap(inDock(find.byTooltip('Bookmark this place')));
      await tester.pumpAndSettle();

      expect(reader.bookmarks, hasLength(1));
      expect(reader.bookmarks.single.title, isNull);
      expect(inDock(find.byTooltip('Bookmarked')), findsOneWidget);
      expect(inDock(find.byTooltip('Bookmark this place')), findsNothing);
      expect(
        inDock(find.byIcon(Icons.bookmark_rounded)),
        findsOneWidget,
        reason: 'The icon fills.',
      );
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('a second tap opens the shared glass editor for that '
        'bookmark, with its place in the book, and saves its name', (
      tester,
    ) async {
      final (reader, _) = await openReader(tester);
      await tester.tap(inDock(find.byTooltip('Bookmark this place')));
      await tester.pumpAndSettle();

      await tester.tap(inDock(find.byTooltip('Bookmarked')));
      await tester.pumpAndSettle();

      expect(find.text('Edit bookmark'), findsOneWidget);
      expect(
        find.ancestor(
          of: find.text('Edit bookmark'),
          matching: find.byType(CoverGlass),
        ),
        findsOneWidget,
        reason: 'The editor is glass.',
      );
      expect(find.text('On ${percentInTwo(.25)}% · Two'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Title (optional)'),
        'River mark',
      );
      await tester.tap(find.text('Save bookmark'));
      await tester.pumpAndSettle();
      expect(reader.bookmarks, hasLength(1));
      expect(reader.bookmarks.single.title, 'River mark');
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('after a page turn the tool reads Bookmark this place again', (
      tester,
    ) async {
      final (reader, _) = await openReader(tester);
      await tester.tap(inDock(find.byTooltip('Bookmark this place')));
      await tester.pumpAndSettle();

      reader.acceptVisible(reader.token, at('OPS/two.xhtml', .5));
      await tester.pumpAndSettle();

      expect(inDock(find.byTooltip('Bookmark this place')), findsOneWidget);
      expect(inDock(find.byTooltip('Bookmarked')), findsNothing);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  });

  group('the Undo row', () {
    testWidgets('a jump shows the player\'s Undo row above the place label, '
        'inside the dock', (tester) async {
      await openReader(tester);
      expect(find.byType(UndoNotice), findsNothing);

      await tester.tap(inDock(find.byTooltip('Next chapter')));
      await tester.pumpAndSettle();

      expect(inDock(find.byType(UndoNotice)), findsOneWidget);
      final label = tester.getRect(
        inDock(find.bySemanticsLabel(RegExp(r'^Half · '))),
      );
      expect(
        tester.getRect(find.byType(UndoNotice)).bottom,
        lessThanOrEqualTo(label.top),
      );
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('Undo returns to the page where the jump began, and the row '
        'goes away', (tester) async {
      final (reader, _) = await openReader(tester);
      await tester.tap(inDock(find.byTooltip('Next chapter')));
      await tester.pumpAndSettle();
      expect(shown(reader), isAt('OPS/two.xhtml', .5));

      await tester.tap(find.widgetWithText(FilledButton, 'Undo'));
      await tester.pumpAndSettle();

      expect(shown(reader), isAt('OPS/two.xhtml', .25));
      expect(find.byType(UndoNotice), findsNothing);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('Dismiss hides the row and leaves the page where it is', (
      tester,
    ) async {
      final (reader, _) = await openReader(tester);
      await tester.tap(inDock(find.byTooltip('Next chapter')));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Dismiss Undo'));
      await tester.pumpAndSettle();

      expect(find.byType(UndoNotice), findsNothing);
      expect(reader.undoOffer, isNull);
      expect(shown(reader), isAt('OPS/two.xhtml', .5));
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('the row coming or going does not move or resize the page', (
      tester,
    ) async {
      await openReader(tester);
      final page = tester.getRect(find.byType(EpubViewport));
      final viewport = tester.state(find.byType(EpubViewport));
      final dock = tester.getRect(find.byType(ReaderDock));

      await tester.tap(inDock(find.byTooltip('Next chapter')));
      await tester.pumpAndSettle();
      expect(find.byType(UndoNotice), findsOneWidget);
      expect(
        tester.getRect(find.byType(ReaderDock)).top,
        lessThan(dock.top),
        reason: 'The dock grows upward over the page.',
      );
      expect(tester.getRect(find.byType(EpubViewport)), page);

      await tester.tap(find.byTooltip('Dismiss Undo'));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(EpubViewport)), page);
      expect(tester.state(find.byType(EpubViewport)), same(viewport));
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('a link followed in full screen keeps the offer, and the row '
        'shows with the controls', (tester) async {
      final (reader, _) = await openReader(tester);
      await tester.tap(find.byType(EpubViewport));
      await tester.pumpAndSettle();
      expect(find.byType(ReaderDock), findsNothing);

      await reader.followLink('three.xhtml');
      await tester.pumpAndSettle();
      expect(shown(reader).$1, 'OPS/three.xhtml');
      expect(find.byType(UndoNotice), findsNothing);

      await tester.tap(find.byType(EpubViewport));
      await tester.pumpAndSettle();
      expect(inDock(find.byType(UndoNotice)), findsOneWidget);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  });

  group('the History tool', () {
    late LocalFiles audioFiles;
    late Playback audiobook;
    setUp(() async {
      audioFiles = LocalFiles();
      audiobook = Playback(
        downloads: audioFiles,
        engine: TestEngine(),
        store: MemoryResume(),
      );
      await audiobook.bind(account(), [title]);
      await audiobook.open(title, recording, autoplay: false);
    });
    tearDown(() async {
      await audiobook.close();
      audioFiles.dispose();
    });

    testWidgets('sits after Bookmark and before the open audiobook\'s cover '
        'button', (tester) async {
      await openReader(tester, playback: audiobook);
      final row = [
        for (final tool in [
          find.byTooltip('Contents'),
          find.byTooltip('Search book'),
          find.byTooltip('Reading settings'),
          find.byTooltip('Bookmark this place'),
          find.byTooltip('History'),
          find.bySemanticsLabel('Play audiobook'),
        ])
          tester.getRect(inDock(tool)),
      ];
      for (var index = 1; index < row.length; index++) {
        expect(row[index].left, greaterThan(row[index - 1].right));
        expect(row[index].center.dy, closeTo(row[0].center.dy, 1));
      }
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('every tool keeps a 48-point touch target on a 360-point-wide '
        'phone with an audiobook open', (tester) async {
      tester.view.physicalSize = const Size(360, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final handle = tester.ensureSemantics();
      await openReader(tester, playback: audiobook);

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      handle.dispose();
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('opens the shared History timeline on a glass sheet over the '
        'book, with the book\'s reading moves and bookmarks', (tester) async {
      final (reader, _) = await openReader(tester);
      await reader.addBookmark(title: 'River mark');
      await tester.tap(inDock(find.byTooltip('Next chapter')));
      await tester.pumpAndSettle();

      await tester.tap(inDock(find.byTooltip('History')));
      await tester.pumpAndSettle();

      final timeline = find.byType(HistoryTimeline);
      expect(timeline, findsOneWidget);
      final glass = find.ancestor(
        of: timeline,
        matching: find.byType(CoverGlass),
      );
      expect(glass, findsOneWidget);
      expect(tester.widget<CoverGlass>(glass).book, book);
      expect(
        find.descendant(of: glass, matching: find.text('History')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: timeline, matching: find.text('River mark')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: timeline,
          matching: find.textContaining('Changed chapter'),
        ),
        findsOneWidget,
      );
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('Go to on a bookmark closes History, shows the bookmark\'s '
        'page and offers Undo', (tester) async {
      final (reader, _) = await openReader(tester);
      await reader.addBookmark(title: 'River mark');
      reader.acceptVisible(reader.token, at('OPS/three.xhtml', .5));
      await tester.pumpAndSettle();

      await tester.tap(inDock(find.byTooltip('History')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('River mark'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining(RegExp(r'^Go to ')));
      await tester.pumpAndSettle();

      expect(find.byType(HistoryTimeline), findsNothing);
      expect(shown(reader), isAt('OPS/two.xhtml', .25));
      expect(inDock(find.byType(UndoNotice)), findsOneWidget);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  });

  testWidgets('the contents sheet lists only the contents: no tabs and no '
      'bookmarks', (tester) async {
    final (reader, _) = await openReader(tester);
    await reader.addBookmark(title: 'River mark');

    await tester.tap(inDock(find.byTooltip('Contents')));
    await tester.pumpAndSettle();

    expect(find.byType(ReaderContentsPanel), findsOneWidget);
    expect(find.text('Half'), findsOneWidget);
    expect(find.byType(TabBar), findsNothing);
    expect(find.text('Bookmarks'), findsNothing);
    expect(find.text('River mark'), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
}

/// A navigator that shows each place that the session asks for at once, and
/// reports it through [show], as the pager reports the page that it shows.
/// A contents entry or a link shows the start of its section.
class _ShowingNavigator extends ControlNavigator {
  _ShowingNavigator(this.sections, this.show);
  final List<String> sections;
  final void Function(ReadingLocation location) show;

  ReadingLocation _at(String resource, double progress) =>
      ReadingLocation.fromJson({
        'cfi': 'epubcfi(/6/4!/4/2/1:0)',
        'resource': resource,
        'quote': '',
        'progress': progress,
      });

  @override
  Future<void> display(ReaderAddress address) async {
    await super.display(address);
    show((address as EpubAddress).location);
  }

  @override
  Future<void> seek(int part, double progress) async {
    await super.seek(part, progress);
    show(_at(sections[part], progress));
  }

  @override
  Future<void> contents(String href) async {
    await super.contents(href);
    show(_at('OPS/${href.split('#').first}', 0));
  }
}
