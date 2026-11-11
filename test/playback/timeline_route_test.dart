import 'dart:convert';

import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/foundation/theme.dart';
import 'package:bookfin/foundation/time.dart';
import 'package:bookfin/playback/records.dart';
import 'package:bookfin/playback/timeline.dart';
import 'package:bookfin/reader/place_words.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

// The History sheet shows each move as a route with two ends: a closed row
// names the place where the move went, and an open move offers its Before
// and After places as two tiles of one size, in the order that they
// happened. An entry that did not move, and a bookmark, offer one place.
// See docs/plans/history-choice.md, design B.

AudioPosition listening(int milliseconds) => AudioPosition(
  editionId: 'audio',
  sourceKey: 'file',
  revision: 'r',
  milliseconds: milliseconds,
);

TextPosition reading(String quote) => TextPosition(
  editionId: 'epub',
  sourceKey: 'epub-file',
  revision: 'r',
  anchor: jsonEncode({'cfi': '/6/4', 'quote': quote}),
);

const longChapter = 'Chapter 12 · The Night of the Morlocks and the Fire';

/// A listening place reads as its time, as `Playback.describe` reads it,
/// and a reading place as `describeTextPlace` reads a place outside the
/// open book: the first words of its quote.
PlaceWords describe(Place place) => switch (place) {
  AudioPosition(:final milliseconds) => (
    short: audioTime(milliseconds),
    chapter: longChapter,
    quote: null,
    along: AlongAudio(milliseconds),
  ),
  final TextPosition text => describeTextPlace(text),
};

final now = DateTime.now().toUtc();

HistoryEvent<Place> move(
  String id,
  HistoryAction kind,
  Place before,
  Place after, {
  int minutesAgo = 1,
  String? device,
}) => HistoryEvent<Place>(
  id: id,
  at: now.subtract(Duration(minutes: minutesAgo)),
  kind: kind,
  before: before,
  after: after,
  bookTitle: 'The Time Machine',
  editionLabel: 'Unabridged',
  device: device,
);

// A seek of 40.8 seconds between two times that read 40 seconds apart.
final seek = move(
  'seek',
  HistoryAction.seek,
  listening(3775900),
  listening(3735100),
  minutesAgo: 2,
);
final pause = move(
  'pause',
  HistoryAction.pause,
  listening(3735100),
  listening(3735100),
  minutesAgo: 3,
);
final chapter = move(
  'chapter',
  HistoryAction.chapter,
  reading(
    'The thing the Time Traveller held in his hand was a glittering '
    'metallic framework',
  ),
  reading(
    'I told some of you last Thursday of the principles of the Time Machine',
  ),
  minutesAgo: 4,
);
final mark = Bookmark<Place>(
  id: 'mark',
  position: listening(75000),
  createdAt: now.subtract(const Duration(minutes: 5)),
  bookTitle: 'The Time Machine',
  editionLabel: 'Unabridged',
);

