import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bookfin/catalog/glass.dart' show CoverGlass;
import 'package:bookfin/foundation/theme.dart';
import 'package:bookfin/playback/records.dart' show HistoryAction;
import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/epub/layout.dart' show Slice;
import 'package:bookfin/reader/epub/pager.dart';
import 'package:bookfin/reader/epub/publication.dart';
import 'package:bookfin/reader/epub/viewport.dart';
import 'package:bookfin/reader/screen.dart';
import 'package:bookfin/reader/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../playback/playback_test.dart' show account, LocalFiles, MemoryResume;
import 'epub/helpers.dart' show loadReaderFont;
import 'epub/page_source_test.dart' show paragraphs, WatchedPublication;
import 'epub/page_source_test.dart' as fixture show book;
import 'native_reader.dart';
import 'publication_test.dart' show epub;
import 'reader_settings.dart';
import 'session_native_test.dart' show navBook;
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
        find.byTooltip('Page words'),
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
    'closing search with Close in its title row or a tap outside the sheet '
    'ends the search',
    (tester) async {
      final navigator = ControlNavigator();
      await openReader(tester, navigator);
      await tester.tap(find.byTooltip('Search book'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Close'));
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
    'every reader sheet is a glass pane that shows the open book, with the '
    'heading in its title row',
    (tester) async {
      await openReader(
        tester,
        ControlNavigator(),
        contents: const [ContentsEntry('River heading', 'one.xhtml')],
      );
      for (final (tool, shown, heading) in [
        ('Contents', 'River heading', null),
        ('Search book', 'Find in this book', 'Search'),
        ('Reading settings', 'Text size', 'Reading settings'),
      ]) {
        await tester.tap(find.byTooltip(tool));
        await tester.pumpAndSettle();
        final glass = find.ancestor(
          of: find.text(shown),
          matching: find.byType(CoverGlass),
        );
        expect(glass, findsOneWidget, reason: tool);
        expect(tester.widget<CoverGlass>(glass).book, book, reason: tool);
        if (heading != null) {
          expect(
            find.descendant(
              of: glass,
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Semantics &&
                    widget.properties.header == true &&
                    widget.child is Text &&
                    (widget.child! as Text).data == heading,
              ),
            ),
            findsOneWidget,
            reason: '$tool has its heading in the glass title row',
          );
        }
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

    /// A two-chapter book whose first page has a note reference to an
    /// endnote at the end of the second chapter. The endnote ends with a
    /// back link to the reference, as Standard Ebooks writes one.
    Publication noteChapterBook() => Publication.admit(
      navBook(
        [
          '<h1 id="one">One</h1><p>The harbour<a id="ref-1" '
              'epub:type="noteref" href="s1.xhtml#note-1">1</a> waits.</p>'
              '${paragraphs(24)}',
          '<h1 id="two">Two</h1>${paragraphs(24, label: 'Near')}'
              '<ol epub:type="endnotes"><li id="note-1" epub:type="endnote">'
              '<p>The lantern note explains the harbour. <a '
              'href="s0.xhtml#ref-1" role="doc-backlink">\u21a9</a></p>'
              '</li></ol>',
        ],
        [('One', 'text/s0.xhtml#one'), ('Two', 'text/s1.xhtml#two')],
      ),
    );

    /// A point of the shown page, from the viewport's top left corner,
    /// whose link passes [test].
    Offset linkPoint(
      WidgetTester tester,
      ReaderSession reader,
      bool Function(EpubLink link) test,
    ) {
      final area = tester.getRect(find.byType(EpubViewport));
      for (var y = 0.0; y < area.height / 2; y += 4) {
        for (var x = 0.0; x < area.width; x += 4) {
          final link = reader.pager!.linkAt(Offset(x, y));
          if (link != null && test(link)) return area.topLeft + Offset(x, y);
        }
      }
      fail('The first page shows no such link.');
    }

    testWidgets('a tap on a note reference shows the note\'s text on a glass '
        'sheet headed Note, with Go to note in its title row and no back '
        'link, and the page and the saved place stay', (tester) async {
      final handle = tester.ensureSemantics();
      final reader = await openNative(tester, publication: noteChapterBook());
      final first = shownOf(reader)!.page;
      final saved = reader.visibleAddress;

      await tester.tapAt(linkPoint(tester, reader, (link) => link.noteref));
      await settleReader(
        tester,
        () => find.byType(EpubNoteView).evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();

      final glass = find.ancestor(
        of: find.byType(EpubNoteView),
        matching: find.byType(CoverGlass),
      );
      expect(glass, findsOneWidget);
      expect(tester.widget<CoverGlass>(glass).book, reader.book);
      final heading = find.descendant(of: glass, matching: find.text('Note'));
      final action = find.descendant(
        of: glass,
        matching: find.widgetWithText(TextButton, 'Go to note'),
      );
      expect(heading, findsOneWidget);
      expect(
        tester.getCenter(action).dy,
        moreOrLessEquals(tester.getCenter(heading).dy, epsilon: 1),
        reason: 'Note and Go to note share the title row.',
      );
      expect(
        tester.getRect(action).bottom,
        lessThan(tester.getRect(find.byType(EpubNoteView)).top),
        reason: 'Go to note sits above the note, not under it.',
      );
      expect(
        tester.getSemantics(action),
        isSemantics(label: 'Go to note', isButton: true, hasTapAction: true),
      );
      expect(tester.getSize(action).height, greaterThanOrEqualTo(48));
      expect(
        find.semantics.byLabel('The lantern note explains the harbour.'),
        findsOneWidget,
        reason: 'The back link is left out of the sheet.',
      );
      expect(find.semantics.byLabel(RegExp('\u21a9')), findsNothing);
      expect(shownOf(reader)!.page, same(first));
      expect(reader.visibleAddress, same(saved));
      handle.dispose();
      await closeNative(tester, reader);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('the note\'s text lines up with the sheet\'s heading, and '
        'the space between the heading\'s letters and the note\'s equals '
        'the space between the note\'s letters and the sheet\'s edge', (
      tester,
    ) async {
      final reader = await openNative(tester, publication: noteChapterBook());

      await tester.tapAt(linkPoint(tester, reader, (link) => link.noteref));
      await settleReader(
        tester,
        () => find.byType(EpubNoteView).evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();

      final view = find.byType(EpubNoteView);
      final note = tester.getRect(view);
      final pane = tester.getRect(
        find.ancestor(of: view, matching: find.byType(CoverGlass)),
      );
      final title = find.descendant(
        of: find.byType(CoverGlass),
        matching: find.text('Note'),
      );
      final heading = tester.getRect(title);
      expect(note.left, heading.left);
      expect(
        note.right,
        moreOrLessEquals(pane.right - (heading.left - pane.left)),
      );

      // The heading, Note, has no descenders, so its letters end at its
      // baseline. The note's letters reach from its first line's ascent to
      // its last line's descent.
      final headingBox = tester.renderObject<RenderBox>(title);
      final headingBaseline =
          heading.top +
          headingBox.getDryBaseline(
            BoxConstraints(maxWidth: headingBox.size.width),
            TextBaseline.alphabetic,
          )!;
      final page = tester.widget<EpubNoteView>(view).note.page;
      ui.LineMetrics metrics(Slice slice) =>
          slice.piece!.paragraph.computeLineMetrics()[slice.line];
      double lineTop(Slice slice) =>
          note.top + slice.piece!.y - page.top + metrics(slice).baseline;
      final lines = page.slices.where((slice) => slice.piece != null);
      final above =
          lineTop(lines.first) - metrics(lines.first).ascent - headingBaseline;
      final below =
          pane.bottom - lineTop(lines.last) - metrics(lines.last).descent;
      expect(
        above,
        moreOrLessEquals(below, epsilon: 5),
        reason:
            'The font\'s ascent and descent reach a little past its '
            'letters, so the bands match to within 5 pixels.',
      );
      await closeNative(tester, reader);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('Go to note closes the sheet and shows the note, which '
        'becomes the saved place', (tester) async {
      final reader = await openNative(tester, publication: noteChapterBook());

      await tester.tapAt(linkPoint(tester, reader, (link) => link.noteref));
      await settleReader(
        tester,
        () => find.text('Go to note').evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();
      expect(
        (reader.visibleAddress! as EpubAddress).location.resource,
        'OPS/text/s0.xhtml',
        reason: 'Only Go to note moves the saved place.',
      );
      await tester.tap(find.widgetWithText(TextButton, 'Go to note'));
      await waitForPage(tester, reader, (shown) => shown.page.section == 1);
      await settleReader(
        tester,
        () =>
            (reader.visibleAddress! as EpubAddress).location.resource ==
            'OPS/text/s1.xhtml',
      );
      await tester.pumpAndSettle();

      expect(find.byType(EpubNoteView), findsNothing);
      final page = shownOf(reader)!.page;
      expect(
        page.dom.texts
            .where((text) => text.text.startsWith('The lantern note'))
            .single
            .order,
        inInclusiveRange(page.startPlace!.node, page.endPlace!.node),
        reason: 'The shown page holds the note.',
      );
      expect(
        [
          for (final event in reader.history)
            if (event.kind != HistoryAction.open) event.kind,
        ],
        [HistoryAction.link],
        reason: 'Go to note records one link move.',
      );
      await closeNative(tester, reader);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets(
      'a limited note stays over the current page and Go to note opens the full note',
      (tester) async {
        final publication = Publication.admit(
          navBook(
            [
              '<p>The harbour<a epub:type="noteref" href="s1.xhtml#n">1</a> waits.</p>',
              '<aside id="n" epub:type="footnote">${paragraphs(90)}</aside>',
            ],
            [('Start', 'text/s0.xhtml'), ('Note', 'text/s1.xhtml#n')],
          ),
        );
        final reader = await openNative(tester, publication: publication);
        final before = reader.visibleAddress;
        await tester.tapAt(linkPoint(tester, reader, (link) => link.noteref));
        await settleReader(
          tester,
          () => find.byType(ReaderNotePanel).evaluate().isNotEmpty,
        );
        await tester.pumpAndSettle();
        expect(reader.visibleAddress, before);
        expect(
          find.text('Showing the beginning. Go to note opens the full note.'),
          findsOneWidget,
        );
        expect(
          tester.widget<EpubNoteView>(find.byType(EpubNoteView)).note.limited,
          isTrue,
        );
        await tester.tap(find.widgetWithText(TextButton, 'Go to note'));
        await waitForPage(tester, reader, (shown) => shown.page.section == 1);
        await tester.pumpAndSettle();
        expect(find.byType(ReaderNotePanel), findsNothing);
        expect(
          (reader.visibleAddress! as EpubAddress).location.resource,
          'OPS/text/s1.xhtml',
        );
        expect(
          reader.history.where((event) => event.kind == HistoryAction.link),
          hasLength(1),
        );
        await closeNative(tester, reader);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );

    testWidgets(
      'changing text size while a note image waits cancels the sheet without navigation',
      (tester) async {
        final publication = _HeldNoteImage(
          fixture.book(
            [
              '<p><a epub:type="noteref" href="s1.xhtml#n">1</a></p>',
              '<aside id="n" epub:type="footnote"><p>Note.</p><img src="../note.png"/></aside>',
            ],
            files: {'note.png': img.encodePng(img.Image(width: 2, height: 2))},
          ),
        );
        addTearDown(() {
          if (!publication.release.isCompleted) publication.release.complete();
        });
        final reader = await openNative(tester, publication: publication);
        await tester.tapAt(linkPoint(tester, reader, (link) => link.noteref));
        await settleReader(tester, () => publication.requested.isCompleted);
        await finishReader(tester, reader.setFontSize(26));
        await waitForPage(
          tester,
          reader,
          (shown) => shown.page.settings.fontSize == 26,
        );
        var releasedImage = false;
        final previousDispose = ui.Image.onDispose;
        ui.Image.onDispose = (image) {
          releasedImage = true;
          previousDispose?.call(image);
        };
        addTearDown(() => ui.Image.onDispose = previousDispose);
        publication.release.complete();
        await settleReader(tester, () => releasedImage);
        await tester.pumpAndSettle();
        expect(find.byType(ReaderNotePanel), findsNothing);
        expect(
          reader.history.where((event) => event.kind == HistoryAction.link),
          isEmpty,
        );
        expect(
          (reader.visibleAddress! as EpubAddress).location.resource,
          'OPS/text/s0.xhtml',
        );
        await closeNative(tester, reader);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );

    testWidgets('an ordinary long note scrolls without omitting its ending', (
      tester,
    ) async {
      final reader = await openNative(
        tester,
        publication: fixture.book([
          '<p><a epub:type="noteref" href="s1.xhtml#n">1</a></p>',
          '<aside id="n" epub:type="footnote">${paragraphs(8)}</aside>',
        ]),
      );
      await tester.tapAt(linkPoint(tester, reader, (link) => link.noteref));
      await settleReader(
        tester,
        () => find.byType(ReaderNotePanel).evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();
      final note = tester.widget<EpubNoteView>(find.byType(EpubNoteView)).note;
      expect(note.limited, isFalse);
      final scrollable = tester.state<ScrollableState>(
        find.descendant(
          of: find.byType(ReaderNotePanel),
          matching: find.byType(Scrollable),
        ),
      );
      expect(scrollable.position.maxScrollExtent, greaterThan(0));
      await tester.dragFrom(
        tester.getTopLeft(find.byType(ReaderNotePanel)) + const Offset(80, 120),
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();
      expect(scrollable.position.pixels, greaterThan(0));
      expect(
        find.text('Showing the beginning. Go to note opens the full note.'),
        findsNothing,
      );
      await tester.tap(find.widgetWithText(TextButton, 'Go to note'));
      await waitForPage(tester, reader, (shown) => shown.page.section == 1);
      await tester.pumpAndSettle();
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
      expect(
        [
          for (final event in reader.history)
            if (event.kind != HistoryAction.open) event.kind,
        ],
        [HistoryAction.link],
        reason: 'A link records one link move.',
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
  @override
  void reportPendingPlace() {}

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

/// Holds the real note image read until a settings change has completed.
class _HeldNoteImage extends WatchedPublication {
  _HeldNoteImage(super.inner);
  final requested = Completer<void>();
  final release = Completer<void>();

  @override
  List<String> get spineSteps => inner.spineSteps;

  @override
  String get originalDigest => inner.originalDigest;

  @override
  List<String> get warnings => inner.warnings;

  @override
  Future<Uint8List?> bytesOf(String path) async {
    if (path.endsWith('note.png')) {
      if (!requested.isCompleted) requested.complete();
      await release.future;
    }
    return super.bytesOf(path);
  }
}
