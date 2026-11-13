import 'dart:async';

import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:bookfin/playback/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'playback_test.dart';
import 'held_engine.dart';

const _otherEdition = Edition(
  id: 'other',
  kind: EditionKind.audio,
  label: 'Other recording',
  files: [first],
  memberIds: ['one:m1'],
);
const _otherBook = Book(
  id: 'other',
  title: 'Other book',
  author: '',
  editions: [_otherEdition],
);

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
  late HeldEngine engine;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = _FailingStore();
    engine = HeldEngine();
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
          await playback.bind(account(), [title, _otherBook]);
          await playback.open(title, recording);
          await playback.flush();
          await body(playback);
        } finally {
          engine.release();
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

  for (final command in HeldCommand.values) {
    test(
      'flush saves only the confirmed place during a held ${command.name}',
      () async {
        final uncaught = await withPlayback((playback) async {
          await playback.seekEdition(11000);
          await playback.addBookmark(title: 'Confirmed');
          final history = playback.history
              .map((event) => event.toJson())
              .toList();
          // This sample stays within the same second, so flush must save it.
          engine.emit(0, 11234, playing: true);
          engine.held = command;
          var commandFinished = false;
          final running = switch (command) {
            HeldCommand.load => playback.open(_otherBook, _otherEdition),
            HeldCommand.seek => playback.seekEdition(78000),
            HeldCommand.pause => playback.pause(),
          }.then((_) => commandFinished = true);
          await engine.entered.future;
          var flushed = false;
          final flushing = playback.flush().then((_) => flushed = true);
          try {
            await flushing.timeout(const Duration(seconds: 5));
            expect(flushed, isTrue, reason: 'local writes do not await audio');
            expect(commandFinished, isFalse);
            final records = await saved();
            expect(records['selected'], 'recording');
            expect(records['resumes'].keys, ['recording']);
            expect(
              records['resumes']['recording'].single['milliseconds'],
              11234,
            );
            expect(records['history'], unorderedEquals(history));
            expect(await savedBookmarks(), ['Confirmed']);
            expect(playback.undoNotifier.value?.saved, isTrue);
          } finally {
            engine.release();
            await running;
            await flushing;
          }
          // The command saves its own result, without a second flush.
          if (command != HeldCommand.load) {
            final records = await saved();
            expect(
              records['resumes']['recording'].single['milliseconds'],
              command == HeldCommand.seek ? 18000 : 11234,
            );
            expect(
              (records['history'] as List).where(
                (event) => event['kind'] == command.name,
              ),
              hasLength(command == HeldCommand.seek ? 2 : 1),
            );
          }
        });
        expect(uncaught, isEmpty);
      },
    );
  }

  test(
    'flush waits for local durability while an audio seek stays held',
    () async {
      final uncaught = await withPlayback((playback) async {
        await playback.seekEdition(11000);
        engine.emit(0, 11234, playing: true);
        engine.held = HeldCommand.seek;
        final seeking = playback.seekEdition(78000);
        await engine.entered.future;
        store
          ..saveStarted = Completer<void>()
          ..saveRelease = Completer<void>();
        var flushed = false;
        final flushing = playback.flush().then((_) => flushed = true);
        try {
          await pumpEventQueue();
          expect(store.saveStarted!.isCompleted, isTrue);
          expect(flushed, isFalse);
          expect(
            (await saved())['resumes']['recording'].single['milliseconds'],
            11000,
          );
          store.saveRelease!.complete();
          await flushing.timeout(const Duration(seconds: 5));
          expect(flushed, isTrue);
          expect(engine.released.isCompleted, isFalse);
          expect(
            (await saved())['resumes']['recording'].single['milliseconds'],
            11234,
          );
        } finally {
          if (!store.saveRelease!.isCompleted) store.saveRelease!.complete();
          engine.release();
          await seeking;
          await flushing;
        }
      });
      expect(uncaught, isEmpty);
    },
  );

  test(
    'flush retries failed records while an account change waits for audio',
    () async {
      final uncaught = await withPlayback((playback) async {
        store.failures.addAll([
          Exception('bookmark storage unavailable'),
          Exception('account-change storage unavailable'),
        ]);
        await playback.addBookmark(title: 'Alice only');
        expect(playback.unsavedChanges, isTrue);
        engine.held = HeldCommand.seek;
        final seeking = playback.seekEdition(78000);
        await engine.entered.future;
        final binding = playback.bind(account(user: 'bob'), [title]);
        var flushed = false;
        final flushing = playback.flush().then((_) => flushed = true);
        try {
          await flushing.timeout(const Duration(seconds: 5));
          expect(flushed, isTrue);
          expect(await savedBookmarks(), ['Alice only']);
          expect(
            await LocalResumeStore().read(account(user: 'bob').scope.key),
            isNull,
          );
          expect(engine.released.isCompleted, isFalse);
        } finally {
          engine.release();
          await seeking;
          await binding;
          await flushing;
        }
        expect(playback.bookmarks, isEmpty);
        expect(playback.position, isNull);
        await playback.bind(account(), [title]);
        expect(playback.bookmarks.single.title, 'Alice only');
        expect(playback.position?.milliseconds, 0);
        expect(
          playback.history.where((event) => event.kind == HistoryAction.seek),
          isEmpty,
        );
      });
      expect(uncaught, isEmpty);
    },
  );

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
          actionNotice: null,
          recoveryMessage: null,
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

  // A save that fails with an Exception is an expected failure, such as
  // full storage. Its report is the save status, and flush and close
  // complete normally, as the reader session does. A save that fails with
  // an Error is a bug, and flush and close hand it to their caller.
  for (final bug in [true, false]) {
    final kind = bug ? 'Error' : 'Exception';
    final report = bug ? 'hands its caller' : 'keeps as the save status';
    test('close $report the final $kind and keeps the stop event pending', () async {
      final firstFailure = StateError('The stop save failed.');
      final lastFailure = bug
          ? StateError('The close retry failed.')
          : Exception('The close retry failed.');
      final uncaught = await withPlayback((playback) async {
        store.failureAction = HistoryAction.stop;
        store.failures.addAll([firstFailure, lastFailure]);
        await expectLater(
          playback.close(),
          bug ? throwsA(same(lastFailure)) : completes,
        );
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

    test('flush $report the $kind of its own retry save', () async {
      final firstFailure = StateError('The first save failed.');
      final lastFailure = bug
          ? StateError('The flush retry failed.')
          : Exception('The flush retry failed.');
      final uncaught = await withPlayback((playback) async {
        store.failures.add(firstFailure);
        await playback.addBookmark(title: 'Keep me');
        store.failures.add(lastFailure);
        await expectLater(
          playback.flush(),
          bug ? throwsA(same(lastFailure)) : completes,
        );
        expect(playback.unsavedChanges, isTrue);
        expect(playback.statusNotifier.value.saveFailed, !bug);
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
