// The shared History timeline over the open book, with the session's real
// pager: a reading place reads as its page among the book's pages, which
// follow the text size, and Before shows the place in the reader.
import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/crossings/crossings.dart';
import 'package:bookfin/crossings/scope.dart';
import 'package:bookfin/foundation/theme.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:bookfin/playback/screen.dart' show PlayerView;
import 'package:bookfin/playback/timeline.dart';
import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/scope.dart';
import 'package:bookfin/reader/screen.dart';
import 'package:bookfin/reader/session.dart';
import 'package:bookfin/reader/text_outline.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../crossings/crossings_test.dart' show MemoryOutlines;
import '../playback/mapped_moves_test.dart' show MediumSpy;
import '../playback/playback_test.dart'
    show account, LocalFiles, MemoryResume, TestEngine;
import 'native_reader.dart';
import 'session_test.dart' show book, edition, source;

/// A recording of [twoChapterBook] with a chapter mark for each of its
/// chapters, a minute each.
const narration = Edition(
  id: 'narration',
  kind: EditionKind.audio,
  label: 'Narrator',
  files: [
    SourceFile(
      itemId: 'audio',
      displayName: 'River',
      mediaSourceId: 'm',
      revision: 'a1',
      durationMs: 120000,
      container: 'mp3',
      sizeBytes: 1,
      chapters: [AudioChapter('One', 0), AudioChapter('Two', 60000)],
    ),
  ],
  memberIds: ['audio:m'],
);

/// The book of [edition] and [narration].
final both = Book(
  id: book.id,
  title: book.title,
  author: book.author,
  editions: const [edition, narration],
);