void main() {
  late List<Object> reports;
  setUp(() => reports = []);

  /// Shows [entries] on a phone that is 360 points wide, with the system
  /// text size at 130%, as the narrowest common Android phone with large
  /// text. Returns the entries, which a test changes as the records change.
  Future<ValueNotifier<List<TimelineEntry>>> showTimeline(
    WidgetTester tester,
    List<TimelineEntry> shown,
  ) async {
    final entries = ValueNotifier(shown);
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
            entries: entries,
            describe: describe,
            onGoBefore: (event) => reports.add(('before', event)),
            onGoTo: (entry) => reports.add(('go', entry)),
            onRename: (bookmark) => reports.add(('rename', bookmark)),
            onDelete: (entry) => reports.add(('delete', entry)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return entries;
  }

  final everything = <TimelineEntry>[
    ActionEntry(seek),
    ActionEntry(pause),
    ActionEntry(chapter),
    BookmarkEntry(mark),
  ];

  Finder row(String label) => find.ancestor(
    of: find.text(label, findRichText: true),
    matching: find.byType(InkWell),
  );

  Future<void> open(WidgetTester tester, String label) async {
    await tester.tap(find.text(label, findRichText: true));
    await tester.pumpAndSettle();
  }

  /// The tile whose role word is [role], such as BEFORE.
  Finder tile(String role) =>
      find.ancestor(of: find.text(role), matching: find.byType(InkWell)).first;

  /// The Name or Rename button of an open bookmark.
  Finder rename() => find.byTooltip('Name');

  /// The reports, with each bookmark entry as its bookmark.
  List<Object> bookmarkReports() => [
    for (final report in reports)
      switch (report) {
        (final String kind, BookmarkEntry(:final bookmark)) => (kind, bookmark),
        _ => report,
      },
  ];

  group('a move is a route with two ends', () {
    testWidgets('a closed move shows the place where it went behind an '
        'arrow, and an entry that did not move shows its place alone', (
      tester,
    ) async {
      await showTimeline(tester, everything);
      expect(find.text('→ 1:02:15'), findsOneWidget);
      expect(find.text('1:02:15'), findsOneWidget);
    });

    testWidgets('an open move shows Before on the left and After on the '
        'right, as two tiles of one size', (tester) async {
      await showTimeline(tester, everything);
      await open(tester, 'Back 40 s');
      final before = tester.getRect(tile('BEFORE'));
      final after = tester.getRect(tile('AFTER'));
      expect(
        find.descendant(of: tile('BEFORE'), matching: find.text('1:02:55')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: tile('AFTER'), matching: find.text('1:02:15')),
        findsOneWidget,
      );
      expect(before.right, lessThan(after.left));
      expect(before.top, after.top);
      expect(before.size, after.size);
    });

    testWidgets('a tap on Before goes to the place where the move began', (
      tester,
    ) async {
      await showTimeline(tester, everything);
      await open(tester, 'Back 40 s');
      await tester.tap(tile('BEFORE'));
      expect(reports, [('before', seek)]);
    });

    testWidgets('a tap on After goes to the place where the move ended', (
      tester,
    ) async {
      await showTimeline(tester, everything);
      await open(tester, 'Back 40 s');
      await tester.tap(tile('AFTER'));
      final (kind, entry) = reports.single as (String, ActionEntry);
      expect((kind, entry.event), ('go', seek));
    });

    testWidgets('the timeline never offers to go back', (tester) async {
      await showTimeline(tester, everything);
      for (final label in ['Back 40 s', 'Paused', 'Changed chapter']) {
        await open(tester, label);
        expect(find.textContaining('Go back'), findsNothing);
      }
    });

    testWidgets('an entry that did not move offers its one place', (
      tester,
    ) async {
      await showTimeline(tester, everything);
      await open(tester, 'Paused');
      expect(find.text('BEFORE'), findsNothing);
      expect(find.text('AFTER'), findsNothing);
      expect(
        find.descendant(of: tile('GO TO'), matching: find.text('1:02:15')),
        findsOneWidget,
      );
      await tester.tap(tile('GO TO'));
      final (kind, entry) = reports.single as (String, ActionEntry);
      expect((kind, entry.event), ('go', pause));
    });

    testWidgets('a play-state entry whose two position samples differ by '
        'milliseconds shows one place', (tester) async {
      // Playback records Played, Interrupted and Finished from the
      // position sample before the change to the one that changed it.
      final kinds = {
        HistoryAction.resume: 'Played',
        HistoryAction.interruption: 'Interrupted',
        HistoryAction.completion: 'Finished',
      };
      await showTimeline(tester, [
        for (final (index, kind) in kinds.keys.indexed)
          ActionEntry(
            move(
              kind.name,
              kind,
              listening(4410000),
              listening(4410180),
              minutesAgo: index + 1,
            ),
          ),
      ]);
      expect(find.text('1:13:30'), findsNWidgets(3));
      expect(find.textContaining('→'), findsNothing);
      for (final label in kinds.values) {
        await open(tester, label);
        expect(find.text('BEFORE'), findsNothing, reason: label);
        expect(find.text('GO TO'), findsOneWidget, reason: label);
      }
    });

    testWidgets('an open without another device is one place', (tester) async {
      final visit = reading('The Time Traveller smiled round at us.');
      await showTimeline(tester, [
        ActionEntry(move('visit', HistoryAction.open, visit, visit)),
      ]);
      await open(tester, 'Opened');
      expect(find.text('BEFORE'), findsNothing);
      expect(find.text('GO TO'), findsOneWidget);
    });

    testWidgets('a bookmark offers its place and a name', (tester) async {
      await showTimeline(tester, everything);
      await open(tester, 'Bookmark');
      await tester.tap(tile('GO TO'));
      await tester.tap(rename());
      expect(bookmarkReports(), [('go', mark), ('rename', mark)]);
    });
  });

  group('a swipe deletes', () {
    testWidgets('a swipe toward the start of a row reports Delete, and the '
        'row springs back until the records change', (tester) async {
      final entries = await showTimeline(tester, everything);
      final before = tester.getRect(row('Paused').first);
      await tester.drag(row('Paused').first, const Offset(-300, 0));
      await tester.pumpAndSettle();
      final (kind, entry) = reports.single as (String, ActionEntry);
      expect((kind, entry.event), ('delete', pause));
      expect(tester.getRect(row('Paused').first), before);
      entries.value = [
        for (final entry in everything)
          if (entry.id != pause.id) entry,
      ];
      await tester.pumpAndSettle();
      expect(find.text('Paused', findRichText: true), findsNothing);
    });

    testWidgets('a swipe on an open bookmark reports Delete', (tester) async {
      await showTimeline(tester, everything);
      await open(tester, 'Bookmark');
      await tester.drag(row('Bookmark').first, const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(bookmarkReports(), [('delete', mark)]);
      expect(find.text('GO TO'), findsOneWidget);
    });

    testWidgets('a row part way through a swipe shows the delete glyph '
        'behind it', (tester) async {
      await showTimeline(tester, everything);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
      final swipe = await tester.startGesture(
        tester.getCenter(row('Paused').first),
      );
      await swipe.moveBy(const Offset(-40, 0));
      await swipe.moveBy(const Offset(-60, 0));
      await tester.pump();
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
      expect(reports, isEmpty);
      await swipe.up();
      await tester.pumpAndSettle();
    });

    testWidgets('a swipe toward the end of a row deletes nothing', (
      tester,
    ) async {
      await showTimeline(tester, everything);
      await tester.drag(row('Paused').first, const Offset(300, 0));
      await tester.pumpAndSettle();
      expect(reports, isEmpty);
    });

    testWidgets('the Delete action of a row reports Delete without a swipe', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await showTimeline(tester, everything);
      tester.semantics.customAction(
        find.semantics.byLabel(RegExp('Paused')),
        const CustomSemanticsAction(label: 'Delete'),
      );
      final (kind, entry) = reports.single as (String, ActionEntry);
      expect((kind, entry.event), ('delete', pause));
      semantics.dispose();
    });
  });

  testWidgets('a tile of a place outside the open book shows its quote '
      'under its first words', (tester) async {
    await showTimeline(tester, everything);
    await open(tester, 'Changed chapter');
    expect(
      find.descendant(
        of: tile('BEFORE'),
        matching: find.text(
          '“The thing the Time Traveller held in his hand was a glittering '
          'metallic framework”',
        ),
      ),
      findsOneWidget,
    );
  });

  group('an open entry keeps one shape', () {
    testWidgets('an open row is as tall as a closed row and still shows its '
        'place', (tester) async {
      await showTimeline(tester, everything);
      for (final (label, place) in [
        ('Back 40 s', '→ 1:02:15'),
        ('Paused', '1:02:15'),
        ('Changed chapter', '→ “I told some of you'),
        ('Bookmark', '1:15'),
      ]) {
        final closed = tester.getRect(row(label).first).height;
        await open(tester, label);
        expect(tester.getRect(row(label).first).height, closed, reason: label);
        expect(
          find.descendant(
            of: row(label).first,
            matching: find.textContaining(place),
          ),
          findsOneWidget,
          reason: label,
        );
      }
    });

    testWidgets('the route spans its row, from the time to the place', (
      tester,
    ) async {
      await showTimeline(tester, everything);
      await open(tester, 'Back 40 s');
      final line = tester.getRect(row('Back 40 s').first);
      expect(tester.getRect(tile('BEFORE')).left, line.left);
      expect(tester.getRect(tile('AFTER')).right, line.right);
      await open(tester, 'Paused');
      final pausedLine = tester.getRect(row('Paused').first);
      expect(tester.getRect(tile('GO TO')).left, pausedLine.left);
      expect(tester.getRect(tile('GO TO')).right, pausedLine.right);
    });

    testWidgets('Name sits at the right end of the Go to line of a bookmark, '
        'as tall as the tile and at least 48 points tall', (tester) async {
      await showTimeline(tester, everything);
      await open(tester, 'Bookmark');
      final line = tester.getRect(row('Bookmark').first);
      final place = tester.getRect(tile('GO TO'));
      final name = tester.getRect(rename());
      expect(place.left, line.left);
      expect(name.right, line.right);
      expect(name.left, greaterThan(place.right));
      expect(name.top, place.top);
      expect(name.height, place.height);
      expect(name.height, greaterThanOrEqualTo(48));
    });

    testWidgets('each line of a tile stays on one line on a narrow phone '
        'with large text', (tester) async {
      await showTimeline(tester, everything);
      for (final (label, roles) in [
        ('Changed chapter', ['BEFORE', 'AFTER']),
        ('Back 40 s', ['BEFORE', 'AFTER']),
        ('Paused', ['GO TO']),
      ]) {
        await open(tester, label);
        for (final role in roles) {
          final lines = find.descendant(
            of: tile(role),
            matching: find.byType(RichText),
          );
          expect(lines, findsNWidgets(3), reason: '$label $role');
          for (final text in lines.evaluate()) {
            expect(
              lineCount(text.renderObject! as RenderParagraph),
              1,
              reason: '$label $role: ${(text.widget as RichText).text}',
            );
          }
        }
      }
    });
  });

  group("a move's distance agrees with the places that it shows", () {
    testWidgets('a seek between 1:02:55 and 1:02:15 moved back 40 s', (
      tester,
    ) async {
      await showTimeline(tester, [ActionEntry(seek)]);
      expect(find.text('Back 40 s', findRichText: true), findsOneWidget);
    });

    testWidgets('a seek within one shown second reads as its verb alone', (
      tester,
    ) async {
      await showTimeline(tester, [
        ActionEntry(
          move(
            'nudge',
            HistoryAction.seek,
            listening(3775900),
            listening(3775100),
          ),
        ),
      ]);
      expect(find.text('Moved', findRichText: true), findsOneWidget);
      await open(tester, 'Moved');
      expect(
        find.descendant(of: tile('BEFORE'), matching: find.text('1:02:55')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: tile('AFTER'), matching: find.text('1:02:55')),
        findsOneWidget,
      );
    });

    testWidgets('a move of a minute or more names minutes and seconds', (
      tester,
    ) async {
      await showTimeline(tester, [
        ActionEntry(
          move(
            'ahead',
            HistoryAction.seek,
            listening(600000),
            listening(691000),
          ),
        ),
      ]);
      expect(find.text('Ahead 1 m 31 s', findRichText: true), findsOneWidget);
    });

    testWidgets('a move of an hour or more names hours, minutes and seconds', (
      tester,
    ) async {
      await showTimeline(tester, [
        ActionEntry(
          move('far', HistoryAction.jump, listening(900), listening(3725100)),
        ),
      ]);
      expect(
        find.text('Ahead 1 h 2 m 5 s', findRichText: true),
        findsOneWidget,
      );
    });
  });

  group('an open from another device', () {
    testWidgets('a listening open names the device whose place it took', (
      tester,
    ) async {
      await showTimeline(tester, [
        ActionEntry(
          move(
            'opened',
            HistoryAction.open,
            listening(2400000),
            listening(4200000),
            device: 'Pixel 8',
          ),
        ),
      ]);
      expect(find.text('From Pixel 8', findRichText: true), findsOneWidget);
    });

    testWidgets('a reading open names the device whose place it took', (
      tester,
    ) async {
      await showTimeline(tester, [
        ActionEntry(
          move(
            'opened',
            HistoryAction.open,
            reading('A river follows the road.'),
            reading('Where the road ends.'),
            device: 'Tablet',
          ),
        ),
      ]);
      expect(find.text('From Tablet', findRichText: true), findsOneWidget);
    });

    testWidgets('an open without a device reads Opened', (tester) async {
      final visit = reading('The Time Traveller smiled round at us.');
      await showTimeline(tester, [
        ActionEntry(move('visit', HistoryAction.open, visit, visit)),
      ]);
      expect(find.text('Opened', findRichText: true), findsOneWidget);
    });
  });
}

/// The number of lines that [paragraph] takes, measured against one line
/// of its own style and text size.
int lineCount(RenderParagraph paragraph) {
  final line = TextPainter(
    text: TextSpan(text: 'A', style: paragraph.text.style),
    textScaler: paragraph.textScaler,
    textDirection: TextDirection.ltr,
  )..layout();
  final count = (paragraph.size.height / line.height).round();
  line.dispose();
  return count;
}
