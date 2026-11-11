import 'dart:convert';

import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/foundation/theme.dart';
import 'package:bookfin/foundation/time.dart';
import 'package:bookfin/playback/records.dart';
import 'package:bookfin/playback/timeline.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

// The History sheet over an open edition shows each medium as its own
// track: listening in the left lane of the rail and reading in the right
// lane. A row keeps its own place in its own words. A tile names where Go
// to lands in the open edition, or says why it opens the other screen,
// before the tap. See docs/plans/cross-edition-places.md, "What the person
// sees".

AudioPosition listening(int milliseconds) => AudioPosition(
  editionId: 'audio',
  sourceKey: 'file',
  revision: 'r',
  milliseconds: milliseconds,
);

TextPosition reading(int page) => TextPosition(
  editionId: 'epub',
  sourceKey: 'epub-file',
  revision: 'r',
  anchor: jsonEncode({'page': page}),
);

/// A listening place reads as its time, and a reading place as its page.
PlaceWords describe(Place place) => switch (place) {
  AudioPosition(:final milliseconds) => (
    short: audioTime(milliseconds),
    chapter: 'Arrival',
    quote: null,
    along: AlongAudio(milliseconds),
  ),
  TextPosition() => (
    short: 'p. ${jsonDecode(place.anchor)['page']}',
    chapter: 'Chapter 4',
    quote: null,
    along: AlongText(page: jsonDecode(place.anchor)['page'] as int),
  ),
};

final now = DateTime.now().toUtc();

HistoryEvent<Place> move(
  String id,
  HistoryAction kind,
  Place before,
  Place after, {
  int minutesAgo = 1,
  Place? counterpartOf,
}) => HistoryEvent<Place>(
  id: id,
  at: now.subtract(Duration(minutes: minutesAgo)),
  kind: kind,
  before: before,
  after: after,
  bookTitle: 'Moby-Dick',
  editionLabel: 'Unabridged',
  counterpartOf: counterpartOf,
  matchedBy: counterpartOf == null ? null : MatchedBy.chapters,
);

/// A listening move of 40 s, and a reading move of 12 pages.
final heard = move(
  'heard',
  HistoryAction.seek,
  listening(3695000),
  listening(3735000),
);
final read = move(
  'read',
  HistoryAction.seek,
  reading(122),
  reading(134),
  minutesAgo: 2,
);

/// The note of a place whose chapters do not match.
const unmatched =
    'The chapters of these editions do not match, so this opens the '
    'audiobook.';

void main() {
  /// Shows [entries] on a phone that is 360 points wide, with the system
  /// text size at 130%, as the narrowest common Android phone with large
  /// text, with [landingOf] as the words of where Go to lands.
  Future<void> show(
    WidgetTester tester,
    List<TimelineEntry> entries, {
    LandingWords Function(Place place)? landingOf,
  }) async {
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        theme: bookfinTheme(Brightness.light),
        home: Scaffold(
          body: HistoryTimeline(
            entries: ValueNotifier(entries),
            describe: describe,
            landingOf: landingOf,
            onGoBefore: (_) {},
            onGoTo: (_) {},
            onRename: (_) {},
            onDelete: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The tile of an open entry whose role word is [role], such as AFTER.
  Finder tile(String role) =>
      find.ancestor(of: find.text(role), matching: find.byType(InkWell)).first;

  Finder inTile(String role, Finder finder) =>
      find.descendant(of: tile(role), matching: finder);

  /// The glyph of a medium, which assistive technology reads as [medium].
  Finder glyph(String medium) => find.byWidgetPredicate(
    (widget) => widget is Icon && widget.semanticLabel == medium,
  );

  /// In the reader: a listening place lands about 100 pages later, by
  /// matched chapters.
  LandingWords inReader(Place place) => switch (place) {
    AudioPosition(:final milliseconds) => (
      words: (
        short: 'about p. ${milliseconds ~/ 30000}',
        chapter: 'Chapter 4',
        quote: null,
        along: null,
      ),
      note: null,
    ),
    TextPosition() => (words: describe(place), note: null),
  };

  testWidgets('a tile of a listening move in the reader names where Go to '
      'lands in the ebook, and the row keeps its own time', (tester) async {
    await show(tester, [ActionEntry(heard)], landingOf: inReader);

    expect(find.text('→ 1:02:15'), findsOneWidget);
    await tester.tap(find.text('Moved ahead 40 s', findRichText: true));
    await tester.pumpAndSettle();

    expect(inTile('BEFORE', find.text('about p. 123')), findsOneWidget);
    expect(inTile('AFTER', find.text('about p. 124')), findsOneWidget);
    expect(inTile('AFTER', find.text('Chapter 4')), findsOneWidget);
    expect(find.text('1:02:15'), findsNothing);
  });

  testWidgets('a tile of a place that has no landing says why, and which '
      'screen Go to opens, in full', (tester) async {
    await show(tester, [
      ActionEntry(heard),
    ], landingOf: (place) => (words: describe(place), note: unmatched));

    await tester.tap(find.text('Moved ahead 40 s', findRichText: true));
    await tester.pumpAndSettle();

    for (final role in ['BEFORE', 'AFTER']) {
      final note = inTile(role, find.text(unmatched));
      expect(note, findsOneWidget);
      expect(
        tester.renderObject<RenderParagraph>(note).didExceedMaxLines,
        isFalse,
      );
    }
    expect(inTile('AFTER', find.text('1:02:15')), findsOneWidget);
  });

  testWidgets('without landing words, a tile names its own place', (
    tester,
  ) async {
    await show(tester, [ActionEntry(heard)]);

    await tester.tap(find.text('Moved ahead 40 s', findRichText: true));
    await tester.pumpAndSettle();

    expect(inTile('AFTER', find.text('1:02:15')), findsOneWidget);
  });

  testWidgets('a timeline of both media puts listening in the left lane and '
      'reading in the right lane', (tester) async {
    await show(tester, [ActionEntry(heard), ActionEntry(read)]);

    final listened = tester.getCenter(glyph('Listening'));
    final reread = tester.getCenter(glyph('Reading'));

    expect(listened.dx, lessThan(reread.dx));
    // Each label starts after both lanes.
    for (final label in ['Moved ahead 40 s', 'Moved ahead 12 pages']) {
      expect(
        tester.getTopLeft(find.text(label, findRichText: true)).dx,
        greaterThan(reread.dx),
      );
    }
  });

  group('a mapped move reads as where it went in the other edition', () {
    final cases = [
      (
        HistoryAction.historyRestore,
        listening(1000),
        reading(1),
        'Went to about where you listened',
      ),
      (
        HistoryAction.bookmarkRestore,
        listening(1000),
        reading(1),
        'Went to about a listening bookmark',
      ),
      (
        HistoryAction.historyRestore,
        reading(1),
        listening(1000),
        'Went to about where you read',
      ),
      (
        HistoryAction.bookmarkRestore,
        reading(1),
        listening(1000),
        'Went to about a reading bookmark',
      ),
    ];
    for (final (kind, other, own, label) in cases) {
      testWidgets(label, (tester) async {
        await show(tester, [
          ActionEntry(move('mapped', kind, own, own, counterpartOf: other)),
        ]);

        expect(find.text(label, findRichText: true), findsOneWidget);
      });
    }
  });
}
