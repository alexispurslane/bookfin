import 'dart:async';

import 'package:bookfin/playback/playback.dart';
import 'package:bookfin/playback/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'playback_test.dart';

/// A real store with a failure or a wait at the next save boundary.
class _FailingStore extends LocalResumeStore {
  final failures = <Object>[];
  HistoryAction? failureAction;
  Completer<void>? saveStarted;
  Completer<void>? saveRelease;

  @override
  Future<void> save(String accountKey, ListeningChanges changes) async {
    final matches =
        failureAction == null ||
        changes.history.values.any(
          (event) => event?['kind'] == failureAction!.name,
        );
    final failure = failures.isEmpty || !matches ? null : failures.removeAt(0);
    final started = saveStarted;
    if (started != null && !started.isCompleted) {
      started.complete();
      await saveRelease!.future;
    }
    if (failure != null) throw failure;
    return super.save(accountKey, changes);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _FailingStore store;
  late TestEngine engine;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = _FailingStore();
    engine = TestEngine();
  });

  Future<Map<String, dynamic>> saved() async =>
      (await LocalResumeStore().read(account().scope.key))!;

  Future<List<Object?>> savedBookmarks() async =>
      ((await saved())['bookmarks'] as List)
          .map((bookmark) => bookmark['title'])
          .toList();

  /// Runs assertions before cleanup. A test failure crosses the guarded
  /// zone through [done], so collecting an unhandled save bug cannot hide it.
  Future<List<Object>> withPlayback(
    Future<void> Function(Playback playback) body,
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
        try {
          await playback.bind(account(), [title]);
          await playback.open(title, recording);
          await playback.flush();
          await body(playback);
        } finally {
          store.failures.clear();
          if (store.saveRelease case final release? when !release.isCompleted) {
            release.complete();
          }
          await playback.close();
          downloads.dispose();
        }
        done.complete();
      } catch (error, stack) {
        done.completeError(error, stack);
      }
    }, (error, stack) => uncaught.add(error));
    await done.future;
    return uncaught;
  }

  Future<void> failBookmark(Playback playback) async {
    store.failures.add(StateError('A bug in the save.'));
    await playback.addBookmark(title: 'First');
  }

  group('after a save that failed with a bug', () {
    test('the next save writes, with the changes of the failed save', () async {
      final uncaught = await withPlayback((playback) async {
        await failBookmark(playback);
        await playback.addBookmark(title: 'Second');
        expect(await savedBookmarks(), unorderedEquals(['First', 'Second']));
      });
      expect(uncaught, [isStateError]);
    });

    test('a flush saves the changes of the failed save', () async {
      final uncaught = await withPlayback((playback) async {
        await failBookmark(playback);
        expect(playback.unsavedChanges, isTrue);
        await playback.flush();
        expect(playback.unsavedChanges, isFalse);
        expect(await savedBookmarks(), ['First']);
      });
      expect(uncaught, [isStateError]);
    });

    test('a command that waits for the saves runs to its end', () async {
      final uncaught = await withPlayback((playback) async {
        await failBookmark(playback);
        await playback.pause();
        expect(playback.playing, isFalse);
        expect(playback.statusNotifier.value, (
          message: null,
          saveFailed: false,
        ));
      });
      expect(uncaught, [isStateError]);
    });

    test('Playback closes', () async {
      final uncaught = await withPlayback((playback) async {
        await failBookmark(playback);
        await playback.close();
        expect(engine.closed, isTrue);
      });
      expect(uncaught, [isStateError]);
    });

    test('the bug is reported once, however many saves follow', () async {
      final uncaught = await withPlayback((playback) async {
        await failBookmark(playback);
        await playback.addBookmark(title: 'Second');
        await playback.pause();
        await playback.flush();
      });
      expect(uncaught, [isStateError]);
    });
  });

  for (final bug in [true, false]) {
    final kind = bug ? 'Error' : 'Exception';
    test('close reports the final $kind and keeps the stop event pending', () async {
      final firstFailure = StateError('The stop save failed.');
      final lastFailure = bug
          ? StateError('The close retry failed.')
          : Exception('The close retry failed.');
      final uncaught = await withPlayback((playback) async {
        store.failureAction = HistoryAction.stop;
        store.failures.addAll([firstFailure, lastFailure]);
        await expectLater(playback.close(), throwsA(same(lastFailure)));
        expect(playback.unsavedChanges, isTrue);
        expect(engine.closed, isTrue);
        expect(engine.events.hasListener, isFalse);
        expect(
          ((await saved())['history'] as List).where(
            (event) => event['kind'] == 'stop',
          ),
          isEmpty,
        );
        // A retained instance can still flush its pending changes after
        // teardown. Reading a fresh store proves that the stop event survived.
        await playback.flush();
        expect(playback.unsavedChanges, isFalse);
        expect(
          ((await saved())['history'] as List).where(
            (event) => event['kind'] == 'stop',
          ),
          hasLength(1),
        );
        await playback.close();
      });
      expect(uncaught, [same(firstFailure)]);
    });

    test('flush reports the $kind from its own retry save', () async {
      final firstFailure = StateError('The first save failed.');
      final lastFailure = bug
          ? StateError('The flush retry failed.')
          : Exception('The flush retry failed.');
      final uncaught = await withPlayback((playback) async {
        store.failures.add(firstFailure);
        await playback.addBookmark(title: 'Keep me');
        store.failures.add(lastFailure);
        await expectLater(playback.flush(), throwsA(same(lastFailure)));
        expect(playback.unsavedChanges, isTrue);
        await playback.flush();
        expect(await savedBookmarks(), ['Keep me']);
      });
      expect(uncaught, [same(firstFailure)]);
    });
  }

  test('close retries a failed stop save and stores its history', () async {
    final uncaught = await withPlayback((playback) async {
      store.failureAction = HistoryAction.stop;
      store.failures.add(StateError('The stop save failed.'));
      await playback.close();
      expect(engine.closed, isTrue);
      expect(playback.unsavedChanges, isFalse);
      expect(
        ((await saved())['history'] as List).where(
          (event) => event['kind'] == 'stop',
        ),
        hasLength(1),
      );
    });
    expect(uncaught, [isStateError]);
  });

  test('a history save keeps the overlapping position save when the position save fails', () async {
    final uncaught = await withPlayback((playback) async {
      store
        ..saveStarted = Completer<void>()
        ..saveRelease = Completer<void>();
      store.failures.add(StateError('The position save failed.'));
      engine.emit(0, 15000, playing: true);
      await store.saveStarted!.future;
      final pause = playback.pause();
      await pumpEventQueue();
      store.saveRelease!.complete();
      await pause;
      final records = await saved();
      expect(
        (records['resumes']['recording'] as List).single['milliseconds'],
        15000,
      );
      expect(
        (records['history'] as List)
            .where((event) => event['kind'] == 'pause')
            .single['after']['milliseconds'],
        15000,
      );
      expect(playback.unsavedChanges, isFalse);
    });
    expect(uncaught, [isStateError]);
  });

  test('close saves pending records of an account that was unbound', () async {
    final uncaught = await withPlayback((playback) async {
      store.failures.addAll([
        StateError('The bookmark save failed.'),
        StateError('The account change save failed.'),
      ]);
      await playback.addBookmark(title: 'Previous account');
      await playback.bind(account(user: 'bob'), [title]);
      await playback.close();
      expect(await savedBookmarks(), ['Previous account']);
    });
    expect(uncaught, [isStateError, isStateError]);
  });
}
