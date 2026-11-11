// In the reader's History, a tile of a listening place names where Go to
// lands in the open ebook (docs/plans/cross-edition-places.md, "What the
// person sees"). The reader names a place by its page once it laid out the
// open book's pages. Until then, the tile names the landing by its share of
// the book and its chapter. Before the reader shows the book at all, Go to
// cannot show the landing there, and the tile keeps the place's own words.
import 'dart:io';

import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/crossings/crossings.dart';
import 'package:bookfin/crossings/scope.dart';
import 'package:bookfin/foundation/theme.dart';
import 'package:bookfin/foundation/time.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:bookfin/playback/timeline.dart';
import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/platform_io.dart';
import 'package:bookfin/reader/scope.dart';
import 'package:bookfin/reader/screen.dart';
import 'package:bookfin/reader/session.dart';
import 'package:bookfin/reader/text_outline.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';

import '../crossings/crossings_test.dart' show MemoryOutlines;
import '../downloads/verified_reads.dart';
import '../playback/mapped_moves_test.dart' show MediumSpy;
import '../playback/playback_test.dart'
    show account, LocalFiles, MemoryResume, TestEngine;
import 'history_pages_test.dart' show both, narration;
import 'native_reader.dart';
import 'pdf_screen_test.dart' show settleNative;
import 'session_test.dart' show edition, source;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Pdfrx.pdfiumModulePath = Platform.environment['PDFIUM_LIBRARY'];
  Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;

  testWidgets('in the reader, a listening move names its landing by its '
      'share of the ebook and its chapter until the reader lays out the '
      'book\'s pages, and then by its page', (tester) async {
    final downloads = LocalFiles()
      ..files[source.key] = Uri.file('/verified.epub')
      ..files[narration.files.single.key] = Uri.file('/narration.mp3');
    addTearDown(downloads.dispose);
    final opened = twoChapterBook();
    final outline = measureTextOutline(opened);
    final reader = ReaderSession(
      downloads: downloads,
      store: MemoryResume(),
      load: (_) async => opened,
    );
    final crossings = Crossings(
      store: MemoryOutlines(),
      measure: (_) async => outline,
      hop: <M, R>(work, input) async => work(input),
    );
    addTearDown(crossings.dispose);
    // A listening move from the start to 30 s, half of chapter One. The
    // player runs on real time, as the app's does.
    late final Playback playback;
    await tester.runAsync(() async {
      playback = Playback(
        downloads: downloads,
        engine: TestEngine(),
        store: MediumSpy(),
      );
      await playback.bind(account(), [both]);
      await playback.open(both, narration, autoplay: false);
      await playback.seekEdition(30000);
      await playback.flush();
      playback.dismissUndo();
    });
    final heard = playback.history.first;
    // The reader opens the book on its own pager, which lays out pages
    // only once the reader screen shows them.
    await reader.bind(account(), [both]);
    await reader.open(both, edition);
    final landing =
        (await tester.runAsync(
              () => crossings.landing(
                heard.after,
                from: narration,
                into: edition,
              ),
            ))!
            as TextLanding;

    final shown = ValueNotifier(false);
    addTearDown(shown.dispose);
    late BuildContext page;
    await tester.pumpWidget(
      MaterialApp(
        theme: bookfinTheme(Brightness.light),
        home: CrossingsScope(
          crossings: crossings,
          child: ReaderScope(
            reader: reader,
            show: (_) {},
            child: Builder(
              builder: (context) {
                page = context;
                return ValueListenableBuilder(
                  valueListenable: shown,
                  builder: (_, shown, _) => shown
                      ? ReaderScreen(reader: reader, onNightChanged: (_) {})
                      : const SizedBox.expand(),
                );
              },
            ),
          ),
        ),
      ),
    );
    expect(reader.bookMap, isNotNull);
    expect(reader.bookMap!.pages, isNull);
    openHistory(page, playback, book: both, showing: EditionKind.text);
    await tester.pumpAndSettle();
    Finder inTimeline(Finder finder) =>
        find.descendant(of: find.byType(HistoryTimeline), matching: finder);
    await tester.tap(inTimeline(find.text('Ahead 30 s', findRichText: true)));
    await tester.pumpAndSettle();
    Finder inTile(String role, Finder finder) => find.descendant(
      of: find
          .ancestor(
            of: inTimeline(find.text(role)),
            matching: find.byType(InkWell),
          )
          .first,
      matching: finder,
    );

    // Half of chapter One, in the book's visible characters.
    final (one, two) = (outline.entries[0].start, outline.entries[1].start);
    final half = ((one + two) / 2 / outline.length * 100).round();
    expect(half, greaterThan(0));
    expect(inTile('AFTER', find.text('about $half%')), findsOneWidget);
    expect(inTile('AFTER', find.text('One')), findsOneWidget);
    expect(inTile('BEFORE', find.text('about 0%')), findsOneWidget);
    expect(inTimeline(find.text('0:30')), findsNothing);

    // The reader shows the book under the sheet, and lays out its pages.
    shown.value = true;
    await settleReader(
      tester,
      () => reader.bookMap?.pages != null,
      reason: 'the book was not laid out',
    );
    await tester.pumpAndSettle();
    final map = reader.bookMap!;
    final landed = map.targetAt(map.fractionAt(landing.place)).page!;
    expect(landed, greaterThan(1));
    expect(inTile('AFTER', find.text('about p. $landed')), findsOneWidget);
    expect(inTile('AFTER', find.text('One')), findsOneWidget);
    expect(inTile('BEFORE', find.text('about p. 1')), findsOneWidget);

    await closeNative(tester, reader);
    await tester.runAsync(playback.close);
  });

  testWidgets('in a PDF, a listening move names the page where it lands and '
      'the chapter of the PDF\'s bookmarks, and Go to shows that page', (
    tester,
  ) async {
    final margins = File('test/reader/fixtures/reflow/margins-book.pdf')
        .absolute;
    final source = SourceFile(
      itemId: 'margins',
      displayName: 'A Short Book of Motion.pdf',
      mediaSourceId: 'original',
      revision: 'one',
      durationMs: null,
      container: 'pdf',
      sizeBytes: margins.lengthSync(),
    );
    final pdf = Edition(
      id: 'motion-pdf',
      kind: EditionKind.text,
      label: 'PDF',
      files: [source],
      memberIds: const ['margins'],
    );
    final measured = (await tester.runAsync(
      () => measureDownloadedOutline(verified(margins), source),
    ))!;
    final motion = motionNarration(measured);
    final book = Book(
      id: 'motion',
      title: 'A Short Book of Motion',
      author: 'Bookfin',
      editions: [pdf, motion],
    );
    final downloads = LocalFiles()
      ..files[source.key] = margins.uri
      ..files[motion.files.single.key] = Uri.file('/motion.mp3');
    addTearDown(downloads.dispose);
    final document = await tester.runAsync(
      () => loadReadingDocument(verified(margins), source),
    );
    final reader = ReaderSession(
      downloads: downloads,
      store: MemoryResume(),
      load: loadPublication,
      loadDocument: (_, _) async => document!,
    );
    final crossings = Crossings(
      store: MemoryOutlines(),
      measure: (_) async => measured,
      hop: <M, R>(work, input) async => work(input),
    );
    addTearDown(crossings.dispose);
    // A listening move from the start to 60% of The Pendulum.
    final pendulum = motion.files.single.chapters[1].startMs;
    final heardAt =
        pendulum + (motion.files.single.durationMs! - pendulum) * 6 ~/ 10;
    late final Playback playback;
    await tester.runAsync(() async {
      playback = Playback(
        downloads: downloads,
        engine: TestEngine(),
        store: MediumSpy(),
      );
      await playback.bind(account(), [book]);
      await playback.open(book, motion, autoplay: false);
      await playback.seekEdition(heardAt);
      await playback.flush();
      playback.dismissUndo();
    });
    await reader.bind(account(), [book]);
    await tester.runAsync(() => reader.open(book, pdf));
    final landing =
        (await tester.runAsync(
              () => crossings.landing(
                playback.history.first.after,
                from: motion,
                into: pdf,
              ),
            ))!
            as TextLanding;

    // The History opens over the open book before the reader shows it, so
    // Go to cannot show the landing yet.
    final shown = ValueNotifier(false);
    addTearDown(shown.dispose);
    late BuildContext page;
    await tester.pumpWidget(
      MaterialApp(
        theme: bookfinTheme(Brightness.light),
        home: CrossingsScope(
          crossings: crossings,
          child: ReaderScope(
            reader: reader,
            show: (_) {},
            child: Builder(
              builder: (context) {
                page = context;
                return ValueListenableBuilder(
                  valueListenable: shown,
                  builder: (_, shown, _) => shown
                      ? ReaderScreen(reader: reader, onNightChanged: (_) {})
                      : const SizedBox.expand(),
                );
              },
            ),
          ),
        ),
      ),
    );
    openHistory(page, playback, book: book, showing: EditionKind.text);
    await tester.pumpAndSettle();
    Finder inTimeline(Finder finder) =>
        find.descendant(of: find.byType(HistoryTimeline), matching: finder);
    await tester.tap(inTimeline(find.text('→ ${audioTime(heardAt)}')));
    await tester.pumpAndSettle();
    final after = find
        .ancestor(
          of: inTimeline(find.text('AFTER')),
          matching: find.byType(InkWell),
        )
        .first;
    expect(
      find.descendant(of: after, matching: find.text(audioTime(heardAt))),
      findsOneWidget,
    );
    expect(
      find.descendant(of: after, matching: find.textContaining('about')),
      findsNothing,
    );

    // The reader shows the book under the sheet.
    shown.value = true;
    for (var wait = 0; wait < 40 && reader.position == null; wait++) {
      await settleNative(tester);
    }
    await tester.pumpAndSettle();
    final start = reader.position!;

    // The landing's page holds 60% of The Pendulum's characters.
    final landed = landing.place.part + 1;
    expect(landed, greaterThan(8));
    expect(
      find.descendant(of: after, matching: find.text('about p. $landed')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: after, matching: find.text('The Pendulum')),
      findsOneWidget,
    );

    await tester.tap(inTimeline(find.text('AFTER')));
    bool mapped(HistoryEvent<TextPosition> event) =>
        event.counterpartOf != null;
    for (var wait = 0; wait < 40 && !reader.history.any(mapped); wait++) {
      await settleNative(tester);
    }
    await tester.runAsync(reader.flush);

    final moved = reader.history.firstWhere(mapped);
    expect(moved.counterpartOf, isA<AudioPosition>());
    expect(moved.before.anchor, start.anchor);
    expect((reader.visibleAddress! as PdfAddress).sourcePage, landed);

    // The reader closes the book, whose survey of pages ends on real time,
    // as pdf_screen_test.dart closes its books.
    await tester.pumpWidget(const SizedBox());
    reader.dispose();
    await tester.runAsync(playback.close);
    await tester.pump();
  });
}

/// A recording of the margins book, whose chapter marks name its two
/// chapters, read at 12 visible characters a second of [outline], from the
/// start of the first chapter.
Edition motionNarration(TextOutline outline) {
  final first = outline.entries.first.start;
  int at(int characters) => (characters - first) * 1000 ~/ 12;
  return Edition(
    id: 'motion-audio',
    kind: EditionKind.audio,
    label: 'Narrator',
    files: [
      SourceFile(
        itemId: 'motion-audio',
        displayName: 'A Short Book of Motion',
        mediaSourceId: 'm',
        revision: 'a1',
        durationMs: at(outline.length),
        container: 'mp3',
        sizeBytes: 1,
        chapters: [
          for (final entry in outline.entries)
            AudioChapter(entry.title, at(entry.start)),
        ],
      ),
    ],
    memberIds: const ['motion-audio:m'],
  );
}
