import 'package:bookfin/catalog/book_cover.dart';
import 'package:bookfin/foundation/theme.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:bookfin/playback/screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'playback_test.dart'
    show LocalFiles, TestEngine, MemoryResume, account, title, recording;

/// The widgets that rebuilt while [during] ran.
Future<List<Widget>> _rebuildsDuring(Future<void> Function() during) async {
  final rebuilt = <Widget>[];
  debugOnRebuildDirtyWidget = (element, _) => rebuilt.add(element.widget);
  try {
    await during();
  } finally {
    debugOnRebuildDirtyWidget = null;
  }
  return rebuilt;
}

bool _isText(Widget widget, bool Function(String text) test) =>
    widget is Text && widget.data != null && test(widget.data!);

void main() {
  late LocalFiles downloads;
  late TestEngine engine;
  late Playback playback;
  setUp(() async {
    downloads = LocalFiles();
    engine = TestEngine();
    playback = Playback(
      downloads: downloads,
      engine: engine,
      store: MemoryResume(),
    );
    await playback.bind(account(), [title]);
    await playback.open(title, recording, autoplay: false);
  });
  tearDown(() async {
    await playback.close();
    downloads.dispose();
  });

  /// One decoder report 200 ms on while audio plays, as arrives several times
  /// a second.
  Future<void> playingTick(WidgetTester tester) async {
    engine.emit(engine.index, engine.milliseconds + 200, playing: true);
    await tester.pump();
  }

  Future<void> showPlayer(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: bookfinTheme(Brightness.light),
        home: Scaffold(body: PlayerView(playback: playback)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a playing tick redraws the slider and the time texts, '
      'not the stage, the cover or the tools row', (tester) async {
    await showPlayer(tester);
    // The first report starts playing, which changes the play button.
    await playingTick(tester);
    final rebuilt = await _rebuildsDuring(() => playingTick(tester));
    expect(rebuilt.whereType<Slider>(), isNotEmpty);
    expect(
      rebuilt.where(
        (widget) => _isText(widget, (text) => text.endsWith('left')),
      ),
      isNotEmpty,
    );
    expect(rebuilt.whereType<StageCover>(), isEmpty);
    expect(
      rebuilt.where((widget) => _isText(widget, (text) => text == title.title)),
      isEmpty,
      reason: 'the stage title',
    );
    expect(
      rebuilt.where((widget) => _isText(widget, (text) => text == 'Chapters')),
      isEmpty,
      reason: 'the tools row',
    );
  });

  testWidgets('a playing tick redraws only the mini player\'s progress line', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: bookfinTheme(Brightness.light),
        home: Scaffold(
          bottomNavigationBar: PlaybackMiniPlayer(playback: playback),
        ),
      ),
    );
    await playingTick(tester);
    final rebuilt = await _rebuildsDuring(() => playingTick(tester));
    expect(rebuilt.whereType<ProgressLine>(), isNotEmpty);
    expect(rebuilt.whereType<BookCover>(), isEmpty);
    expect(
      rebuilt.where((widget) => _isText(widget, (text) => text == title.title)),
      isEmpty,
    );
  });

  testWidgets('a new bookmark redraws no mini player progress line', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: bookfinTheme(Brightness.light),
        home: Scaffold(
          bottomNavigationBar: PlaybackMiniPlayer(playback: playback),
        ),
      ),
    );
    final records = playback.recordsNotifier;
    var recorded = 0;
    void heard() => recorded++;
    records.addListener(heard);
    addTearDown(() => records.removeListener(heard));
    final rebuilt = await _rebuildsDuring(() async {
      await tester.runAsync(playback.addBookmark);
      await tester.pump();
    });
    expect(recorded, isPositive, reason: 'the bookmark was recorded');
    expect(rebuilt.whereType<ProgressLine>(), isEmpty);
  });

  testWidgets('the Sleep label counts down while nothing else changes', (
    tester,
  ) async {
    await showPlayer(tester);
    // The timer runs on real time: 63 seconds read as 2 minutes, and 59 as 1.
    await tester.runAsync(
      () => playback.setSleep(const Duration(minutes: 1, seconds: 3)),
    );
    await tester.pump();
    expect(find.text('2 m'), findsOneWidget);

    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 4)),
    );
    await tester.pump();
    expect(find.text('1 m'), findsOneWidget);

    await tester.runAsync(() => playback.setSleep(null));
    await tester.pump();
    expect(find.text('1 m'), findsNothing);
  });

  testWidgets('the Bookmark tool names the bookmark only while the place is '
      'near it', (tester) async {
    await showPlayer(tester);
    await tester.runAsync(() async {
      await playback.addBookmark();
      await playback.flush();
    });
    await tester.pump();
    expect(find.text('Bookmarked'), findsOneWidget);

    engine.emit(engine.index, engine.milliseconds + 20000, playing: true);
    await tester.pump();
    expect(find.text('Bookmarked'), findsNothing);
    expect(find.text('Bookmark'), findsOneWidget);
  });
}
