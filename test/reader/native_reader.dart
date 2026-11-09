// Helpers for widget tests of the reader screen with the session's real
// pager. The pager prepares sections in worker isolates and lays out pages
// in steps that the scheduler runs between frames, so a test lets real time
// pass for the workers and pumps frames for the steps.
import 'dart:async';

import 'package:bookfin/foundation/theme.dart';
import 'package:bookfin/reader/epub/pager.dart';
import 'package:bookfin/reader/screen.dart';
import 'package:bookfin/reader/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_epub_viewer/publication.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback/playback_test.dart' show account, LocalFiles, MemoryResume;
import 'epub/page_source_test.dart' show paragraphs;
import 'session_native_test.dart' show navBook;
import 'session_test.dart' show book, edition, source;

/// A two-chapter book. The first chapter starts with a link to the
/// paragraph with the id "far", deep in the second chapter. Each chapter
/// fills several pages.
Publication twoChapterBook() => Publication.admit(
  navBook(
    [
      '<h1 id="one">One</h1>'
          '<p><a href="s1.xhtml#far">Go to the far shore</a></p>'
          '${paragraphs(24)}',
      '<h1 id="two">Two</h1>${paragraphs(24, label: 'Near')}'
          '<p id="far">The far shore at last.</p>${paragraphs(4)}',
    ],
    [('One', 'text/s0.xhtml#one'), ('Two', 'text/s1.xhtml#two')],
  ),
);

/// Pumps frames and lets real time pass until [done] holds, for up to 30
/// seconds of real time.
Future<void> settleReader(
  WidgetTester tester,
  bool Function() done, {
  String reason = 'the reader did not settle',
}) async {
  final clock = Stopwatch()..start();
  while (clock.elapsed < const Duration(seconds: 30)) {
    if (done()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)),
    );
    await tester.pump(const Duration(milliseconds: 16));
  }
  fail(reason);
}

/// Pumps frames and lets real time pass until [work] completes. The
/// session's record writes and the pager's layout need both.
Future<void> finishReader(WidgetTester tester, Future<void> work) async {
  var ended = false;
  unawaited(work.whenComplete(() => ended = true));
  await settleReader(tester, () => ended, reason: 'the work did not end');
  await work;
}

/// The page that the open book's pager shows, or null.
ShownPage? shownOf(ReaderSession reader) => reader.pager?.shown.value;

/// Waits until the open book's pager shows a page that passes [test], and
/// returns it. Without [test], any page passes.
Future<ShownPage> waitForPage(
  WidgetTester tester,
  ReaderSession reader, [
  bool Function(ShownPage shown)? test,
]) async {
  await settleReader(tester, () {
    final shown = shownOf(reader);
    return shown != null && (test?.call(shown) ?? true);
  }, reason: 'the pager showed no such page');
  return shownOf(reader)!;
}

/// Opens [publication], by default [twoChapterBook], in a new session of
/// the test account and shows the reader screen in the cream theme. It
/// waits until the pager shows the first page and the session has the
/// visible place and the book map. The test ends with [closeNative].
Future<ReaderSession> openNative(
  WidgetTester tester, {
  Publication? publication,
  ReadingStore? store,
}) async {
  final downloads = LocalFiles()
    ..files[source.key] = Uri.file('/verified.epub');
  final opened = publication ?? twoChapterBook();
  final reader = ReaderSession(
    downloads: downloads,
    store: store ?? MemoryResume(),
    load: (_) async => opened,
  );
  addTearDown(downloads.dispose);
  await reader.bind(account(), [book]);
  await reader.open(book, edition);
  await tester.pumpWidget(
    MaterialApp(
      theme: bookfinTheme(Brightness.light),
      home: ReaderScreen(reader: reader, onNightChanged: (_) {}),
    ),
  );
  await waitForPage(tester, reader);
  await settleReader(
    tester,
    () => reader.visibleAddress != null && reader.bookMap != null,
    reason: 'the session has no visible place or no book map',
  );
  return reader;
}

/// Closes the reader screen and [reader], saves its records, and runs the
/// layout steps that were still scheduled, which then do nothing. Flutter
/// checks for pending timers before tear-down callbacks run, so each test
/// calls this at its end.
Future<void> closeNative(WidgetTester tester, ReaderSession reader) async {
  await tester.pumpWidget(const SizedBox());
  reader.dispose();
  await finishReader(tester, reader.flush());
  await tester.pump();
}
