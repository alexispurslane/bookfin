// The shared History timeline over the open book, with the session's real
// pager: a reading place reads as its page among the book's pages, which
// follow the text size, and Go back shows the place in the reader.
import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/foundation/theme.dart';
import 'package:bookfin/playback/records.dart';
import 'package:bookfin/playback/timeline.dart';
import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/scope.dart';
import 'package:bookfin/reader/screen.dart';
import 'package:bookfin/reader/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback/playback_test.dart' show account, LocalFiles, MemoryResume;
import 'native_reader.dart';
import 'session_test.dart' show book, edition, source;

void main() {
  testWidgets('a reading move reads as the page where it ended, and a larger '
      'text size shows a later page; Go back shows where it began', (
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
    expect(inTimeline(find.text('p. $before')), findsOneWidget);
    await tester.tap(
      inTimeline(find.text('Went to a search result', findRichText: true)),
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

    await tester.tap(inTimeline(find.text('Go back to p. 1')));
    await tester.pump();
    await waitForPage(tester, reader, (shown) => shown.page.section == 0);
    await settleReader(
      tester,
      () => find.byType(HistoryTimeline).evaluate().isEmpty,
      reason: 'Go back did not close the timeline',
    );
    expect(
      (reader.visibleAddress! as EpubAddress).resource,
      _resourceOf(start),
    );
    await closeNative(tester, reader);
  });
}

/// The section of [place], from its saved anchor.
String _resourceOf(TextPosition place) =>
    RegExp(r'"resource":"([^"]+)"').firstMatch(place.anchor)!.group(1)!;
