// The reader estimates the reading time left in the chapter and in the book
// from the person's own reading speed. The bottom bar's label adds the time
// left in the chapter, and the contents sheet shows the time left in the
// book.
import 'package:bookfin/foundation/time.dart';
import 'package:bookfin/reader/epub/viewport.dart';
import 'package:bookfin/reader/reading_speed.dart';
import 'package:bookfin/reader/screen.dart';
import 'package:bookfin/reader/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback/playback_test.dart' show MemoryResume;
import 'native_reader.dart';
import 'reading_speed_test.dart' show MemorySpeedStore;

/// The speed at which the person in these tests reads, in visible
/// characters a minute.
const _perMinute = 1000;

/// A clock that the test moves as the person reads.
class _Clock {
  DateTime now = DateTime(2026, 11, 9, 21);
}

/// The person reads the shown page at [_perMinute] characters a minute on
/// [clock], then turns forward, and the next page shows.
Future<void> _readPage(
  WidgetTester tester,
  ReaderSession reader,
  _Clock clock,
) async {
  final page = shownOf(reader)!.page;
  final characters = page.endVisible - page.startVisible;
  clock.now = clock.now.add(
    Duration(milliseconds: (characters / _perMinute * 60000).round()),
  );
  await finishReader(tester, reader.move(true));
  await waitForPage(tester, reader, (shown) => !identical(shown.page, page));
}

/// Waits until every section of the open book is laid out, so the book's
/// visible characters are known.
Future<void> _laidOut(WidgetTester tester, ReaderSession reader) =>
    settleReader(
      tester,
      () => reader.pager!.bookPages.value.complete,
      reason: 'the book was never laid out',
    );

/// The visible characters of the shown page's section from the page's
/// start on, and of the sections after it. Each section of the test book
/// starts a chapter.
({int chapter, int book}) _charactersLeft(ReaderSession reader) {
  final page = shownOf(reader)!.page;
  final parts = reader.pager!.bookPages.value.parts;
  int length(int part) => parts[part]!.visible!.length;
  final chapter = length(page.section) - page.startVisible;
  var book = chapter;
  for (var part = page.section + 1; part < parts.length; part++) {
    book += length(part);
  }
  return (chapter: chapter, book: book);
}

/// The estimate of [characters] read at [_perMinute], as the reader
/// shows it.
String _time(int characters) =>
    estimatedTime(Duration(milliseconds: characters * 60000 ~/ _perMinute));

void main() {
  testWidgets('no time left shows before enough page turns', (tester) async {
    final clock = _Clock();
    final reader = await openNative(
      tester,
      speed: ReadingSpeed(MemorySpeedStore(), clock: () => clock.now),
    );
    for (var page = 0; page < 4; page++) {
      await _readPage(tester, reader, clock);
    }
    await _laidOut(tester, reader);
    await tester.pump();
    expect(find.textContaining('left in chapter'), findsNothing);
    await closeNative(tester, reader);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('the label shows the minutes left in the chapter at the '
      'reader\'s speed', (tester) async {
    final clock = _Clock();
    final reader = await openNative(
      tester,
      speed: ReadingSpeed(MemorySpeedStore(), clock: () => clock.now),
    );
    for (var page = 0; page < 5; page++) {
      await _readPage(tester, reader, clock);
    }
    await _laidOut(tester, reader);
    await tester.pump();
    final left = _charactersLeft(reader);
    final number = reader.pager!.pageNumber.value!;
    final chapter = shownOf(reader)!.page.section == 0 ? 'One' : 'Two';
    expect(
      find.bySemanticsLabel(
        '$chapter · Page ${number.number} of ${number.count} · '
        '${_time(left.chapter)} left in chapter',
      ),
      findsOneWidget,
    );
    await closeNative(tester, reader);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('the contents sheet shows the time left in the book', (
    tester,
  ) async {
    final clock = _Clock();
    final reader = await openNative(
      tester,
      speed: ReadingSpeed(MemorySpeedStore(), clock: () => clock.now),
    );
    for (var page = 0; page < 5; page++) {
      await _readPage(tester, reader, clock);
    }
    await _laidOut(tester, reader);
    await tester.tap(find.byTooltip('Contents'));
    await settleReader(
      tester,
      () => find.byType(ReaderContentsPanel).evaluate().isNotEmpty,
    );
    await tester.pump(const Duration(seconds: 1));
    expect(
      find.text('${_time(_charactersLeft(reader).book)} left in book'),
      findsOneWidget,
    );
    await closeNative(tester, reader);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('a new reading speed redraws the label, not the page', (
    tester,
  ) async {
    final clock = _Clock();
    final speed = ReadingSpeed(MemorySpeedStore(), clock: () => clock.now);
    final reader = await openNative(tester, speed: speed);
    for (var page = 0; page < 5; page++) {
      await _readPage(tester, reader, clock);
    }
    await _laidOut(tester, reader);
    await tester.pump();
    final before = find.textContaining('left in chapter').evaluate().single;
    final shownBefore = (before.widget as Text).data;

    final rebuilt = <Widget>[];
    debugOnRebuildDirtyWidget = (element, _) => rebuilt.add(element.widget);
    try {
      // Five slow pages, as the speed sees them, without a turn of the
      // shown page.
      for (var page = 0; page < 5; page++) {
        clock.now = clock.now.add(const Duration(minutes: 9));
        speed.pageShown(read: 1000);
      }
      await tester.pump();
    } finally {
      debugOnRebuildDirtyWidget = null;
    }
    final after = find.textContaining('left in chapter').evaluate().single;
    expect((after.widget as Text).data, isNot(shownBefore));
    expect(rebuilt.whereType<EpubViewport>(), isEmpty);
    expect(rebuilt.whereType<ReaderScreen>(), isEmpty);
    await closeNative(tester, reader);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('a speed store that cannot be read leaves the reading place '
      'and the bookmarks untouched', (tester) async {
    final records = MemoryResume();
    final clock = _Clock();
    final first = await openNative(
      tester,
      store: records,
      speed: ReadingSpeed(MemorySpeedStore(), clock: () => clock.now),
    );
    for (var page = 0; page < 3; page++) {
      await _readPage(tester, first, clock);
    }
    await finishReader(tester, first.addBookmark(title: 'River mark'));
    final place = first.position!.anchor;
    await closeNative(tester, first);

    final speed = ReadingSpeed(MemorySpeedStore()..unreadable = true);
    await tester.runAsync(speed.restore);
    final reader = await openNative(tester, store: records, speed: speed);
    expect(speed.charactersPerMinute.value, isNull);
    expect(reader.position!.anchor, place);
    expect(reader.bookmarks.map((mark) => mark.title), ['River mark']);
    await closeNative(tester, reader);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
