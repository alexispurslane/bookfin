import 'dart:async';

import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/foundation/theme.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:bookfin/playback/recent.dart';
import 'package:bookfin/playback/records_screen.dart';
import 'package:bookfin/playback/screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'playback_test.dart' show title, recording, second;

/// Each player control here is drawn alone, with no Playback behind it. It
/// can only report what the listener did.
void main() {
  Future<void> show(WidgetTester tester, Widget control) => tester.pumpWidget(
    MaterialApp(
      theme: bookfinTheme(Brightness.light),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(width: 400, child: control),
        ),
      ),
    ),
  );

  for (final large in [false, true]) {
    testWidgets('the ${large ? 'stage' : 'mini player'} play button offers '
        'Pause while audio plays and reports the tap', (tester) async {
      var taps = 0;
      await show(
        tester,
        PlayPauseButton(playing: true, large: large, onPlayPause: () => taps++),
      );
      expect(find.byTooltip('Play'), findsNothing);
      await tester.tap(find.byTooltip('Pause'));
      expect(taps, 1);
    });
  }

  testWidgets('a jump button reports which way it jumps', (tester) async {
    final jumps = <bool>[];
    await show(
      tester,
      Row(
        children: [
          JumpButton(forward: false, seconds: 10, onJump: jumps.add),
          JumpButton(
            forward: true,
            seconds: 30,
            compact: true,
            onJump: jumps.add,
          ),
        ],
      ),
    );
    await tester.tap(find.byTooltip('Back 10 seconds'));
    await tester.tap(find.byTooltip('Forward 30 seconds'));
    expect(jumps, [false, true]);
  });

  testWidgets('the position slider reports where a drag starts and ends, '
      'and shows the target until the seek lands', (tester) async {
    var starts = 0;
    final ends = <int>[];
    final landed = Completer<void>();
    await show(
      tester,
      PositionSlider(
        position: 0,
        total: 150000,
        chapters: const [],
        chapterIndex: null,
        bookmarks: const [],
        onSeekStart: () => starts++,
        onSeekEnd: (milliseconds) {
          ends.add(milliseconds);
          return landed.future;
        },
      ),
    );
    Slider slider() => tester.widget<Slider>(find.byType(Slider));
    slider().onChangeStart!(0);
    slider().onChanged!(95000);
    await tester.pump();
    expect(starts, 1);
    expect(ends, isEmpty);
    expect(slider().value, 95000);
    expect(find.text('01:35'), findsOneWidget);

    slider().onChangeEnd!(95000);
    await tester.pump();
    expect(ends, [95000]);
    expect(slider().value, 95000);

    landed.complete();
    await tester.pumpAndSettle();
    expect(slider().value, 0);
  });

  testWidgets('the Undo notice reports Undo and its dismissal', (tester) async {
    var undos = 0;
    var dismissals = 0;
    await show(
      tester,
      UndoNotice(
        unsaved: false,
        onUndo: () => undos++,
        onDismiss: () => dismissals++,
      ),
    );
    expect(find.text('Your previous place is saved'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.tap(find.byTooltip('Dismiss Undo'));
    expect((undos, dismissals), (1, 1));
  });

  testWidgets('the mini player reports a tap on its book as a request to '
      'open the player', (tester) async {
    var opened = 0;
    await show(
      tester,
      MiniPlayerCard(book: title, onOpen: () => opened++, controls: const []),
    );
    await tester.tap(find.text('The journey'));
    expect(opened, 1);
  });

  testWidgets('the mini player redraws only its progress line as the '
      'progress moves', (tester) async {
    final progress = ValueNotifier(0.25);
    addTearDown(progress.dispose);
    await show(
      tester,
      MiniPlayerCard(
        book: title,
        onOpen: () {},
        controls: const [],
        progress: progress,
      ),
    );
    final rebuilt = <Widget>[];
    debugOnRebuildDirtyWidget = (element, _) => rebuilt.add(element.widget);
    try {
      progress.value = 0.5;
      await tester.pump();
    } finally {
      debugOnRebuildDirtyWidget = null;
    }
    expect(tester.widget<ProgressLine>(find.byType(ProgressLine)).value, 0.5);
    expect(rebuilt.whereType<ProgressLine>(), isNotEmpty);
    expect(
      rebuilt.whereType<Text>().where((text) => text.data == 'The journey'),
      isEmpty,
    );
  });

  testWidgets('the replacement notice reports which replacement to start', (
    tester,
  ) async {
    final request = AudioReplacement(
      title,
      recording,
      AudioPosition(
        editionId: recording.id,
        sourceKey: second.key,
        revision: second.revision,
        milliseconds: 5000,
      ),
    );
    final started = <AudioReplacement>[];
    await show(
      tester,
      ReplacementOffer(request: request, onStartReplacement: started.add),
    );
    expect(find.text('The journey · Narrator'), findsOneWidget);
    await tester.tap(find.text('Start replacement'));
    expect(started, [request]);
  });

  testWidgets('the save notice shows the message and reports a retry', (
    tester,
  ) async {
    var retries = 0;
    await show(
      tester,
      RecordSaveNotice(
        status: (message: 'Saved records are late.', saveFailed: true),
        onRetrySave: () => retries++,
      ),
    );
    expect(find.text('Saved records are late.'), findsOneWidget);
    await tester.tap(find.text('Retry saving'));
    expect(retries, 1);
  });

  testWidgets('the save notice shows nothing while records save', (
    tester,
  ) async {
    await show(
      tester,
      RecordSaveNotice(
        status: (message: null, saveFailed: false),
        onRetrySave: () {},
      ),
    );
    expect(find.text('Retry saving'), findsNothing);
  });

  testWidgets('a recently listened row reports the book to resume', (
    tester,
  ) async {
    final now = DateTime(2026, 11, 7, 12);
    final entry = (book: title, edition: recording, at: now);
    final resumed = <RecentListening>[];
    await show(
      tester,
      RecentListeningRow(
        entry: entry,
        progress: (elapsedMs: 30000, totalMs: 150000),
        now: now,
        onResume: resumed.add,
      ),
    );
    expect(find.textContaining('2 m left'), findsOneWidget);
    await tester.tap(find.byTooltip('Resume The journey'));
    await tester.tap(find.text('The journey'));
    expect(resumed, [entry, entry]);
  });

  group('the bookmark editor', () {
    Future<Future<({String title, String note})?>> openEditor(
      WidgetTester tester,
    ) async {
      final edited = Completer<({String title, String note})?>();
      await show(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => edited.complete(
              showBookmarkEditor(
                context,
                heading: 'Edit bookmark',
                title: 'The letter',
                place: 'At 01:15',
              ),
            ),
            child: const Text('Edit'),
          ),
        ),
      );
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      return edited.future;
    }

    testWidgets('returns the edited title and note', (tester) async {
      final edited = await openEditor(tester);
      expect(find.text('Edit bookmark'), findsOneWidget);
      expect(find.text('At 01:15'), findsOneWidget);
      expect(find.text('The letter'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Title (optional)'),
        'The second letter',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Note (optional)'),
        'Read it again.',
      );
      await tester.tap(find.text('Save bookmark'));
      await tester.pumpAndSettle();
      expect(await edited, (
        title: 'The second letter',
        note: 'Read it again.',
      ));
      expect(find.text('Edit bookmark'), findsNothing);
    });

    testWidgets('returns nothing when cancelled', (tester) async {
      final edited = await openEditor(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await edited, isNull);
    });
  });
}
