import 'dart:io';

import 'package:bookfin/catalog/glass.dart' show CoverGlass;
import 'package:bookfin/foundation/theme.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:bookfin/playback/screen.dart';
import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/pdf.dart';
import 'package:bookfin/reader/platform_io.dart';
import 'package:bookfin/reader/screen.dart';
import 'package:bookfin/reader/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_epub_viewer/publication.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';

import '../playback/playback_test.dart'
    show LocalFiles, MemoryResume, TestEngine, account, recording, title;
import 'appearance_test.dart' show BridgePlatform, finishLoading;
import 'book_map_test.dart' show contents, threeSections;
import 'pdf_document_test.dart' show pdfSource;
import 'pdf_screen_test.dart' show settleNative;
import 'pdf_session_test.dart' as pdf show book, edition;
import 'publication_test.dart' show epub;
import 'screen_test.dart' show ControlPort;
import 'session_test.dart' show source, edition, book, visible;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final publication = threeSections();
  int size(String resource) => publication.resources[resource]!.length;
  final whole =
      size('OPS/one.xhtml') + size('OPS/two.xhtml') + size('OPS/three.xhtml');

  /// Where a place [progress] of the way through "two" sits in the book.
  double inTwo(double progress) =>
      (size('OPS/one.xhtml') + size('OPS/two.xhtml') * progress) / whole;

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

  /// Opens the three-section book on [port], at a place [progress] of the
  /// way through "two", and shows the reader. With [playback], the reader
  /// offers that audiobook. [night] reports each theme the person chose.
  Future<ReaderSession> openReader(
    WidgetTester tester, {
    ControlPort? port,
    Playback? playback,
    List<bool>? night,
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
    reader.attach(reader.token, port ?? ControlPort(), contents);
    await tester.runAsync(pumpEventQueue);
    reader.acceptVisible(
      reader.token,
      at('OPS/two.xhtml', .25, chapter: 'Two'),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: bookfinTheme(Brightness.light),
        home: ReaderScreen(
          reader: reader,
          onNightChanged: (on) => night?.add(on),
          playback: playback,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return reader;
  }

  Finder inDock(Finder finder) =>
      find.descendant(of: find.byType(ReaderDock), matching: finder);

  // An audiobook that does not play yet. Playback's queue begins in the
  // real zone, as in the other playback tests.
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

  group('the glass dock', () {
    testWidgets('holds the place label, the scrub bar between the chapter '
        'arrows, and one row of reading tools, top to bottom', (tester) async {
      await openReader(tester);
      expect(
        find.ancestor(
          of: find.byType(ReaderDock),
          matching: find.byType(CoverGlass),
        ),
        findsNothing,
        reason: 'The dock is the glass, not inside another pane.',
      );
      expect(inDock(find.byType(CoverGlass)), findsOneWidget);
      final label = tester.getRect(
        inDock(find.bySemanticsLabel('Two · ${(inTwo(.25) * 100).round()}%')),
      );
      final bar = tester.getRect(inDock(find.byType(Slider)));
      final previous = tester.getRect(
        inDock(find.byTooltip('Previous chapter')),
      );
      final next = tester.getRect(inDock(find.byTooltip('Next chapter')));
      final tools = [
        for (final tool in [
          'Contents',
          'Search book',
          'Reading settings',
          'Bookmark this place',
        ])
          tester.getRect(inDock(find.byTooltip(tool))),
      ];
      // Assistive technology names Aa by what it opens, not by its letters.
      final settings = tester.getSemantics(
        inDock(find.byTooltip('Reading settings')),
      );
      expect(settings.tooltip, 'Reading settings');
      expect(settings.label, isNot(contains('Aa')));
      expect(label.bottom, lessThanOrEqualTo(bar.top));
      expect(previous.right, lessThanOrEqualTo(bar.left));
      expect(next.left, greaterThanOrEqualTo(bar.right));
      expect(previous.center.dy, closeTo(bar.center.dy, 1));
      for (final tool in tools) {
        expect(tool.top, greaterThanOrEqualTo(bar.bottom));
      }
      expect(
        [for (final tool in tools) tool.left],
        orderedEquals([...tools.map((tool) => tool.left)]..sort()),
        reason: 'Contents, Search, Aa, then Add bookmark, left to right.',
      );
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('replaces the old rows: no separate bookmarks list, text '
        'size or theme buttons, and no mini player', (tester) async {
      await openReader(tester, playback: audiobook);
      for (final gone in [
        'Reading bookmarks',
        'Smaller text',
        'Larger text',
        'Night reading theme',
        'Cream reading theme',
        'Previous page',
        'Next page',
      ]) {
        expect(find.byTooltip(gone), findsNothing, reason: gone);
      }
      expect(find.byType(MiniPlayerCard), findsNothing);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('ends its tool row with the round cover button of the open '
        'audiobook', (tester) async {
      await openReader(tester, playback: audiobook);
      final cover = tester.getRect(
        inDock(find.bySemanticsLabel('Play audiobook')),
      );
      final bookmark = tester.getRect(
        inDock(find.byTooltip('Bookmark this place')),
      );
      expect(cover.left, greaterThan(bookmark.right));
      expect(cover.center.dy, closeTo(bookmark.center.dy, 1));
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('has four tools and no round cover button without an '
        'audiobook', (tester) async {
      await openReader(tester);
      expect(find.bySemanticsLabel('Play audiobook'), findsNothing);
      expect(find.byType(PlaybackCoverButton), findsNothing);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('hides with a tap on the page and shows again with a second '
        'tap', (tester) async {
      final platform = BridgePlatform();
      final previous = InAppWebViewPlatform.instance;
      InAppWebViewPlatform.instance = platform;
      addTearDown(() {
        if (previous != null) InAppWebViewPlatform.instance = previous;
      });
      final downloads = LocalFiles()
        ..files[source.key] = Uri.file('/verified.epub');
      final reader = ReaderSession(
        downloads: downloads,
        store: MemoryResume(),
        load: (_) async => Publication.admit(epub()),
      );
      await reader.bind(account(), [book]);
      await reader.open(book, edition);
      await tester.pumpWidget(
        MaterialApp(
          theme: bookfinTheme(Brightness.light),
          home: ReaderScreen(reader: reader, onNightChanged: (_) {}),
        ),
      );
      await finishLoading(tester);
      final bridge = platform.controllers.single;
      bridge.handlers['readerLocation']!([visible.toJson()]);
      await tester.pumpAndSettle();
      expect(find.byType(ReaderDock), findsOneWidget);
      bridge.handlers['readerTap']!([]);
      await tester.pumpAndSettle();
      expect(find.byType(ReaderDock), findsNothing);
      bridge.handlers['readerTap']!([]);
      await tester.pumpAndSettle();
      expect(find.byType(ReaderDock), findsOneWidget);
      expect(
        platform.controllers,
        hasLength(1),
        reason: 'The page stays open while the controls hide and show.',
      );
      await tester.pumpWidget(const SizedBox());
      reader.dispose();
      await reader.flush();
      downloads.dispose();
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  });

  group('the chapter arrows', () {
    testWidgets('go to the start of the next chapter, also one that starts '
        'inside a section', (tester) async {
      final port = ControlPort();
      final reader = await openReader(tester, port: port);
      await tester.tap(find.byTooltip('Next chapter'));
      await tester.pumpAndSettle();
      expect(port.seeks.single.$1, 1);
      expect(port.seeks.single.$2, closeTo(.5, 1e-9), reason: 'Half');

      reader.acceptVisible(reader.token, at('OPS/two.xhtml', .75));
      await tester.tap(find.byTooltip('Next chapter'));
      await tester.pumpAndSettle();
      expect(port.seeks.last, (2, 0.0), reason: 'Three');
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('go back to the start of the shown chapter, or to the '
        'chapter before when the page is that start', (tester) async {
      final port = ControlPort();
      final reader = await openReader(tester, port: port);
      await tester.tap(find.byTooltip('Previous chapter'));
      await tester.pumpAndSettle();
      expect(port.seeks.single, (1, 0.0), reason: 'the start of Two');

      reader.acceptVisible(reader.token, at('OPS/two.xhtml', 0));
      await tester.tap(find.byTooltip('Previous chapter'));
      await tester.pumpAndSettle();
      expect(port.seeks.last, (0, 0.0), reason: 'the start of One');
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('stay put past the last chapter start and before the first', (
      tester,
    ) async {
      final port = ControlPort();
      final reader = await openReader(tester, port: port);
      reader.acceptVisible(reader.token, at('OPS/three.xhtml', .5));
      await tester.tap(find.byTooltip('Next chapter'));
      await tester.pumpAndSettle();
      reader.acceptVisible(reader.token, at('OPS/one.xhtml', 0));
      await tester.tap(find.byTooltip('Previous chapter'));
      await tester.pumpAndSettle();
      expect(port.seeks, isEmpty);
      expect(reader.message, isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  });

  group('Reading settings', () {
    testWidgets('opens a sheet with the text size and the reading theme, and '
        'no reflow for an EPUB', (tester) async {
      final night = <bool>[];
      final reader = await openReader(tester, night: night);
      await tester.tap(find.byTooltip('Reading settings'));
      await tester.pumpAndSettle();
      final sheet = find.byType(ReaderSettingsPanel);
      expect(sheet, findsOneWidget);
      Finder inSheet(String tooltip) =>
          find.descendant(of: sheet, matching: find.byTooltip(tooltip));
      expect(inSheet('Reflow text'), findsNothing);
      expect(inSheet('Original page'), findsNothing);
      final size = reader.fontSize;
      await tester.tap(inSheet('Larger text'));
      await tester.pumpAndSettle();
      expect(reader.fontSize, size + 2);
      await tester.tap(inSheet('Smaller text'));
      await tester.pumpAndSettle();
      expect(reader.fontSize, size);
      await tester.tap(inSheet('Night reading theme'));
      await tester.pumpAndSettle();
      expect(night, [true]);
      expect(inSheet('Cream reading theme'), findsOneWidget);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('turns its text size buttons off at the smallest and the '
        'largest size', (tester) async {
      final reader = await openReader(tester);
      await reader.setFontSize(40);
      await tester.tap(find.byTooltip('Reading settings'));
      await tester.pumpAndSettle();
      IconButton button(String tooltip) => tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, switch (tooltip) {
          'Larger text' => Icons.text_increase_rounded,
          _ => Icons.text_decrease_rounded,
        }),
      );
      expect(button('Larger text').onPressed, isNull);
      expect(button('Smaller text').onPressed, isNotNull);
      await reader.setFontSize(14);
      await tester.pumpAndSettle();
      expect(button('Larger text').onPressed, isNotNull);
      expect(button('Smaller text').onPressed, isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  });

  group('Contents', () {
    testWidgets('opens a sheet with a Contents tab and a Bookmarks tab', (
      tester,
    ) async {
      final port = ControlPort();
      final reader = await openReader(tester, port: port);
      await reader.addBookmark(title: 'River mark');
      await tester.tap(find.byTooltip('Contents'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(Tab, 'Contents'), findsOneWidget);
      expect(find.widgetWithText(Tab, 'Bookmarks'), findsOneWidget);
      expect(find.text('Half'), findsOneWidget);
      expect(find.text('River mark'), findsNothing);
      await tester.tap(find.widgetWithText(Tab, 'Bookmarks'));
      await tester.pumpAndSettle();
      expect(find.text('River mark'), findsOneWidget);
      await tester.tap(find.text('River mark'));
      await tester.pumpAndSettle();
      expect(find.byType(ReaderContentsPanel), findsNothing);
      expect(port.destinations, hasLength(1));
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('says how to add a bookmark when there is none', (
      tester,
    ) async {
      await openReader(tester);
      await tester.tap(find.byTooltip('Contents'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(Tab, 'Bookmarks'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No reading bookmarks'), findsOneWidget);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  });

  group('a PDF', () {
    late PdfBook document;
    setUp(() async {
      Pdfrx.pdfiumModulePath = Platform.environment['PDFIUM_LIBRARY'];
      Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;
    });

    Future<ReaderSession> openPdf(WidgetTester tester) async {
      document =
          (await tester.runAsync(
                () => loadReadingDocument(
                  File('tool/research/readers/fixtures/simple.pdf')
                      .absolute
                      .uri,
                  pdfSource,
                ),
              ))!
              as PdfBook;
      final downloads = LocalFiles()
        ..files[pdfSource.key] = File(
          'tool/research/readers/fixtures/simple.pdf',
        ).absolute.uri;
      final reader = ReaderSession(
        downloads: downloads,
        store: MemoryResume(),
        load: loadPublication,
        loadDocument: (_, _) async => document,
      );
      await reader.bind(account(), [pdf.book]);
      await reader.open(pdf.book, pdf.edition);
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(reader: reader, onNightChanged: (_) {}),
        ),
      );
      await settleNative(tester);
      addTearDown(() {
        reader.dispose();
        downloads.dispose();
      });
      return reader;
    }

    Future<void> close(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    }

    testWidgets('has page arrows at the ends of its bar, because its pages '
        'are not chapters', (tester) async {
      final reader = await openPdf(tester);
      expect(inDock(find.byTooltip('Previous page')), findsOneWidget);
      expect(inDock(find.byTooltip('Previous chapter')), findsNothing);
      await tester.tap(inDock(find.byTooltip('Next page')));
      await settleNative(tester);
      expect((reader.visibleAddress as PdfAddress).sourcePage, 2);
      expect(inDock(find.byTooltip('Reflow text')), findsNothing);
      await close(tester);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('offers reflow in Reading settings', (tester) async {
      final reader = await openPdf(tester);
      await tester.tap(find.byTooltip('Reading settings'));
      await tester.pumpAndSettle();
      final sheet = find.byType(ReaderSettingsPanel);
      await tester.tap(
        find.descendant(of: sheet, matching: find.byTooltip('Reflow text')),
      );
      await settleNative(tester);
      expect(reader.reflow, isTrue);
      await tester.tap(
        find.descendant(of: sheet, matching: find.byTooltip('Original page')),
      );
      await settleNative(tester);
      expect(reader.reflow, isFalse);
      await close(tester);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  });
}
