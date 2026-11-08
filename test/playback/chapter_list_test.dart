import 'package:bookfin/foundation/theme.dart';
import 'package:bookfin/playback/playback.dart' show PlaybackChapter;
import 'package:bookfin/playback/screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The chapter list takes values and a callback, and no Playback. So these
// tests build it with no Playback at all: a list that tried to reach one
// would not compile.

/// Two files: the first holds two chapters, and the second starts 20 minutes
/// into the edition. The last chapter does not know its edition time.
const _chapters = [
  PlaybackChapter('Departure', 'one', 0, 0),
  PlaybackChapter('The crossing', 'one', 600000, 600000),
  PlaybackChapter('Arrival', 'two', 0, 1200000),
  PlaybackChapter('Home', 'two', 300000),
];

Future<List<PlaybackChapter>> _show(
  WidgetTester tester, {
  int current = 0,
  int position = 0,
}) async {
  final chosen = <PlaybackChapter>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: bookfinTheme(Brightness.light),
      home: Scaffold(
        body: ChapterList(
          chapters: _chapters,
          current: current,
          position: position,
          onChapter: chosen.add,
        ),
      ),
    ),
  );
  return chosen;
}

void main() {
  testWidgets('a tapped chapter reports itself', (tester) async {
    final chosen = await _show(tester);
    await tester.tap(find.text('Arrival'));
    expect(chosen, [_chapters[2]]);
  });

  testWidgets('only the current chapter shows how far through it the place '
      'is', (tester) async {
    await _show(tester, current: 0, position: 300000);
    final lines = tester.widgetList<ProgressLine>(find.byType(ProgressLine));
    expect([for (final line in lines) line.value], [0.5]);
  });

  testWidgets('each chapter shows where it starts in the whole edition, or in '
      'its file when the edition time is unknown', (tester) async {
    await _show(tester);
    Finder row(String chapter, String start) => find.ancestor(
      of: find.text(start),
      matching: find.ancestor(
        of: find.text(chapter),
        matching: find.byType(InkWell),
      ),
    );
    expect(row('Arrival', '20:00'), findsOneWidget);
    expect(row('Home', '05:00'), findsOneWidget);
  });

  testWidgets('the chapter sheet reports the tapped chapter, then closes', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: bookfinTheme(Brightness.light),
        home: const Scaffold(body: SizedBox.expand()),
      ),
    );
    final chosen = <PlaybackChapter>[];
    final shown = showChapters(
      tester.element(find.byType(SizedBox).last),
      chapters: _chapters,
      current: 0,
      position: 0,
      onChapter: chosen.add,
    );
    await tester.pumpAndSettle();
    expect(find.byType(ChapterList), findsOneWidget);
    await tester.tap(find.text('Arrival'));
    await tester.pumpAndSettle();
    expect(chosen, [_chapters[2]]);
    expect(find.byType(ChapterList), findsNothing);
    await shown;
  });
}
