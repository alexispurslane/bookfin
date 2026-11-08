import 'dart:async';

import 'package:bookfin/playback/playback.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'playback_test.dart'
    show LocalFiles, TestEngine, MemoryResume, account, title, recording;
import 'timeline_test.dart' show other, otherFile, otherRecording;

/// A store that cannot save, as on a full disk.
class FullStore extends MemoryResume {
  @override
  Future<void> save(String accountKey, ListeningChanges changes) async =>
      throw Exception('no space');
}

/// Counts how many times each narrow signal of [playback] notifies from now
/// on, by signal name.
Map<String, int> heard(Playback playback) {
  final signals = <String, Listenable>{
    'position': playback.positionNotifier,
    'selection': playback.selectionNotifier,
    'sleep': playback.sleepNotifier,
    'records': playback.recordsNotifier,
    'library': playback.libraryNotifier,
    'settings': playback.settingsNotifier,
    'status': playback.statusNotifier,
    'undo': playback.undoNotifier,
  };
  final counts = {for (final name in signals.keys) name: 0};
  for (final MapEntry(key: name, value: signal) in signals.entries) {
    signal.addListener(() => counts[name] = counts[name]! + 1);
  }
  return counts;
}

void main() {
  late LocalFiles downloads;
  late TestEngine engine;
  late MemoryResume store;
  late Playback playback;
  setUp(() async {
    downloads = LocalFiles()..files[otherFile.key] = Uri.file('/three.wav');
    engine = TestEngine();
    store = MemoryResume();
    playback = Playback(downloads: downloads, engine: engine, store: store);
    await playback.bind(account(), [title, other]);
    await playback.open(title, recording, autoplay: false);
  });
  tearDown(() async {
    await playback.close();
    downloads.dispose();
  });

  /// One decoder sample 200 ms later while audio plays, as arrives five
  /// times a second.
  void tick() =>
      engine.emit(engine.index, engine.milliseconds + 200, playing: true);

  group('a playing tick', () {
    test('moves the position and leaves every other signal quiet', () async {
      await playback.play();
      await playback.setSleep(const Duration(minutes: 30));
      final counts = heard(playback);
      var broad = 0;
      playback.addListener(() => broad++);
      // Ten ticks cross two whole seconds, so the resume is saved twice.
      for (var step = 0; step < 10; step++) {
        tick();
      }
      await playback.flush();
      expect(broad, 0);
      expect(counts, {
        'position': 10,
        'selection': 0,
        'sleep': 0,
        'records': 0,
        'library': 0,
        'settings': 0,
        'status': 0,
        'undo': 0,
      });
      expect(playback.positionNotifier.value?.milliseconds, 2000);
      playback.checkInvariants();
    });

    // The media session needs this tick to correct its projected position.
    test('that repeats the same place still notifies the position', () async {
      await playback.play();
      final counts = heard(playback);
      engine.emit(engine.index, engine.milliseconds, playing: true);
      expect(counts, {
        'position': 1,
        'selection': 0,
        'sleep': 0,
        'records': 0,
        'library': 0,
        'settings': 0,
        'status': 0,
        'undo': 0,
      });
    });
  });

  group('the selection', () {
    test('shows the open book and edition, paused', () {
      expect(playback.selectionNotifier.value, (
        book: title,
        edition: recording,
        playing: false,
        active: false,
      ));
    });

    test('changes at once when the book plays and when it pauses', () async {
      final counts = heard(playback);
      await playback.play();
      expect(playback.selectionNotifier.value.playing, isTrue);
      expect(playback.selectionNotifier.value.active, isTrue);
      expect(counts['selection'], greaterThan(0));
      final played = counts['selection']!;
      await playback.pause();
      expect(playback.selectionNotifier.value.playing, isFalse);
      expect(counts['selection'], greaterThan(played));
    });

    test('changes with the position when another book opens', () async {
      final counts = heard(playback);
      await playback.open(other, otherRecording, autoplay: false);
      expect(playback.selectionNotifier.value.book, other);
      expect(playback.selectionNotifier.value.edition, otherRecording);
      expect(playback.positionNotifier.value?.editionId, otherRecording.id);
      expect(counts['selection'], 1);
      expect(counts['position'], greaterThan(0));
    });

    test('empties when the account signs out', () async {
      await playback.bind(null, []);
      expect(playback.selectionNotifier.value, (
        book: null,
        edition: null,
        playing: false,
        active: false,
      ));
      expect(playback.positionNotifier.value, isNull);
    });
  });

  test('a seek moves the position and keeps the selection', () async {
    final counts = heard(playback);
    await playback.seekEdition(75000);
    expect(playback.editionTime(playback.positionNotifier.value!), 75000);
    expect(counts['position'], greaterThan(0));
    expect(counts['selection'], 0);
  });

  group('the records', () {
    test(
      'change when a bookmark is added, and the position does not',
      () async {
        final counts = heard(playback);
        await playback.addBookmark(title: 'Here');
        expect(counts['records'], 1);
        expect(counts['position'], 0);
      },
    );

    test('change when a listening action is recorded', () async {
      await playback.play();
      final counts = heard(playback);
      await playback.pause();
      expect(playback.history.first.kind, ListeningAction.pause);
      expect(counts['records'], 1);
    });

    test('change when another account loads its own records', () async {
      final counts = heard(playback);
      await playback.bind(account(user: 'bob'), [title, other]);
      expect(counts['records'], greaterThan(0));
    });
  });

  group('the library', () {
    test('changes when the same account binds a refreshed library, and the '
        'records do not', () async {
      final counts = heard(playback);
      await playback.bind(account(), [title, other]);
      expect(counts['library'], 1);
      expect(counts['records'], 0);
    });

    test('changes when another account binds its library', () async {
      final counts = heard(playback);
      await playback.bind(account(user: 'bob'), [title, other]);
      expect(counts['library'], greaterThan(0));
    });
  });

  group('the undo offer', () {
    test('comes with a seek once the place before it is saved', () async {
      final counts = heard(playback);
      await playback.seekEdition(75000);
      final offer = playback.undoNotifier.value;
      expect(offer?.action.kind, ListeningAction.seek);
      expect(offer?.saved, isTrue);
      expect(counts['undo'], 1);
    });

    test('goes when it is dismissed', () async {
      await playback.seekEdition(75000);
      final counts = heard(playback);
      playback.dismissUndo();
      expect(playback.undoNotifier.value, isNull);
      expect(counts['undo'], 1);
    });

    test('stays saved while playing ticks save the place', () async {
      await playback.play();
      await playback.seekEdition(75000);
      await playback.flush();
      final counts = heard(playback);
      for (var step = 0; step < 10; step++) {
        tick();
      }
      await playback.flush();
      expect(playback.undoNotifier.value?.saved, isTrue);
      expect(counts['undo'], 0);
      playback.checkInvariants();
    });
  });

  group('the settings', () {
    test('change with the speed, and the position does not', () async {
      final counts = heard(playback);
      await playback.setSpeed(1.5);
      expect(playback.settingsNotifier.value, (
        speed: 1.5,
        backward: 10,
        forward: 30,
      ));
      expect(counts['settings'], 1);
      expect(counts['position'], 0);
    });

    test('change with the jump lengths', () async {
      await playback.setJumps(15, 45);
      expect(playback.settingsNotifier.value, (
        speed: 1.0,
        backward: 15,
        forward: 45,
      ));
    });
  });

  test('the status shows a records save that failed', () async {
    final full = Playback(
      downloads: downloads,
      engine: TestEngine(),
      store: FullStore(),
    );
    addTearDown(full.close);
    await full.bind(account(), [title]);
    await full.open(title, recording, autoplay: false);
    await full.addBookmark();
    expect(full.statusNotifier.value, (
      message:
          'Personal records could not be saved. Free storage and try again.',
      saveFailed: true,
    ));
  });

  group('the sleep timer', () {
    /// Runs [work] to its end. Playback work starts in fake time, so its
    /// timers run on the test clock.
    Future<void> finish(WidgetTester tester, Future<void> work) async {
      var done = false;
      unawaited(work.whenComplete(() => done = true));
      for (var step = 0; !done && step < 100; step++) {
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump(Duration.zero);
      }
      expect(done, isTrue);
    }

    Future<Playback> listen(WidgetTester tester) async {
      final listening = Playback(
        downloads: downloads,
        engine: TestEngine(),
        store: MemoryResume(),
      );
      await finish(tester, listening.bind(account(), [title]));
      await finish(tester, listening.open(title, recording));
      return listening;
    }

    testWidgets('counts down the time left once a second', (tester) async {
      final listening = await listen(tester);
      final counts = heard(listening);
      await finish(tester, listening.setSleep(const Duration(minutes: 15)));
      expect(listening.sleepNotifier.value, const Duration(minutes: 15));
      await tester.pump(const Duration(seconds: 1));
      expect(
        listening.sleepNotifier.value,
        const Duration(minutes: 14, seconds: 59),
      );
      await tester.pump(const Duration(minutes: 1));
      expect(
        listening.sleepNotifier.value,
        const Duration(minutes: 13, seconds: 59),
      );
      expect(counts['sleep'], 62);
      expect(counts['position'], 0);
      listening.checkInvariants();
      await finish(tester, listening.close());
    });

    testWidgets('clears when it pauses the book', (tester) async {
      final listening = await listen(tester);
      await finish(tester, listening.setSleep(const Duration(seconds: 3)));
      await tester.pump(const Duration(seconds: 3));
      await finish(tester, listening.flush());
      expect(listening.sleepNotifier.value, isNull);
      expect(listening.selectionNotifier.value.playing, isFalse);
      listening.checkInvariants();
      await finish(tester, listening.close());
    });

    test('clears when it is turned off', () async {
      await playback.setSleep(const Duration(minutes: 15));
      await playback.setSleep(null);
      expect(playback.sleepNotifier.value, isNull);
    });
  });
}