void main() {
  testWidgets('a reading move reads as the page where it ended, and a larger '
      'text size shows a later page; Before shows where it began', (
    tester,
  ) async {
    final downloads = LocalFiles()
      ..files[source.key] = Uri.file('/verified.epub');
    addTearDown(downloads.dispose);
    final store = MemoryResume();
    final opened = twoChapterBook();
    final reader = ReaderSession(
      downloads: downloads,
      store: store,
      load: (_) async => opened,
    );
    await reader.bind(account(), [book]);
    await reader.open(book, edition);
    late BuildContext page;
    await tester.pumpWidget(
      MaterialApp(
        theme: bookfinTheme(Brightness.light),
        home: ReaderScope(
          reader: reader,
          show: (_) {},
          child: Builder(
            builder: (context) {
              page = context;
              return ReaderScreen(reader: reader, onNightChanged: (_) {});
            },
          ),
        ),
      ),
    );
    await waitForPage(tester, reader);
    bool laidOut() => reader.bookMap?.pages != null;
    await settleReader(tester, laidOut, reason: 'the book was not laid out');
    await settleReader(tester, () => reader.position != null);
    final start = reader.position!;
    await finishReader(tester, reader.goToContents('text/s1.xhtml#two'));
    await waitForPage(tester, reader, (shown) => shown.page.section == 1);
    await settleReader(tester, () => reader.position != start);
    final chapterTwo = reader.position!;

    // The move that a search would record. Recording comes with t9-nnon.
    final moved = HistoryEvent(
      id: 'search',
      at: DateTime.now().toUtc(),
      kind: HistoryAction.search,
      before: start,
      after: chapterTwo,
      bookTitle: book.title,
      editionLabel: edition.label,
    );
    final key = account().scope.key;
    await finishReader(tester, reader.flush());
    store.values[key] = {
      ...store.values[key]!,
      'history': [moved.toJson()],
    };
    await finishReader(tester, reader.refreshPersonalRecords());
    expect(reader.history.single.id, 'search');

    openHistory(page, null, book: book, showing: EditionKind.text);
    await tester.pumpAndSettle();
    Finder inTimeline(Finder finder) =>
        find.descendant(of: find.byType(HistoryTimeline), matching: finder);
    int pageOf(TextPosition place) =>
        int.parse(reader.describe(place).short.substring('p. '.length));
    final before = pageOf(chapterTwo);
    expect(before, greaterThan(1));
    expect(inTimeline(find.text('→ p. $before')), findsOneWidget);
    await tester.tap(
      inTimeline(find.text('From search', findRichText: true)),
    );
    await tester.pumpAndSettle();
    expect(
      inTimeline(find.textContaining('Two', findRichText: true)),
      findsWidgets,
    );

    for (var step = 0; step < 4; step++) {
      await finishReader(tester, reader.stepFontSize(larger: true));
    }
    await settleReader(
      tester,
      () => laidOut() && pageOf(chapterTwo) > before,
      reason: 'a larger text size did not move the page later',
    );
    await tester.pump();
    final after = pageOf(chapterTwo);
    expect(inTimeline(find.text('p. $after')), findsOneWidget);
    expect(inTimeline(find.text('p. $before')), findsNothing);

    // The open move shows where it began on its Before tile.
    expect(inTimeline(find.text('p. 1')), findsOneWidget);
    await tester.tap(inTimeline(find.text('BEFORE')));
    await tester.pump();
    await waitForPage(tester, reader, (shown) => shown.page.section == 0);
    await settleReader(
      tester,
      () => find.byType(HistoryTimeline).evaluate().isEmpty,
      reason: 'Before did not close the timeline',
    );
    expect(
      (reader.visibleAddress! as EpubAddress).resource,
      _resourceOf(start),
    );
    await closeNative(tester, reader);
  });

  testWidgets('in the reader, a listening move names where it lands in the '
      'ebook, and Go to shows the landing as a reading move with Undo, '
      'without the player', (tester) async {
    final downloads = LocalFiles()
      ..files[source.key] = Uri.file('/verified.epub')
      ..files[narration.files.single.key] = Uri.file('/narration.mp3');
    addTearDown(downloads.dispose);
    final opened = twoChapterBook();
    final reader = ReaderSession(
      downloads: downloads,
      store: MemoryResume(),
      load: (_) async => opened,
    );
    final listening = MediumSpy();
    late final Playback playback;
    final crossings = Crossings(
      store: MemoryOutlines(),
      measure: (_) async => measureTextOutline(opened),
      hop: <M, R>(work, input) async => work(input),
    );
    addTearDown(crossings.dispose);
    // A listening move from the start to 30 s, half of chapter One. The
    // player runs on real time, as the app's does.
    await tester.runAsync(() async {
      playback = Playback(
        downloads: downloads,
        engine: TestEngine(),
        store: listening,
      );
      await playback.bind(account(), [both]);
      await playback.open(both, narration, autoplay: false);
      await playback.seekEdition(30000);
      await playback.flush();
      playback.dismissUndo();
    });
    final heard = playback.history.first;
    await reader.bind(account(), [both]);
    await reader.open(both, edition);
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
                return ReaderScreen(reader: reader, onNightChanged: (_) {});
              },
            ),
          ),
        ),
      ),
    );
    await waitForPage(tester, reader);
    await settleReader(
      tester,
      () => reader.bookMap?.pages != null,
      reason: 'the book was not laid out',
    );
    await settleReader(tester, () => reader.position != null);
    final start = reader.position!;
    late final Crossing found;
    await finishReader(
      tester,
      crossings
          .landing(heard.after, from: narration, into: edition)
          .then((crossing) => found = crossing),
    );
    final map = reader.bookMap!;
    final landed = map
        .targetAt(map.fractionAt((found as TextLanding).place))
        .page!;
    expect(landed, greaterThan(1));

    openHistory(page, playback, book: both, showing: EditionKind.text);
    await tester.pumpAndSettle();
    Finder inTimeline(Finder finder) =>
        find.descendant(of: find.byType(HistoryTimeline), matching: finder);
    await tester.tap(
      inTimeline(find.text('Ahead 30 s', findRichText: true)),
    );
    await tester.pumpAndSettle();
    final after = find
        .ancestor(
          of: inTimeline(find.text('AFTER')),
          matching: find.byType(InkWell),
        )
        .first;
    expect(
      find.descendant(of: after, matching: find.text('about p. $landed')),
      findsOneWidget,
    );

    listening.listening.clear();
    await tester.tap(inTimeline(find.text('AFTER')));
    await tester.pump();
    await settleReader(
      tester,
      () => reader.history.isNotEmpty && reader.position != start,
      reason: 'Go to did not move the reader',
    );
    await finishReader(tester, reader.flush());

    final moved = reader.history.first;
    expect(moved.kind, HistoryAction.historyRestore);
    expect(moved.counterpartOf, isA<AudioPosition>());
    expect((moved.counterpartOf! as AudioPosition).milliseconds, 30000);
    expect(reader.undoOffer?.action, same(moved));
    expect(reader.describe(reader.position!).short, 'p. $landed');
    expect(find.byType(PlayerView), findsNothing);
    expect(playback.editionMilliseconds, 30000);
    expect(listening.listening, isEmpty);
    await closeNative(tester, reader);
    await tester.runAsync(playback.close);
  });
}

/// The section of [place], from its saved anchor.
String _resourceOf(TextPosition place) =>
    RegExp(r'"resource":"([^"]+)"').firstMatch(place.anchor)!.group(1)!;
