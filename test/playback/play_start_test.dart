import 'dart:async';

import 'package:bookfin/catalog/book_page.dart';
import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/downloads/downloads.dart';
import 'package:bookfin/foundation/theme.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:bookfin/playback/screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'playback_test.dart'
    show
        LocalFiles,
        MemoryResume,
        TestEngine,
        account,
        recording,
        second,
        title;
import 'observe_playback.dart';

/// A decoder that takes time to sound: Play only records the command, and a
/// test reports the first sound itself.
class _SlowEngine extends TestEngine {
  @override
  Future<void> play() async {
    playCount++;
  }
}

/// Saved files that count the lookups that are under way.
class _CountingFiles extends LocalFiles {
  int pending = 0;
  int mostPending = 0;
  @override
  Future<Uri?> localFile(SourceFile source) async {
    pending++;
    if (pending > mostPending) mostPending = pending;
    try {
      return await super.localFile(source);
    } finally {
      pending--;
    }
  }
}

void main() {
  late _CountingFiles downloads;
  late _SlowEngine engine;
  late Playback playback;
  setUp(() async {
    downloads = _CountingFiles();
    engine = _SlowEngine();
    playback = Playback(
      downloads: downloads,
      engine: engine,
      store: MemoryResume(),
    );
    await playback.bind(account(), [title]);
  });
  tearDown(() async {
    if (downloads.lookupGate case final gate? when !gate.isCompleted) {
      gate.complete();
    }
    await playback.close();
    downloads.dispose();
  });

  group('Playback says which edition is starting', () {
    test('Listen shows its edition as starting before any file is found', () {
      downloads.lookupGate = Completer<void>();
      unawaited(playback.open(title, recording));
      expect(playback.startingNotifier.value?.id, recording.id);
      downloads.lookupGate!.complete();
    });

    test('a started edition stops starting when its audio sounds', () async {
      await playback.open(title, recording);
      expect(playback.starting?.id, recording.id);
      engine.emit(0, 0, playing: true);
      expect(playback.playing, isTrue);
      expect(playback.starting, isNull);
    });

    test('Play shows the open edition as starting until it sounds', () async {
      await playback.open(title, recording, autoplay: false);
      expect(playback.starting, isNull);
      final playing = playback.play();
      expect(playback.starting?.id, recording.id);
      await playing;
      expect(playback.starting?.id, recording.id);
      engine.emit(0, 0, playing: true);
      expect(playback.starting, isNull);
    });

    test('Play while audio sounds starts nothing', () async {
      await playback.open(title, recording);
      engine.emit(0, 0, playing: true);
      await playback.play();
      expect(playback.starting, isNull);
    });

    test('a start that cannot play stops starting', () async {
      downloads.files.remove(second.key);
      await playback.open(title, recording);
      expect(playback.statusNotifier.value.actionNotice?.message, isNotNull);
      expect(playback.starting, isNull);
    });

    test('Pause during a start stops starting at once', () async {
      downloads.lookupGate = Completer<void>();
      final opening = playback.open(title, recording);
      final pausing = playback.pause();
      expect(playback.starting, isNull);
      downloads.lookupGate!.complete();
      await Future.wait([opening, pausing]);
      expect(playback.starting, isNull);
      expect(playback.playing, isFalse);
    });

    test('a decoder failure stops starting', () async {
      await playback.open(title, recording);
      final stopped = waitForPlayback(
        playback,
        () => playback.starting == null,
      );
      engine.events.addError(Exception('decoder failed'));
      await stopped;
      expect(playback.starting, isNull);
    });

    test('another account stops the start of this one', () async {
      await playback.open(title, recording);
      await playback.bind(null, []);
      expect(playback.starting, isNull);
    });
  });

  group('a start looks up all files of the edition at once', () {
    test('Listen looks up every file together', () async {
      downloads.lookupGate = Completer<void>();
      final opening = playback.open(title, recording);
      await pumpEventQueue();
      expect(downloads.pending, recording.files.length);
      downloads.lookupGate!.complete();
      await opening;
    });

    test('Play looks up every file together', () async {
      await playback.open(title, recording, autoplay: false);
      downloads.lookupGate = Completer<void>();
      final playing = playback.play();
      await pumpEventQueue();
      expect(downloads.pending, recording.files.length);
      downloads.lookupGate!.complete();
      await playing;
    });
  });

  group('every Play control shows the start at once', () {
    Future<void> show(WidgetTester tester, Widget child) => tester.pumpWidget(
      MaterialApp(
        theme: bookfinTheme(Brightness.light),
        home: Scaffold(body: Center(child: child)),
      ),
    );

    // Playback's queue began in the real zone, so its work runs there:
    // each step that waits for it runs in runAsync, and frames pump between
    // the steps. The slow engine keeps the start open until the test
    // reports the sound.
    testWidgets('the mini player Play turns into a progress ring at the tap '
        'and into Pause when the audio sounds', (tester) async {
      await tester.runAsync(
        () => playback.open(title, recording, autoplay: false),
      );
      await show(tester, PlaybackMiniPlayer(playback: playback));
      await tester.runAsync(() => tester.tap(find.byTooltip('Play')));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.runAsync(playback.flush);
      await tester.pump();
      expect(engine.playCount, 1);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      engine.emit(0, 0, playing: true);
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byTooltip('Pause'), findsOneWidget);
    });

    testWidgets('a tap on a starting Play button pauses', (tester) async {
      await tester.runAsync(
        () => playback.open(title, recording, autoplay: false),
      );
      await show(tester, PlaybackMiniPlayer(playback: playback));
      await tester.runAsync(() => tester.tap(find.byTooltip('Play')));
      await tester.pump();
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Pause'));
        await playback.flush();
      });
      await tester.pump();
      expect(playback.starting, isNull);
      expect(playback.playing, isFalse);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    for (final large in [false, true]) {
      testWidgets('the ${large ? 'stage' : 'mini player'} button shows a '
          'progress ring while starting and offers Pause', (tester) async {
        var taps = 0;
        await show(
          tester,
          PlayPauseButton(
            playing: false,
            starting: true,
            large: large,
            onPlayPause: () => taps++,
          ),
        );
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        await tester.tap(find.byTooltip('Pause'));
        expect(taps, 1);
      });
    }

    testWidgets('the book page Listen shows a progress ring only while its '
        'own edition starts', (tester) async {
      final starting = ValueNotifier<Edition?>(null);
      addTearDown(starting.dispose);
      await show(
        tester,
        BookActions(
          listening: recording,
          reading: null,
          downloads: null,
          starting: starting,
          onListen: (_) {},
          onRead: null,
          onDownload: (_, _) {},
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      starting.value = const Edition(
        id: 'other',
        kind: EditionKind.audio,
        label: 'Other',
        files: [second],
        memberIds: ['two:m2'],
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      starting.value = recording;
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('an edition panel Listen shows a progress ring while its '
        'edition starts', (tester) async {
      await show(
        tester,
        SingleChildScrollView(
          child: EditionPanel(
            edition: recording,
            downloads: null,
            starting: ValueNotifier<Edition?>(recording),
            onListen: () {},
            onOrderFiles: () {},
            onSeparate: (_) {},
            onDownload: (DownloadAction _) {},
          ),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}
