import 'package:bookfin/playback/playback.dart';
import 'package:flutter_test/flutter_test.dart';

import 'playback_test.dart'
    show LocalFiles, TestEngine, MemoryResume, account, title, recording;
import 'timeline_test.dart' show other, otherFile, otherRecording;

void main() {
  late LocalFiles downloads;
  late TestEngine engine;
  late Playback playback;
  setUp(() async {
    downloads = LocalFiles()..files[otherFile.key] = Uri.file('/three.wav');
    engine = TestEngine();
    playback = Playback(
      downloads: downloads,
      engine: engine,
      store: MemoryResume(),
    );
    await playback.bind(account(), [title, other]);
    // Listen to the other book first, then bookmark this one 75 s in.
    await playback.open(other, otherRecording, autoplay: false);
    await playback.jump(forward: true);
    await playback.open(title, recording, autoplay: false);
    await playback.seekEdition(75000);
    await playback.addBookmark();
  });
  tearDown(() async {
    await playback.close();
    downloads.dispose();
  });

  /// One decoder sample 200 ms later, as arrives several times a second
  /// while audio plays.
  void tick() {
    final before = playback.position!.milliseconds;
    engine.emit(engine.index, engine.milliseconds + 200);
    expect(playback.position!.milliseconds, before + 200);
  }

  group('a playing tick derives no list again:', () {
    test('the recent books stay the same list', () {
      final recent = playback.recent;
      tick();
      expect(playback.recent, same(recent));
    });

    test('the chapters stay the same list', () {
      final chapters = playback.chapters;
      tick();
      expect(playback.chapters, same(chapters));
    });

    test('the history and the bookmarks stay the same lists', () {
      final history = playback.history;
      final bookmarks = playback.bookmarks;
      tick();
      expect(playback.history, same(history));
      expect(playback.bookmarks, same(bookmarks));
    });

    test('the timeline of a book stays the same list', () {
      final entries = playback.timeline(title);
      tick();
      expect(playback.timeline(title), same(entries));
    });

    test('the bookmarks of the open edition stay the same list', () {
      final marks = playback.editionBookmarks;
      tick();
      expect(playback.editionBookmarks, same(marks));
    });
  });

  test('the timeline follows the book it is for', () {
    expect(
      [for (final entry in playback.timeline(title)) entry.bookTitle],
      [title.title, title.title],
    );
    expect(
      [for (final entry in playback.timeline(other)) entry.bookTitle],
      [other.title],
    );
  });

  test('the timeline follows a new bookmark', () async {
    final count = playback.timeline(null).length;
    await playback.addBookmark();
    expect(playback.timeline(null), hasLength(count + 1));
    expect(playback.timeline(null).first, isA<BookmarkEntry>());
  });

  test('the recent books follow a new listening action', () async {
    expect(
      [for (final entry in playback.recent) entry.book.id],
      [title.id, other.id],
    );
    await playback.open(other, otherRecording, autoplay: false);
    await playback.jump(forward: true);
    expect(
      [for (final entry in playback.recent) entry.book.id],
      [other.id, title.id],
    );
  });

  test('the recent books follow a library refresh', () async {
    expect(playback.recent, hasLength(2));
    await playback.bind(account(), [title]);
    expect([for (final entry in playback.recent) entry.book.id], [title.id]);
  });

  test('the chapters follow the open edition', () async {
    expect(playback.chapters, hasLength(4));
    await playback.open(other, otherRecording, autoplay: false);
    expect(
      [for (final chapter in playback.chapters) chapter.name],
      ['Only part'],
    );
  });

  test('the bookmarks of the open edition carry their edition times', () {
    expect([for (final mark in playback.editionBookmarks) mark.at], [75000]);
  });

  test('the bookmarks of the open edition leave out other books', () async {
    await playback.open(other, otherRecording, autoplay: false);
    await playback.addBookmark();
    await playback.open(title, recording, autoplay: false);
    expect(playback.bookmarks, hasLength(2));
    expect([for (final mark in playback.editionBookmarks) mark.at], [75000]);
  });

  test('the bookmarks of the open edition follow a new bookmark', () async {
    await playback.seekEdition(20000);
    await playback.addBookmark();
    expect(
      [for (final mark in playback.editionBookmarks) mark.at],
      [20000, 75000],
    );
  });

  test('the bookmarks of the open edition follow a rename', () async {
    final id = playback.bookmarks.single.id;
    await playback.editBookmark(id, title: 'The letter');
    expect(playback.editionBookmarks.single.bookmark.title, 'The letter');
    expect(playback.bookmarks.single.title, 'The letter');
  });

  test('the bookmarks of the open edition follow a deletion', () async {
    await playback.deleteBookmark(playback.bookmarks.single.id);
    expect(playback.editionBookmarks, isEmpty);
    expect(playback.bookmarks, isEmpty);
  });

  test('the history follows a deleted action', () async {
    final count = playback.history.length;
    await playback.deleteHistory(playback.history.first.id);
    expect(playback.history, hasLength(count - 1));
  });

  test(
    'a place in a book that is not open is measured in its edition',
    () async {
      final place = playback.bookmarks.single.position;
      await playback.open(other, otherRecording, autoplay: false);
      expect(playback.editionTime(place), 75000);
    },
  );

  test(
    'a library refresh without an edition stops measuring its places',
    () async {
      final place = playback.bookmarks.single.position;
      await playback.open(other, otherRecording, autoplay: false);
      expect(playback.editionTime(place), 75000);
      await playback.bind(account(), [other]);
      expect(playback.editionTime(place), isNull);
    },
  );
}
