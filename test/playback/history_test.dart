import 'dart:async';
import 'dart:convert';

import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:bookfin/playback/native.dart';
import 'package:bookfin/playback/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'playback_test.dart';

void main() {
  late LocalFiles downloads;
  late TestEngine engine;
  late MemoryResume store;
  late Playback playback;
  setUp(() async {
    downloads = LocalFiles();
    engine = TestEngine();
    store = MemoryResume();
    playback = Playback(downloads: downloads, engine: engine, store: store);
    await playback.bind(account(), [title]);
    await playback.open(title, recording);
  });
  tearDown(() async {
    await playback.close();
    downloads.dispose();
  });

  List<dynamic> savedHistory() =>
      store.values[account().scope.key]?['history'] as List? ?? [];

  test('accepted overlapping jumps retain each previous and resulting source position', () async {
    await playback.seekEdition(45000);
    await Future.wait([
      playback.jump(forward: true),
      playback.jump(forward: true),
    ]);
    await playback.flush();
    final jumps = savedHistory()
        .where((event) => event['kind'] == 'jump')
        .toList();
    expect(jumps, hasLength(2));
    expect(jumps[0]['before']['source'], first.key);
    expect(jumps[0]['before']['milliseconds'], 45000);
    expect(jumps[0]['after']['source'], second.key);
    expect(jumps[0]['after']['milliseconds'], 15000);
    expect(jumps[1]['before']['milliseconds'], 15000);
    expect(jumps[1]['after']['milliseconds'], 45000);
  });

  test(
    'pause resume and interruption are history but decoder ticks are not',
    () async {
      engine.emit(0, 11000, playing: true);
      engine.emit(0, 12000, playing: true);
      await playback.pause();
      await playback.play();
      engine.emit(0, 12500);
      engine.emit(0, 12500);
      engine.emit(0, 13000, playing: true);
      await playback.flush();
      expect(savedHistory().map((event) => event['kind']), [
        'resume',
        'pause',
        'resume',
        'interruption',
        'resume',
      ]);
    },
  );

  test('restart retains recovery actions beside the migrated resume', () async {
    await playback.seekEdition(75000);
    await playback.flush();
    final saved = savedHistory()
        .where((event) => event['kind'] == 'seek')
        .toList();
    expect(saved, hasLength(1));
    await playback.close();
    playback = Playback(
      downloads: downloads,
      engine: TestEngine(),
      store: store,
    );
    await playback.bind(account(), [title]);
    await playback.flush();
    expect(playback.position?.milliseconds, 15000);
    expect(savedHistory().where((event) => event['kind'] == 'seek'), saved);
  });

  test(
    'a slider drag records its starting place and only its completed target',
    () async {
      engine.emit(0, 11000, playing: true);
      await playback.beginSliderSeek();
      engine.emit(0, 13000, playing: true);
      await playback.finishSliderSeek(95000);
      final seek = playback.history
          .where((event) => event.kind == ListeningAction.seek)
          .single;
      expect(seek.before.milliseconds, 11000);
      expect(seek.after.sourceKey, second.key);
      expect(seek.after.milliseconds, 35000);
      await playback.undoSeek();
      expect(playback.position?.sourceKey, first.key);
      expect(playback.position?.milliseconds, 11000);
      expect(playback.history.first.kind, ListeningAction.undo);
      expect(
        playback.history.where((event) => event.id == seek.id),
        hasLength(1),
      );
    },
  );

  test(
    'overlapping recovery commands each start at the last accepted result',
    () async {
      await playback.seekEdition(45000);
      await playback.jump(forward: true);
      await Future.wait([playback.undoSeek(), playback.jump(forward: true)]);
      expect(playback.editionMilliseconds, 75000);
      expect(playback.history.first.before.milliseconds, 45000);
      expect(playback.history[1].kind, ListeningAction.undo);
      expect(playback.history[1].before.milliseconds, 15000);
      expect(playback.history[1].after.milliseconds, 45000);
    },
  );

  test('history restores either side after restart and adds rather than erases actions', () async {
    await playback.seekEdition(45000);
    await playback.jump(forward: true);
    final jump = playback.history.first;
    await playback.close();
    playback = Playback(
      downloads: downloads,
      engine: TestEngine(),
      store: store,
    );
    await playback.bind(account(), [title]);
    final count = playback.history.length;
    await playback.restoreHistory(jump.id);
    expect(playback.editionMilliseconds, 45000);
    expect(playback.history, hasLength(count + 1));
    expect(playback.history.first.kind, ListeningAction.historyRestore);
    await playback.restoreHistory(jump.id, previous: false);
    expect(playback.editionMilliseconds, 75000);
    expect(playback.history, hasLength(count + 2));
    expect(
      playback.history.where((event) => event.id == jump.id),
      hasLength(1),
    );
  });

  test(
    'bookmarks retain their ID and position through edits restart and delete',
    () async {
      await playback.seekEdition(75000);
      await playback.addBookmark(title: 'Arrival', note: 'Read this again');
      expect(playback.bookmarks, hasLength(1));
      final bookmark = playback.bookmarks.single;
      await playback.seekEdition(12000);
      await playback.editBookmark(
        bookmark.id,
        title: 'Return',
        note: 'New note',
      );
      expect(playback.bookmarks.single.id, bookmark.id);
      expect(playback.bookmarks.single.position.sourceKey, second.key);
      expect(playback.bookmarks.single.position.milliseconds, 15000);
      await playback.close();
      playback = Playback(
        downloads: downloads,
        engine: TestEngine(),
        store: store,
      );
      await playback.bind(account(), [title]);
      expect(playback.bookmarks.single.title, 'Return');
      expect(playback.bookmarks.single.note, 'New note');
      await playback.restoreBookmark(bookmark.id);
      expect(playback.editionMilliseconds, 75000);
      expect(playback.history.first.kind, ListeningAction.bookmarkRestore);
      await playback.editBookmark(bookmark.id);
      expect(playback.bookmarks.single.title, isNull);
      expect(playback.bookmarks.single.note, isNull);
      await playback.deleteBookmark(bookmark.id);
      await playback.bind(null, []);
      await playback.bind(account(), [title]);
      expect(playback.bookmarks, isEmpty);
    },
  );

  test('account switches hide personal records and restore only the matching account', () async {
    await playback.seekEdition(75000);
    await playback.addBookmark(title: 'Private');
    final id = playback.bookmarks.single.id;
    await playback.bind(account(user: 'bob'), [title]);
    expect(playback.bookmarks, isEmpty);
    expect(playback.history, isEmpty);
    await expectLater(playback.restoreBookmark(id), throwsArgumentError);
    await playback.bind(account(), [title]);
    expect(playback.bookmarks.single.id, id);
    expect(playback.position?.milliseconds, 15000);
  });

  test('a new command invalidates an unfinished slider drag', () async {
    await playback.beginSliderSeek();
    await playback.jump(forward: true);
    final count = playback.history.length;
    await playback.finishSliderSeek(90000);
    expect(playback.editionMilliseconds, 30000);
    expect(playback.history, hasLength(count));
  });

  test('failed seek leaves no accepted restore or changed position', () async {
    await playback.seekEdition(20000);
    await playback.addBookmark();
    final bookmark = playback.bookmarks.single;
    await playback.seekEdition(75000);
    final failing = FailingSeekEngine();
    await playback.close();
    playback = Playback(downloads: downloads, engine: failing, store: store);
    await playback.bind(account(), [title]);
    final count = playback.history.length;
    failing.fail = true;
    await playback.restoreBookmark(bookmark.id);
    expect(playback.editionMilliseconds, 75000);
    expect(playback.history, hasLength(count));
    expect(playback.message, contains('Cannot play'));
  });

  test(
    'changed sources keep old bookmarks and history without applying them',
    () async {
      await playback.seekEdition(75000);
      await playback.addBookmark();
      final bookmark = playback.bookmarks.single;
      final seek = playback.history.first;
      const changedSource = SourceFile(
        itemId: 'two',
        displayName: 'Changed',
        mediaSourceId: 'm2',
        revision: 'new',
        durationMs: 90000,
        container: 'wav',
        sizeBytes: 42,
      );
      const changedEdition = Edition(
        id: 'recording',
        kind: EditionKind.audio,
        label: 'Changed',
        files: [first, changedSource],
        memberIds: ['one:m1', 'two:m2'],
      );
      const changedBook = Book(
        id: 'book',
        title: 'The journey',
        author: 'A. Writer',
        editions: [changedEdition],
      );
      await playback.bind(account(), [changedBook]);
      final count = playback.history.length;
      await playback.restoreBookmark(bookmark.id);
      await playback.restoreHistory(seek.id, previous: false);
      expect(playback.position, isNull);
      expect(playback.bookmarks.single.position.revision, 'r2');
      expect(playback.history, hasLength(count));
      expect(playback.message, contains('changed'));
    },
  );

  test('durable write failure remains visible and retries without losing records on account switch', () async {
    final failing = FailingRecordStore();
    await playback.close();
    playback = Playback(
      downloads: downloads,
      engine: TestEngine(),
      store: failing,
    );
    await playback.bind(account(), [title]);
    await playback.open(title, recording);
    failing.fail = true;
    await playback.seekEdition(75000);
    await playback.addBookmark(title: 'Keep me');
    expect(playback.unsavedChanges, isTrue);
    expect(playback.message, contains('could not be saved'));
    await playback.bind(account(user: 'bob'), [title]);
    expect(playback.bookmarks, isEmpty);
    await playback.bind(account(), [title]);
    expect(playback.bookmarks.single.title, 'Keep me');
    expect(playback.editionMilliseconds, 75000);
    failing.fail = false;
    await playback.flush();
    expect(playback.unsavedChanges, isFalse);
    await playback.close();
    playback = Playback(
      downloads: downloads,
      engine: TestEngine(),
      store: failing,
    );
    await playback.bind(account(), [title]);
    expect(playback.bookmarks.single.title, 'Keep me');
    expect(
      playback.history.any((event) => event.kind == ListeningAction.seek),
      isTrue,
    );
  });

  test('failed restoration never overwrites stored personal records', () async {
    await playback.addBookmark(title: 'Keep');
    await playback.bind(null, []);
    final saved = jsonEncode(store.values[account().scope.key]);
    store.failRead = true;
    await playback.bind(account(), [title]);
    await playback.addBookmark(title: 'Not restored');
    await playback.flush();
    await playback.bind(null, []);
    expect(jsonEncode(store.values[account().scope.key]), saved);
    store.failRead = false;
  });

  test('opening a recording after a failed account read cannot start an unsaved session', () async {
    await playback.seekEdition(75000);
    await playback.bind(null, []);
    final saved = jsonEncode(store.values[account().scope.key]);
    store.failRead = true;
    await playback.bind(account(), [title]);
    await playback.open(title, recording);
    expect(playback.position, isNull);
    expect(playback.playing, isFalse);
    expect(playback.message, contains('Cannot restore'));
    await playback.flush();
    expect(jsonEncode(store.values[account().scope.key]), saved);
    store.failRead = false;
  });

  test('commands during account restoration wait for the restored personal records', () async {
    await playback.addBookmark(title: 'First');
    await playback.bind(null, []);
    store.readGate = Completer<void>();
    final binding = playback.bind(account(), [title]);
    final adding = playback.addBookmark(title: 'Second');
    await Future<void>.delayed(Duration.zero);
    store.readGate!.complete();
    await Future.wait([binding, adding]);
    expect(playback.bookmarks.map((bookmark) => bookmark.title), [
      'Second',
      'First',
    ]);
  });

  test(
    'native controls use the same history and Undo as on-screen controls',
    () async {
      final handler = PlaybackHandler()..attach(playback);
      await handler.seek(const Duration(milliseconds: 75000));
      expect(playback.history.first.before.milliseconds, 0);
      expect(playback.history.first.after.sourceKey, second.key);
      await handler.rewind();
      expect(playback.history.first.kind, ListeningAction.jump);
      expect(playback.history.first.after.milliseconds, 5000);
      await playback.undoSeek();
      expect(playback.position?.milliseconds, 15000);
      await handler.pause();
      expect(playback.history.first.kind, ListeningAction.pause);
      expect(playback.history.first.after.milliseconds, 15000);
      await handler.play();
      expect(playback.history.first.kind, ListeningAction.resume);
    },
  );

  test(
    'a verified local source is required before a bookmark restore is accepted',
    () async {
      await playback.addBookmark(title: 'Start');
      await playback.seekEdition(75000);
      final count = playback.history.length;
      downloads.files.remove(first.key);
      await playback.restoreBookmark(playback.bookmarks.single.id);
      expect(playback.editionMilliseconds, 75000);
      expect(playback.history, hasLength(count));
      expect(playback.message, contains('Download'));
    },
  );

  test(
    'an interruption during a durable seek write is still recorded',
    () async {
      final gated = GatedRecordStore();
      await playback.close();
      playback = Playback(
        downloads: downloads,
        engine: engine = TestEngine(),
        store: gated,
      );
      await playback.bind(account(), [title]);
      await playback.open(title, recording);
      await playback.flush();
      gated.gate = Completer<void>();
      final seeking = playback.seekEdition(75000);
      await Future<void>.delayed(Duration.zero);
      engine.emit(1, 15000);
      gated.gate!.complete();
      await seeking;
      expect(playback.playing, isFalse);
      expect(playback.history.first.kind, ListeningAction.interruption);
      expect(playback.history.first.after.milliseconds, 15000);
    },
  );

  test(
    'a failing old-account command cannot publish an error to the next account',
    () async {
      final gated = DeferredSeekEngine();
      await playback.close();
      playback = Playback(downloads: downloads, engine: gated, store: store);
      await playback.bind(account(), [title]);
      await playback.open(title, recording);
      final seeking = playback.seekEdition(75000);
      await Future<void>.delayed(Duration.zero);
      final switching = playback.bind(account(user: 'bob'), [title]);
      gated.gate.completeError(Exception('old decoder failed'));
      await Future.wait([seeking, switching]);
      expect(playback.history, isEmpty);
      expect(playback.position, isNull);
      expect(playback.message, isNull);
    },
  );

  test('version-one local resumes migrate without changing their source or playback settings', () async {
    await playback.close();
    SharedPreferences.setMockInitialValues({
      'bookfin.playback.v1.${account().scope.key}': jsonEncode({
        'version': 1,
        'selected': recording.id,
        'resumes': {
          recording.id: {
            'source': second.key,
            'revision': 'r2',
            'milliseconds': 18000,
            'pendingOffline': true,
          },
        },
        'speed': 1.5,
        'backward': 15,
        'forward': 45,
      }),
    });
    playback = Playback(
      downloads: downloads,
      engine: TestEngine(),
      store: LocalResumeStore(),
    );
    await playback.bind(account(), [title]);
    expect(playback.position?.sourceKey, second.key);
    expect(playback.position?.milliseconds, 18000);
    expect(playback.playbackSpeed, 1.5);
    expect(playback.backwardSeconds, 15);
    expect(playback.forwardSeconds, 45);
    expect(playback.history, isEmpty);
    await playback.addBookmark(title: 'Migrated');
    await playback.seekEdition(90000);
    await playback.close();
    playback = Playback(
      downloads: downloads,
      engine: TestEngine(),
      store: LocalResumeStore(),
    );
    await playback.bind(account(), [title]);
    expect(playback.bookmarks.single.position.milliseconds, 18000);
    expect(playback.position?.milliseconds, 30000);
    expect(
      playback.history.any((event) => event.kind == ListeningAction.seek),
      isTrue,
    );
  });

  test('an unreadable action prevents later writes from replacing any personal records', () async {
    await playback.seekEdition(75000);
    await playback.bind(null, []);
    final saved = jsonDecode(
      jsonEncode(store.values[account().scope.key]),
    ) as Map<String, dynamic>;
    (saved['history'] as List).first['kind'] = 'unknown-future-action';
    store.values[account().scope.key] = saved;
    await playback.bind(account(), [title]);
    await playback.flush();
    expect(playback.message, contains('Cannot restore'));
    expect(store.values[account().scope.key], saved);
  });

  test('history retains the confirmed decoder result rather than the requested target', () async {
    await playback.close();
    playback = Playback(
      downloads: downloads,
      engine: AdjustedSeekEngine(),
      store: store,
    );
    await playback.bind(account(), [title]);
    await playback.open(title, recording);
    await playback.seekEdition(75000);
    expect(playback.position?.milliseconds, 13000);
    expect(playback.history.first.after.milliseconds, 13000);
    expect(playback.history.first.after.sourceKey, second.key);
  });

  test(
    'a bookmark draft retains the place shown when the editor opens',
    () async {
      engine.emit(0, 12000, playing: true);
      final placeShown = playback.position!;
      engine.emit(0, 19000, playing: true);
      await playback.addBookmark(position: placeShown, title: 'Earlier place');
      expect(playback.bookmarks.single.position.milliseconds, 12000);
      expect(playback.position?.milliseconds, 19000);
    },
  );

  test(
    'restores between editions retain both edition positions and support Undo',
    () async {
      const alternate = Edition(
        id: 'alternate',
        kind: EditionKind.audio,
        label: 'Another narrator',
        files: [first],
        memberIds: ['one:m1'],
      );
      const anotherBook = Book(
        id: 'another',
        title: 'Another book',
        author: 'B. Writer',
        editions: [alternate],
      );
      await playback.bind(account(), [title, anotherBook]);
      await playback.seekEdition(75000);
      await playback.addBookmark(title: 'First recording');
      final bookmark = playback.bookmarks.single;
      await playback.open(anotherBook, alternate, autoplay: false);
      await playback.seekEdition(20000);
      await playback.restoreBookmark(bookmark.id);
      expect(playback.edition?.id, recording.id);
      expect(playback.history.first.before.editionId, alternate.id);
      expect(playback.history.first.before.milliseconds, 20000);
      expect(playback.history.first.after.editionId, recording.id);
      expect(playback.history.first.after.milliseconds, 15000);
      await playback.undoSeek();
      expect(playback.edition?.id, alternate.id);
      expect(playback.position?.milliseconds, 20000);
      playback.checkInvariants();
    },
  );
}

class FailingSeekEngine extends TestEngine {
  bool fail = false;
  @override
  Future<AudioSample> seek(int fileIndex, int position) async {
    if (fail) throw Exception('seek failed');
    return super.seek(fileIndex, position);
  }
}

class FailingRecordStore extends MemoryResume {
  bool fail = false;
  @override
  Future<void> write(String accountKey, Map<String, dynamic> value) async {
    if (fail) throw Exception('disk full');
    await super.write(accountKey, value);
  }
}

class GatedRecordStore extends MemoryResume {
  Completer<void>? gate;
  @override
  Future<void> write(String accountKey, Map<String, dynamic> value) async {
    await gate?.future;
    await super.write(accountKey, value);
  }
}

class DeferredSeekEngine extends TestEngine {
  final gate = Completer<void>();
  @override
  Future<AudioSample> seek(int fileIndex, int position) async {
    await gate.future;
    return super.seek(fileIndex, position);
  }
}

class AdjustedSeekEngine extends TestEngine {
  @override
  Future<AudioSample> seek(int fileIndex, int position) async {
    emit(fileIndex, position - 2000, playing: isPlaying);
    return AudioSample(index, milliseconds, playing: isPlaying);
  }
}
