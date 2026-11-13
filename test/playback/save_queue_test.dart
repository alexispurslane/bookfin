import 'dart:async';

import 'package:bookfin/playback/playback.dart';
import 'package:flutter_test/flutter_test.dart';

import 'playback_test.dart';

/// A record store whose next save fails with [failure].
class _FailingStore extends MemoryResume {
  Object? failure;

  @override
  Future<void> save(String accountKey, ListeningChanges changes) async {
    final failure = this.failure;
    this.failure = null;
    if (failure != null) throw failure;
    return super.save(accountKey, changes);
  }
}

// How Playback's saves treat a save that fails with a bug: an Error that is
// not an Exception. The bug stays visible, and it never stops a later save,
// because a place or a history entry that is not saved is lost data.
void main() {
  late _FailingStore store;
  late TestEngine engine;
  setUp(() {
    store = _FailingStore();
    engine = TestEngine();
  });

  /// The titles of the bookmarks that the store holds.
  Iterable<Object?> savedBookmarks() =>
      (store.values[account().scope.key]?['bookmarks'] as List? ?? []).map(
        (bookmark) => bookmark['title'],
      );

  /// Plays the recording, makes the save of a first bookmark fail with a
  /// bug, runs [after], and closes Playback. Returns the errors that nothing
  /// caught.
  ///
  /// The save of the first bookmark runs with no caller that holds its
  /// future. These tests do not state where its bug goes, only that it is
  /// reported once, so they ignore the future of that command.
  Future<List<Object>> afterBuggySave(
    Future<void> Function(Playback playback) after,
  ) async {
    final uncaught = <Object>[];
    final done = Completer<void>();
    runZonedGuarded(() async {
      final downloads = LocalFiles();
      final playback = Playback(
        downloads: downloads,
        engine: engine,
        store: store,
      );
      try {
        await playback.bind(account(), [title]);
        await playback.open(title, recording);
        await playback.flush();
        store.failure = StateError('A bug in the save.');
        await playback.addBookmark(title: 'First').catchError((Object _) {});
        await after(playback);
        await playback.close();
        downloads.dispose();
      } finally {
        done.complete();
      }
    }, (error, stack) => uncaught.add(error));
    await done.future;
    return uncaught;
  }

  // NOTE: An expectation inside [afterBuggySave] would fail into the guarded
  // zone, where nothing reads it. Each test takes values out and states its
  // expectations after the zone ended.
  group('after a save that failed with a bug', () {
    test('the next save writes, with the changes of the failed save', () async {
      await afterBuggySave((playback) async {
        await playback.addBookmark(title: 'Second');
      });

      expect(savedBookmarks(), unorderedEquals(['First', 'Second']));
    });

    test('a flush saves the changes of the failed save', () async {
      bool? unsavedBefore;
      bool? unsavedAfter;
      await afterBuggySave((playback) async {
        unsavedBefore = playback.unsavedChanges;
        await playback.flush();
        unsavedAfter = playback.unsavedChanges;
      });

      expect(unsavedBefore, isTrue);
      expect(unsavedAfter, isFalse);
      expect(savedBookmarks(), ['First']);
    });

    test('a command that waits for the saves runs to its end', () async {
      PlaybackStatus? status;
      bool? playing;
      await afterBuggySave((playback) async {
        await playback.pause();
        playing = playback.playing;
        status = playback.statusNotifier.value;
      });

      expect(playing, isFalse);
      expect(status, (message: null, saveFailed: false));
    });

    test('Playback closes', () async {
      await afterBuggySave((playback) async {});

      expect(engine.closed, isTrue);
    });

    test('the bug is reported once, however many saves follow', () async {
      var allRan = false;
      final uncaught = await afterBuggySave((playback) async {
        await playback.addBookmark(title: 'Second');
        await playback.pause();
        await playback.flush();
        allRan = true;
      });

      expect(allRan, isTrue);
      expect(uncaught, [isStateError]);
    });
  });
}
