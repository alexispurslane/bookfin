import 'dart:io';

import 'package:bookfin/catalog/glass.dart' show CoverGlass;
import 'package:bookfin/foundation/theme.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:bookfin/playback/screen.dart';
import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/epub/viewport.dart';
import 'package:bookfin/reader/pdf.dart';
import 'package:bookfin/reader/platform_io.dart';
import 'package:bookfin/reader/screen.dart';
import 'package:bookfin/reader/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';

import '../playback/playback_test.dart'
    show LocalFiles, MemoryResume, TestEngine, account, recording, title;
import 'book_map_test.dart' show contents, threeSections;
import 'epub/helpers.dart' show loadReaderFont;
import 'native_reader.dart';
import 'pdf_document_test.dart' show pdfSource;
import 'pdf_screen_test.dart' show settleNative;
import 'pdf_session_test.dart' as pdf show book, edition;
import 'screen_test.dart' show ControlNavigator;
import 'session_test.dart' show source, edition, book;
import '../downloads/verified_reads.dart';

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

  /// Opens the three-section book on [navigator], at a place [progress] of the
  /// way through "two", and shows the reader. With [playback], the reader
  /// offers that audiobook. [night] reports each theme the person chose.
  Future<ReaderSession> openReader(
    WidgetTester tester, {
    ControlNavigator? navigator,
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
    reader.attachDocument(
      reader.token,
      navigator ?? ControlNavigator(),
      contents,
    );
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
          'History',
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
        reason: 'Contents, Search, Aa, Bookmark, then History, left to right.',
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
      final history = tester.getRect(inDock(find.byTooltip('History')));
      expect(cover.left, greaterThan(history.right));
      expect(cover.center.dy, closeTo(history.center.dy, 1));
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('has five tools and no round cover button without an '
        'audiobook', (tester) async {
      await openReader(tester);
      expect(find.bySemanticsLabel('Play audiobook'), findsNothing);
      expect(find.byType(PlaybackCoverButton), findsNothing);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('hides with a tap on the page and shows again with a second '
        'tap, on the same page', (tester) async {
      final reader = await openNative(tester);
      final viewport = tester.state(find.byType(EpubViewport));
      final address = reader.visibleAddress;
      final first = shownOf(reader)!.page;
      bool fits() =>
          shownOf(reader)!.page.settings.height ==
          tester.getSize(find.byType(EpubViewport)).height;

      await tester.tap(find.byType(EpubViewport));
      await settleReader(
        tester,
        () => find.byType(ReaderDock).evaluate().isEmpty,
      );
      await settleReader(tester, fits, reason: 'no page for the taller area');
      expect(find.byType(ReaderDock), findsNothing);
      expect(
        (shownOf(reader)!.page.section, shownOf(reader)!.page.startPlace),
        (first.section, first.startPlace),
      );

      await tester.tap(find.byType(EpubViewport));
      await settleReader(
        tester,
        () => find.byType(ReaderDock).evaluate().isNotEmpty,
      );
      await settleReader(tester, fits, reason: 'no page for the shorter area');
      expect(
        tester.state(find.byType(EpubViewport)),
        same(viewport),
        reason: 'The page stays open while the controls hide and show.',
      );
      expect(reader.visibleAddress, same(address), reason: 'Nothing moved.');
      await closeNative(tester, reader);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  });

  group('the place label of a native page', () {
    setUpAll(loadReaderFont);

    /// The page part of the dock's place label, such as "Page 2 of 8".
    String? pageLabel(WidgetTester tester) => tester
        .widgetList<Text>(inDock(find.byType(Text)))
        .map((text) => text.data ?? '')
        .map(RegExp(r'Page \d+( of \d+)?$').firstMatch)
        .nonNulls
        .map((match) => match[0])
        .firstOrNull;

    testWidgets('names the shown page among the book\'s pages once the book '
        'is laid out, and follows a turn', (tester) async {
      final reader = await openNative(tester);
      await settleReader(
        tester,
        () => reader.pager!.bookPages.value.complete,
        reason: 'the book was never laid out',
      );
      final count = reader.pager!.bookPages.value.count!;
      expect(reader.pager!.pageNumber.value, (number: 1, count: count));
      expect(count, greaterThan(1));
      expect(find.bySemanticsLabel('One · Page 1 of $count'), findsOneWidget);

      await finishReader(tester, reader.move(true));
      await settleReader(tester, () => pageLabel(tester) == 'Page 2 of $count');
      expect(find.bySemanticsLabel('One · Page 2 of $count'), findsOneWidget);
      await closeNative(tester, reader);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('names the chapter after the book opens at a saved place, '
        'whose saved form has no chapter title', (tester) async {
      final reader = await openNative(tester);
      await finishReader(tester, reader.goToContents('text/s1.xhtml#two'));
      await settleReader(tester, () => reader.position != null);
      await finishReader(tester, reader.open(book, edition));
      await waitForPage(tester, reader, (shown) => shown.page.section == 1);
      await settleReader(
        tester,
        () => reader.pager!.bookPages.value.complete,
        reason: 'the book was never laid out',
      );
      await tester.pump();
      expect(
        (reader.visibleAddress! as EpubAddress).location.chapter,
        isNull,
        reason: 'The pager reports the saved place as saved.',
      );
      final number = reader.pager!.pageNumber.value!;
      expect(
        find.bySemanticsLabel('Two · Page ${number.number} of ${number.count}'),
        findsOneWidget,
      );
      await closeNative(tester, reader);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  });

  group('the chapter arrows', () {
    testWidgets('go to the start of the next chapter, also one that starts '
        'inside a section', (tester) async {
      final navigator = ControlNavigator();
      final reader = await openReader(tester, navigator: navigator);
      await tester.tap(find.byTooltip('Next chapter'));
      await tester.pumpAndSettle();
      expect(navigator.seeks.single.$1, 1);
      expect(navigator.seeks.single.$2, closeTo(.5, 1e-9), reason: 'Half');

      reader.acceptVisible(reader.token, at('OPS/two.xhtml', .75));
      await tester.tap(find.byTooltip('Next chapter'));
      await tester.pumpAndSettle();
      expect(navigator.seeks.last, (2, 0.0), reason: 'Three');
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('go back to the start of the shown chapter, or to the '
        'chapter before when the page is that start', (tester) async {
      final navigator = ControlNavigator();
      final reader = await openReader(tester, navigator: navigator);
      await tester.tap(find.byTooltip('Previous chapter'));
      await tester.pumpAndSettle();
      expect(navigator.seeks.single, (1, 0.0), reason: 'the start of Two');

      reader.acceptVisible(reader.token, at('OPS/two.xhtml', 0));
      await tester.tap(find.byTooltip('Previous chapter'));
      await tester.pumpAndSettle();
      expect(navigator.seeks.last, (0, 0.0), reason: 'the start of One');
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('stay put past the last chapter start and before the first', (
      tester,
    ) async {
      final navigator = ControlNavigator();
      final reader = await openReader(tester, navigator: navigator);
      reader.acceptVisible(reader.token, at('OPS/three.xhtml', .5));
      await tester.tap(find.byTooltip('Next chapter'));
      await tester.pumpAndSettle();
      reader.acceptVisible(reader.token, at('OPS/one.xhtml', 0));
      await tester.tap(find.byTooltip('Previous chapter'));
      await tester.pumpAndSettle();
      expect(navigator.seeks, isEmpty);
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
      expect(inSheet('Page words'), findsNothing);
      expect(inSheet('Original page'), findsNothing);
      expect(find.text('Trim margins'), findsNothing);
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
                  verified(
                    File('tool/research/readers/fixtures/simple.pdf').absolute,
                  ),
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
      expect(inDock(find.byTooltip('Page words')), findsNothing);
      await close(tester);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('offers reflow in Reading settings', (tester) async {
      final reader = await openPdf(tester);
      await tester.tap(find.byTooltip('Reading settings'));
      await tester.pumpAndSettle();
      final sheet = find.byType(ReaderSettingsPanel);
      await tester.tap(
        find.descendant(of: sheet, matching: find.byTooltip('Page words')),
      );
      await settleNative(tester);
      expect(reader.pdfView, PdfPageView.pageWords);
      await tester.tap(
        find.descendant(of: sheet, matching: find.byTooltip('Original page')),
      );
      await settleNative(tester);
      expect(reader.pdfView, PdfPageView.original);
      await close(tester);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  });
}
