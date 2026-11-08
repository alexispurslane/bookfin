import 'package:bookfin/foundation/theme.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:bookfin/playback/screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'playback_test.dart'
    show LocalFiles, MemoryResume, TestEngine, account, recording, title;

/// A decoder that takes time to sound: Play only records the command, and a
/// test reports the first sound itself.
class _SlowEngine extends TestEngine {
  @override
  Future<void> play() async {
    playCount++;
  }
}

void main() {
  late LocalFiles downloads;
  late _SlowEngine engine;
  late Playback playback;

  // Playback's queue begins in the real zone, so each test step that waits
  // for it runs in runAsync. The slow engine sounds only when a test says so.
  setUp(() async {
    downloads = LocalFiles();
    engine = _SlowEngine();
    playback = Playback(
      downloads: downloads,
      engine: engine,
      store: MemoryResume(),
    );
    await playback.bind(account(), [title]);
  });

  tearDown(() async {
    await playback.close();
    downloads.dispose();
  });

  Future<void> show(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      theme: bookfinTheme(Brightness.light),
      home: Scaffold(
        body: Center(child: PlaybackCoverButton(playback: playback)),
      ),
    ),
  );

  Finder button(String action) => find.bySemanticsLabel('$action audiobook');

  testWidgets('a tap on the round cover button plays the open audiobook, and '
      'a second tap pauses it', (tester) async {
    await tester.runAsync(
      () => playback.open(title, recording, autoplay: false),
    );
    await show(tester);
    expect(button('Play'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(button('Play'));
      await playback.flush();
    });
    engine.emit(0, 0, playing: true);
    await tester.pump();
    expect(playback.playing, isTrue);
    expect(button('Pause'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(button('Pause'));
      await playback.flush();
    });
    await tester.pump();
    expect(playback.playing, isFalse);
    expect(button('Play'), findsOneWidget);
  });

  testWidgets('a long press on the round cover button opens the player', (
    tester,
  ) async {
    await tester.runAsync(
      () => playback.open(title, recording, autoplay: false),
    );
    await show(tester);
    await tester.longPress(button('Play'));
    await tester.pumpAndSettle();
    expect(find.byType(PlayerView), findsOneWidget);
    expect(playback.playing, isFalse, reason: 'A long press does not play.');
  });

  testWidgets('the round cover button shows the starting ring at the tap and '
      'offers Pause until the audio sounds', (tester) async {
    await tester.runAsync(
      () => playback.open(title, recording, autoplay: false),
    );
    await show(tester);
    // The starting ring is the one inside the play state.
    Finder startingRing() => find.descendant(
      of: find.byType(PlayStateIcon),
      matching: find.byType(CircularProgressIndicator),
    );
    expect(startingRing(), findsNothing);
    await tester.runAsync(() => tester.tap(button('Play')));
    await tester.pump();
    expect(startingRing(), findsOneWidget);
    expect(button('Pause'), findsOneWidget);
    await tester.runAsync(playback.flush);
    engine.emit(0, 0, playing: true);
    await tester.pump();
    expect(startingRing(), findsNothing);
    expect(button('Pause'), findsOneWidget);
  });

  testWidgets('the round cover button fills its faded cover in full colour, '
      'like a pie, as far through the audiobook as the open place is', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await playback.open(title, recording, autoplay: false);
      await playback.seekEdition(75000);
    });
    await show(tester);
    final total = playback.durationMilliseconds!;
    final pie = tester.widget<ClipPath>(
      find.descendant(
        of: find.byType(PlaybackCoverButton),
        matching: find.byWidgetPredicate(
          (widget) => widget is ClipPath && widget.clipper is ProgressPie,
        ),
      ),
    );
    expect((pie.clipper! as ProgressPie).value, closeTo(75000 / total, 1e-9));
    expect(
      find.descendant(
        of: find.byType(PlaybackCoverButton),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsNothing,
      reason: 'No ring around the cover takes room from it.',
    );
  });

  test('the progress pie grows clockwise from twelve o\'clock', () {
    const size = Size.square(48);
    Path pie(double value) => ProgressPie(value).getClip(size);
    const upperRight = Offset(36, 12);
    const lowerRight = Offset(36, 36);
    const lowerLeft = Offset(12, 36);
    const upperLeft = Offset(12, 12);

    final quarter = pie(.25);
    expect(quarter.contains(upperRight), isTrue);
    expect(quarter.contains(lowerRight), isFalse);
    expect(quarter.contains(upperLeft), isFalse);

    final most = pie(.8);
    expect(most.contains(lowerLeft), isTrue);
    expect(most.contains(upperLeft), isFalse);

    expect(pie(0).contains(upperRight), isFalse);
    for (final point in [upperRight, lowerRight, lowerLeft, upperLeft]) {
      expect(pie(1).contains(point), isTrue);
    }
  });

  testWidgets('with no audiobook open there is no round cover button', (
    tester,
  ) async {
    await show(tester);
    expect(button('Play'), findsNothing);
    expect(
      tester.getSize(find.byType(PlaybackCoverButton)),
      Size.zero,
      reason: 'The button takes no room in the row.',
    );
  });
}
