import 'dart:convert';

import 'package:bookfin/catalog/glass.dart';
import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/foundation/theme.dart';
import 'package:bookfin/foundation/time.dart';
import 'package:bookfin/playback/records.dart';
import 'package:bookfin/playback/timeline.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// The rows of the History timeline fit the narrowest common Android phone
// with large text: 360 points wide, with the system text size at 130%. The
// tests draw the timeline in its glass sheet and in the app's own Outfit
// font, so that widths match the phone.

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
    chapter: 'Chapter 7',
    quote: null,
    along: AlongAudio(milliseconds),
  ),
  TextPosition() => (
    short: 'p. ${jsonDecode(place.anchor)['page']}',
    chapter: 'Chapter 7',
    quote: null,
    along: AlongText(page: jsonDecode(place.anchor)['page'] as int),
  ),
};

var _ids = 0;

/// A move of [kind] from [before] to [after] at [at], local time.
ActionEntry move(
  HistoryAction kind,
  Place before,
  Place after, {
  DateTime? at,
  Place? counterpartOf,
}) => ActionEntry(
  HistoryEvent<Place>(
    id: 'move ${_ids++}',
    at: (at ?? DateTime.now()).toUtc(),
    kind: kind,
    before: before,
    after: after,
    bookTitle: 'The Time Machine',
    editionLabel: 'Unabridged',
    counterpartOf: counterpartOf,
    matchedBy: counterpartOf == null ? null : MatchedBy.chapters,
  ),
);

void main() {
  setUpAll(() async {
    final outfit = FontLoader('Outfit')
      ..addFont(rootBundle.load('assets/fonts/Outfit.ttf'));
    await outfit.load();
  });

  /// Shows [entries] in the History's glass sheet, on a phone that is 360
  /// points wide, with the system text size at 130%.
  Future<void> show(WidgetTester tester, List<TimelineEntry> entries) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        theme: bookfinTheme(Brightness.light),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showGlassSheet<void>(
                context,
                title: 'History',
                isScrollControlled: true,
                builder: (_) => DraggableScrollableSheet(
                  expand: false,
                  initialChildSize: 0.7,
                  maxChildSize: 0.95,
                  builder: (_, scroll) => HistoryTimeline(
                    entries: ValueNotifier(entries),
                    describe: describe,
                    scroll: scroll,
                    onGoBefore: (_) {},
                    onGoTo: (_) {},
                    onRename: (_) {},
                    onDelete: (_) {},
                  ),
                ),
              ),
              child: const Text('Open History'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open History'));
    await tester.pumpAndSettle();
  }

  /// The paragraph of the row text [text].
  RenderParagraph paragraph(WidgetTester tester, String text) =>
      tester.renderObject<RenderParagraph>(find.text(text, findRichText: true));

  /// Where the glyphs of the text [text] start and end, across the screen.
  ({double left, double right}) glyphs(WidgetTester tester, String text) {
    final shown = paragraph(tester, text);
    final boxes = shown.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: text.length),
    );
    double across(double x) => shown.localToGlobal(Offset(x, 0)).dx;
    return (
      left: across(
        boxes.map((box) => box.left).reduce((a, b) => a < b ? a : b),
      ),
      right: across(
        boxes.map((box) => box.right).reduce((a, b) => a > b ? a : b),
      ),
    );
  }

  testWidgets('the longest usual listening and reading move labels show in '
      'full beside both lanes', (tester) async {
    await show(tester, [
      // A drag of the slider, in an audiobook over an hour long.
      move(HistoryAction.seek, listening(3735000), listening(4495000)),
      // A drag of the scrub bar in a long novel.
      move(HistoryAction.seek, reading(134), reading(254)),
      move(HistoryAction.chapter, reading(254), reading(268)),
      move(HistoryAction.historyRestore, reading(268), reading(134)),
      move(
        HistoryAction.historyRestore,
        reading(134),
        reading(254),
        counterpartOf: listening(4495000),
      ),
    ]);

    for (final label in [
      'Ahead 12 m 40 s',
      'Ahead 120 pages',
      'Changed chapter',
      'From History',
      'From audiobook',
    ]) {
      expect(
        paragraph(tester, label).didExceedMaxLines,
        isFalse,
        reason: '"$label" ends in "…"',
      );
    }
  });

  testWidgets('a row says a short label and reads its full words to a '
      'screen reader', (tester) async {
    final semantics = tester.ensureSemantics();
    await show(tester, [
      move(HistoryAction.jump, listening(3735000), listening(3765000)),
    ]);

    expect(find.text('Ahead 30 s', findRichText: true), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Jumped ahead 30 s')), findsOneWidget);
    semantics.dispose();
  });

  for (final (clock, latest) in [
    ('12-hour', '10:58 PM'),
    ('24-hour', '22:58'),
  ]) {
    testWidgets('on a $clock clock, an open row keeps its place text as far '
        'from its end as the widest time of day starts from its start, and '
        'its place lines up with the closed rows', (tester) async {
      tester.platformDispatcher.alwaysUse24HourFormatTestValue =
          clock == '24-hour';
      addTearDown(tester.platformDispatcher.clearAlwaysUse24HourTestValue);
      final today = DateTime.now();
      await show(tester, [
        move(
          HistoryAction.seek,
          listening(3735000),
          listening(4495000),
          at: DateTime(today.year, today.month, today.day, 22, 58),
        ),
        move(
          HistoryAction.seek,
          listening(4495000),
          listening(4525000),
          at: DateTime(today.year, today.month, today.day, 9, 5),
        ),
      ]);
      await tester.tap(find.text('Ahead 12 m 40 s', findRichText: true));
      await tester.pumpAndSettle();

      final highlight = tester.getRect(
        find
            .ancestor(
              of: find.text('Ahead 12 m 40 s', findRichText: true),
              matching: find.byType(InkWell),
            )
            .first,
      );
      final time = glyphs(tester, latest);
      final open = glyphs(tester, '→ 1:14:55');
      final closed = glyphs(tester, '→ 1:15:25');

      expect(open.right, lessThan(highlight.right));
      expect(
        highlight.right - open.right,
        moreOrLessEquals(time.left - highlight.left, epsilon: 0.5),
      );
      expect(closed.right, moreOrLessEquals(open.right, epsilon: 0.5));
    });
  }
}
