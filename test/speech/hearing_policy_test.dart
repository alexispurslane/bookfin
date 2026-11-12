// The hearing policy decides when a heard window is heard
// (docs/plans/cross-edition-places.md, "When a window is heard"): after
// each 5 minutes of listening, at each new move, pause or bookmark of this
// phone, and in a fill of older places, newest first, only while the phone
// charges with battery saver off. It hears only audiobooks whose book also
// has an ebook, because a heard window serves only a landing in an ebook.
import 'package:bookfin/catalog/model.dart';
import 'package:flutter/foundation.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:bookfin/speech/hearing_policy.dart';
import 'package:bookfin/speech/heard_windows.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback/playback_test.dart'
    show LocalFiles, MemoryResume, TestEngine, account;
import 'heard_windows_test.dart' show FakeHearing, MemoryStore, inline;

/// One file of an hour.
const hour = SourceFile(
  itemId: 'hour',
  displayName: 'Hour',
  mediaSourceId: 'm',
  revision: 'r1',
  durationMs: 3600000,
  container: 'mp3',
  sizeBytes: 42,
);
const long = Edition(
  id: 'long',
  kind: EditionKind.audio,
  label: 'Narrator',
  files: [hour],
  memberIds: ['hour:m'],
);
const ebook = Edition(
  id: 'ebook',
  kind: EditionKind.text,
  label: 'EPUB',
  files: [
    SourceFile(
      itemId: 'text',
      displayName: 'Long',
      mediaSourceId: 't',
      revision: 'r1',
      durationMs: null,
      container: 'epub',
      sizeBytes: 42,
    ),
  ],
  memberIds: ['text:t'],
);
const book = Book(id: 'b', title: 'Long', author: 'A', editions: [long, ebook]);

/// The same recording in a book that has no ebook.
const alone = Book(id: 'b', title: 'Long', author: 'A', editions: [long]);

void main() {
  late LocalFiles downloads;
  late TestEngine engine;
  late MemoryResume store;
  late Playback playback;
  late FakeHearing hearing;
  late HeardWindows heard;
  late ValueNotifier<bool> mayFill;
  late HearingPolicy policy;

  /// The window starts that were heard, in order.
  List<int> starts() => [for (final call in hearing.calls) call.$2];

  /// Plays from [from] to [to] seconds, one decoder report a second.
  void listen(int from, int to) {
    for (var second = from; second <= to; second++) {
      engine.emit(0, second * 1000, playing: true);
    }
  }

  setUp(() async {
    downloads = LocalFiles()..files[hour.key] = Uri.file('/hour.mp3');
    engine = TestEngine();
    store = MemoryResume();
    playback = Playback(downloads: downloads, engine: engine, store: store);
    await playback.bind(account(), [book]);
    hearing = FakeHearing();
    heard = HeardWindows(
      hear: hearing.call,
      store: MemoryStore(),
      localPath: (file) async => (await downloads.localFile(file))?.path,
      hop: inline,
    );
    mayFill = ValueNotifier(false);
    policy = HearingPolicy(playback: playback, heard: heard, mayFill: mayFill);
  });
  tearDown(() async {
    policy.dispose();
    await playback.close();
    downloads.dispose();
  });

  Future<void> settle() async {
    for (var turn = 0; turn < 20; turn++) {
      await pumpEventQueue();
    }
  }

  test('five minutes of listening make a window of the last 8 s', () async {
    await playback.open(book, long, autoplay: false);
    await playback.play();
    // Play makes a record too, which has a window of its own.
    policy.start();
    listen(0, 299);
    await settle();
    expect(starts(), isEmpty);
    listen(300, 300);
    await settle();
    expect(starts(), [292000]);
    listen(301, 599);
    await settle();
    expect(starts(), [292000]);
    listen(600, 600);
    await settle();
    expect(starts(), [292000, 592000]);
  });

  test('a skip through the book is no listening', () async {
    await playback.open(book, long, autoplay: false);
    await playback.play();
    // Play makes a record too, which has a window of its own.
    policy.start();
    for (var second = 0; second < 3000; second += 60) {
      engine.emit(0, second * 1000, playing: true);
    }
    await settle();
    expect(starts(), isEmpty);
  });

  test('a pause makes a window at its place', () async {
    await playback.open(book, long, autoplay: false);
    await playback.play();
    // Play makes a record too, which has a window of its own.
    policy.start();
    listen(0, 42);
    await playback.pause();
    await settle();
    expect(starts(), [38000]);
  });

  test('a jump makes a window at each of its ends', () async {
    policy.start();
    await playback.open(book, long, autoplay: false);
    listen(0, 42);
    engine.emit(0, 42000);
    await playback.jump(forward: true);
    await settle();
    expect(starts(), containsAll([38000, 68000]));
  });

  test('a new bookmark makes a window at its place', () async {
    policy.start();
    await playback.open(book, long, autoplay: false);
    engine.emit(0, 120000);
    await playback.addBookmark();
    await settle();
    expect(starts(), [116000]);
  });

  test('nothing is heard before the policy starts', () async {
    await playback.open(book, long, autoplay: false);
    engine.emit(0, 120000);
    await playback.addBookmark();
    await settle();
    expect(starts(), isEmpty);
  });

  group('the fill of older places', () {
    setUp(() async {
      await playback.open(book, long, autoplay: false);
      for (final second in [100, 200, 300]) {
        engine.emit(0, second * 1000);
        await playback.addBookmark();
      }
    });

    test('waits while the phone does not allow it', () async {
      policy.start();
      await settle();
      expect(starts(), isEmpty);
    });

    test('starts when the phone starts allowing it', () async {
      policy.start();
      await settle();
      mayFill.value = true;
      await settle();
      expect(starts(), [296000, 196000, 96000]);
    });

    test('hears the older places newest first when allowed', () async {
      mayFill.value = true;
      policy.start();
      await settle();
      expect(starts(), [296000, 196000, 96000]);
    });

    test('stops when the phone stops allowing it', () async {
      mayFill.value = true;
      hearing.gated = true;
      policy.start();
      await settle();
      mayFill.value = false;
      hearing.gates.first.complete();
      await settle();
      expect(starts(), [296000]);
    });

    test('a place that heard nothing is not tried again', () async {
      mayFill.value = true;
      hearing.answer = (_, _) => null;
      policy.start();
      await settle();
      policy.recheck();
      await settle();
      expect(starts(), [296000, 196000, 96000]);
    });
  });

  group('an audiobook whose book has no ebook', () {
    setUp(() async {
      await playback.bind(account(), [alone]);
      await playback.open(alone, long, autoplay: false);
    });

    test('is not heard after five minutes of listening', () async {
      await playback.play();
      policy.start();
      listen(0, 600);
      await settle();
      expect(starts(), isEmpty);
    });

    test('is not heard at a new bookmark', () async {
      policy.start();
      engine.emit(0, 200000);
      await playback.addBookmark();
      await settle();
      expect(starts(), isEmpty);
    });

    test('is not heard by the fill', () async {
      engine.emit(0, 100000);
      await playback.addBookmark();
      mayFill.value = true;
      policy.start();
      await settle();
      expect(starts(), isEmpty);
    });
  });
}
