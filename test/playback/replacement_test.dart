import 'dart:async';
import 'dart:convert';

import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/foundation/theme.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:bookfin/playback/screen.dart';
import 'package:bookfin/playback/store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'history_test.dart' show FailingRecordStore, GatedRecordStore;
import 'playback_test.dart';

const revisedSecond = SourceFile(
  itemId: 'two',
  displayName: 'Replacement part two',
  mediaSourceId: 'm2',
  revision: 'replacement',
  durationMs: 90000,
  container: 'wav',
  sizeBytes: 42,
);
const replacement = Edition(
  id: 'recording',
  kind: EditionKind.audio,
  label: 'Replacement recording',
  files: [first, revisedSecond],
  memberIds: ['one:m1', 'two:m2'],
);
const revisedBook = Book(
  id: 'book',
  title: 'The journey',
  author: 'A. Writer',
  editions: [replacement],
);

void main() {
  late LocalFiles downloads;
  late ReplacementEngine engine;
  late MemoryResume store;
  late Playback playback;
  late String originalBookmark;
  late String originalSeek;

  Future<void> startWith(MemoryResume records) async {
    store = records;
    engine = ReplacementEngine();
    playback = Playback(downloads: downloads, engine: engine, store: store);
    await playback.bind(account(), [title]);
    await playback.open(title, recording, autoplay: false);
    await playback.seekEdition(78000);
    originalSeek = playback.history.first.id;
    await playback.addBookmark(title: 'Original place');
    originalBookmark = playback.bookmarks.single.id;
    await playback.bind(account(), [revisedBook]);
  }

  setUp(() async {
    downloads = LocalFiles();
    await startWith(MemoryResume());
  });
  tearDown(() async {
    engine.gate?.complete();
    await playback.close();
    downloads.dispose();
  });

  test(
    'changed audio offers a fresh start without applying the old position',
    () async {
      expect(playback.position, isNull);
      expect(playback.replacementStart, isNotNull);
      expect(playback.replacementStart!.previous.milliseconds, 18000);
      expect(playback.replacementStart!.previous.revision, 'r2');
      await playback.open(revisedBook, replacement);
      expect(playback.position, isNull);
      expect(playback.active, isFalse);
      expect(playback.bookmarks.single.id, originalBookmark);
    },
  );

  test(
    'confirmation starts replacement at zero and retains original records',
    () async {
      final request = playback.replacementStart;
      expect(request, isNotNull);
      final oldHistory = playback.history
          .map((event) => event.toJson())
          .toList();
      final oldBookmark = playback.bookmarks.single.toJson();
      await playback.confirmReplacement(request!);
      expect(playback.edition, replacement);
      expect(playback.editionMilliseconds, 0);
      expect(playback.position?.revision, 'r1');
      expect(playback.active, isTrue);
      expect(playback.replacementStart, isNull);
      expect(playback.bookmarks.single.toJson(), oldBookmark);
      expect(
        playback.history.map((event) => event.toJson()),
        containsAll(oldHistory),
      );
      await playback.restoreBookmark(originalBookmark);
      await playback.restoreHistory(originalSeek, previous: false);
      expect(playback.editionMilliseconds, 0);
      expect(playback.message, contains('changed'));
      playback.checkInvariants();
    },
  );

  test(
    'cancel keeps the old resume and permits another explicit offer',
    () async {
      await playback.flush();
      final before = jsonEncode(store.values);
      final request = playback.replacementStart;
      expect(request, isNotNull);
      playback.cancelReplacement(request!);
      expect(playback.replacementStart, isNull);
      await playback.confirmReplacement(request);
      expect(playback.position, isNull);
      expect(engine.playCount, 0);
      await playback.flush();
      expect(jsonEncode(store.values), before);
      await playback.open(revisedBook, replacement);
      expect(playback.replacementStart, isNotNull);
    },
  );

  test(
    'failed replacement load keeps the offer and the original resume',
    () async {
      final request = playback.replacementStart;
      expect(request, isNotNull);
      engine.failLoad = true;
      await playback.confirmReplacement(request!);
      expect(playback.position, isNull);
      expect(playback.active, isFalse);
      expect(playback.replacementStart, same(request));
      expect(playback.message, contains('Cannot play'));
      engine.failLoad = false;
      await playback.close();
      engine = ReplacementEngine();
      playback = Playback(downloads: downloads, engine: engine, store: store);
      await playback.bind(account(), [title]);
      expect(playback.position?.revision, 'r2');
      expect(playback.position?.milliseconds, 18000);
      expect(playback.bookmarks.single.id, originalBookmark);
    },
  );

  test(
    'restart reopens replacement and both recordings retain their own resume',
    () async {
      final request = playback.replacementStart;
      expect(request, isNotNull);
      await playback.confirmReplacement(request!);
      await playback.seekEdition(89000);
      await playback.addBookmark(title: 'Replacement place');
      final replacementBookmark = playback.bookmarks.first.id;
      await playback.close();
      engine = ReplacementEngine();
      playback = Playback(downloads: downloads, engine: engine, store: store);
      await playback.bind(account(), [revisedBook]);
      expect(playback.position?.revision, 'replacement');
      expect(playback.position?.milliseconds, 29000);
      expect(playback.replacementStart, isNull);
      await playback.seekEdition(0);
      await playback.restoreBookmark(replacementBookmark);
      expect(playback.position?.milliseconds, 29000);
      await playback.bind(account(), [title]);
      expect(playback.position?.revision, 'r2');
      expect(playback.position?.milliseconds, 18000);
      await playback.restoreBookmark(originalBookmark);
      expect(playback.position?.milliseconds, 18000);
      await playback.bind(account(), [revisedBook]);
      expect(playback.position?.revision, 'replacement');
      expect(playback.position?.milliseconds, 29000);
      expect(playback.bookmarks, hasLength(2));
      playback.checkInvariants();
    },
  );

  test(
    'replacement at an unchanged first file never overwrites original identity',
    () async {
      final request = playback.replacementStart;
      expect(request, isNotNull);
      await playback.confirmReplacement(request!);
      await playback.seekEdition(12000);
      await playback.bind(account(), [title]);
      expect(playback.position?.revision, 'r2');
      expect(playback.position?.milliseconds, 18000);
      await playback.bind(account(), [revisedBook]);
      expect(playback.editionMilliseconds, 12000);
    },
  );

  test('correcting file order keeps the same recording resume and reloads its decoder order', () async {
    await playback.confirmReplacement(playback.replacementStart!);
    await playback.seekEdition(89000);
    const reordered = Edition(
      id: 'recording',
      kind: EditionKind.audio,
      label: 'Replacement recording',
      files: [revisedSecond, first],
      memberIds: ['one:m1', 'two:m2'],
    );
    const reorderedBook = Book(
      id: 'book',
      title: 'The journey',
      author: 'A. Writer',
      editions: [reordered],
    );
    await playback.bind(account(), [reorderedBook]);
    expect(playback.position?.revision, 'replacement');
    expect(playback.position?.milliseconds, 29000);
    expect(playback.editionMilliseconds, 29000);
    expect(playback.replacementStart, isNull);
    await playback.seekEdition(35000);
    expect(playback.position?.sourceKey, 'two:m2');
    expect(playback.position?.milliseconds, 35000);
  });

  for (final duringLoad in [false, true]) {
    test(
      'account change rejects old confirmation (load started: $duringLoad)',
      () async {
        final request = playback.replacementStart;
        expect(request, isNotNull);
        Future<void>? confirming;
        if (duringLoad) {
          engine.gate = Completer<void>();
          confirming = playback.confirmReplacement(request!);
          await engine.loadStarted.future;
        }
        final switching = playback.bind(account(user: 'bob'), [revisedBook]);
        engine.gate?.complete();
        engine.gate = null;
        await confirming;
        await switching;
        await playback.confirmReplacement(request!);
        expect(playback.position, isNull);
        expect(playback.replacementStart, isNull);
        expect(playback.bookmarks, isEmpty);
        expect(playback.history, isEmpty);
        expect(playback.active, isFalse);
        await playback.bind(account(), [title]);
        expect(playback.position?.milliseconds, 18000);
        expect(playback.bookmarks.single.id, originalBookmark);
      },
    );
  }

  test('catalog refresh during confirmation cannot commit the obsolete replacement', () async {
    final request = playback.replacementStart!;
    engine.gate = Completer<void>();
    final confirming = playback.confirmReplacement(request);
    await engine.loadStarted.future;
    await playback.bind(account(), [title]);
    engine.gate!.complete();
    engine.gate = null;
    await confirming;
    expect(playback.position, isNull);
    expect(playback.active, isFalse);
    await playback.open(title, recording, autoplay: false);
    expect(playback.position?.revision, 'r2');
    expect(playback.position?.milliseconds, 18000);
  });

  test(
    'cancel during a replacement load cannot commit a fresh start',
    () async {
      final request = playback.replacementStart!;
      engine.gate = Completer<void>();
      final confirming = playback.confirmReplacement(request);
      await engine.loadStarted.future;
      playback.cancelReplacement(request);
      engine.gate!.complete();
      engine.gate = null;
      await confirming;
      expect(playback.position, isNull);
      expect(playback.active, isFalse);
      await playback.bind(account(), [title]);
      await playback.open(title, recording, autoplay: false);
      expect(playback.position?.milliseconds, 18000);
    },
  );

  test('an aborted replacement load keeps the prior recording recoverable without claiming it is playing', () async {
    const alternate = Edition(
      id: 'alternate',
      kind: EditionKind.audio,
      label: 'Another recording',
      files: [first],
      memberIds: ['one:m1'],
    );
    const anotherBook = Book(
      id: 'another',
      title: 'Another book',
      author: 'Writer',
      editions: [alternate],
    );
    await playback.bind(account(), [revisedBook, anotherBook]);
    await playback.open(anotherBook, alternate);
    await playback.seekEdition(20000);
    final undo = playback.undoAction;
    await playback.open(revisedBook, replacement);
    final request = playback.replacementStart!;
    engine.gate = Completer<void>();
    final confirming = playback.confirmReplacement(request);
    await engine.loadStarted.future;
    playback.cancelReplacement(request);
    engine.gate!.complete();
    engine.gate = null;
    await confirming;
    expect(playback.edition, alternate);
    expect(playback.editionMilliseconds, 20000);
    expect(playback.undoAction, same(undo));
    expect(playback.playing, isFalse);
    expect(playback.active, isFalse);
    await playback.play();
    expect(playback.editionMilliseconds, 20000);
    expect(playback.playing, isTrue);
    await playback.undoSeek();
    expect(playback.editionMilliseconds, 0);
    playback.checkInvariants();
  });

  test(
    'fresh start cannot accept audio with an unknown source revision',
    () async {
      const unidentified = Edition(
        id: 'recording',
        kind: EditionKind.audio,
        label: 'Unknown replacement',
        files: [
          first,
          SourceFile(
            itemId: 'two',
            mediaSourceId: 'm2',
            revision: '',
            displayName: 'Unknown part two',
            durationMs: 90000,
            container: 'wav',
            sizeBytes: 42,
          ),
        ],
        memberIds: ['one:m1', 'two:m2'],
      );
      const unknownBook = Book(
        id: 'book',
        title: 'The journey',
        author: 'A. Writer',
        editions: [unidentified],
      );
      await playback.bind(account(), [unknownBook]);
      await playback.confirmReplacement(playback.replacementStart!);
      expect(playback.position, isNull);
      expect(playback.active, isFalse);
      expect(playback.bookmarks.single.id, originalBookmark);
      await playback.bind(account(), [title]);
      await playback.open(title, recording, autoplay: false);
      expect(playback.position?.milliseconds, 18000);
    },
  );

  test(
    'catalog refresh during file lookup cannot publish an obsolete offer',
    () async {
      downloads.lookupGate = Completer<void>();
      final opening = playback.open(revisedBook, replacement);
      await Future<void>.delayed(Duration.zero);
      await playback.bind(account(), [title]);
      downloads.lookupGate!.complete();
      downloads.lookupGate = null;
      await opening;
      expect(playback.replacementStart, isNull);
      playback.checkInvariants();
      await playback.open(title, recording, autoplay: false);
      expect(playback.position?.milliseconds, 18000);
    },
  );

  for (final version in [1, 2]) {
    test(
      'version-$version legacy position in an unchanged file survives replacement playback',
      () async {
        await playback.close();
        SharedPreferences.setMockInitialValues({
          'bookfin.playback.v1.${account().scope.key}': jsonEncode({
            'version': version,
            'selected': 'recording',
            'resumes': {
              'recording': {
                'source': 'one:m1',
                'revision': 'r1',
                'milliseconds': 12000,
              },
            },
            'history': [],
            'bookmarks': [],
          }),
        });
        engine = ReplacementEngine();
        playback = Playback(
          downloads: downloads,
          engine: engine,
          store: LocalResumeStore(),
        );
        await playback.bind(account(), [revisedBook]);
        expect(playback.position?.milliseconds, 12000);
        await playback.seekEdition(78000);
        await playback.close();
        engine = ReplacementEngine();
        playback = Playback(
          downloads: downloads,
          engine: engine,
          store: LocalResumeStore(),
        );
        await playback.bind(account(), [title]);
        expect(playback.position?.revision, 'r1');
        expect(playback.position?.milliseconds, 12000);
        await playback.bind(account(), [revisedBook]);
        expect(playback.position?.revision, 'replacement');
        expect(playback.position?.milliseconds, 18000);
        playback.checkInvariants();
      },
    );

    test(
      'version-$version resume migration retains old audio beside a confirmed replacement',
      () async {
        await playback.close();
        final legacy = {
          'version': version,
          'selected': 'recording',
          'resumes': {
            'recording': {
              'source': 'two:m2',
              'revision': 'r2',
              'milliseconds': 18000,
              'pendingOffline': true,
            },
          },
          'history': playback.history.map((event) => event.toJson()).toList(),
          'bookmarks': playback.bookmarks
              .map((bookmark) => bookmark.toJson())
              .toList(),
          'speed': 1.5,
          'backward': 15,
          'forward': 45,
        };
        SharedPreferences.setMockInitialValues({
          'bookfin.playback.v1.${account().scope.key}': jsonEncode(legacy),
        });
        engine = ReplacementEngine();
        playback = Playback(
          downloads: downloads,
          engine: engine,
          store: LocalResumeStore(),
        );
        await playback.bind(account(), [revisedBook]);
        expect(playback.position, isNull);
        await playback.confirmReplacement(playback.replacementStart!);
        await playback.seekEdition(8000);
        expect(playback.playbackSpeed, 1.5);
        expect(playback.backwardSeconds, 15);
        expect(playback.forwardSeconds, 45);
        await playback.close();
        engine = ReplacementEngine();
        playback = Playback(
          downloads: downloads,
          engine: engine,
          store: LocalResumeStore(),
        );
        await playback.bind(account(), [revisedBook]);
        expect(playback.editionMilliseconds, 8000);
        await playback.bind(account(), [title]);
        expect(playback.position?.revision, 'r2');
        expect(playback.position?.milliseconds, 18000);
        expect(playback.pendingOfflineResume, isTrue);
        if (version == 2) {
          expect(playback.bookmarks.single.id, originalBookmark);
          await playback.restoreHistory(originalSeek, previous: false);
          expect(playback.position?.milliseconds, 18000);
        }
        await playback.bind(account(), [revisedBook]);
        expect(playback.editionMilliseconds, 8000);
      },
    );
  }

  test(
    'failed account writes keep original and replacement pending until retry',
    () async {
      await playback.close();
      final failing = FailingRecordStore();
      await startWith(failing);
      failing.fail = true;
      final request = playback.replacementStart;
      expect(request, isNotNull);
      await playback.confirmReplacement(request!);
      await playback.seekEdition(88000);
      expect(playback.unsavedChanges, isTrue);
      await playback.bind(account(user: 'bob'), [revisedBook]);
      await playback.bind(account(), [revisedBook]);
      expect(playback.position?.revision, 'replacement');
      expect(playback.position?.milliseconds, 28000);
      expect(playback.bookmarks.single.id, originalBookmark);
      failing.fail = false;
      await playback.flush();
      expect(playback.unsavedChanges, isFalse);
      await playback.bind(account(), [title]);
      expect(playback.position?.milliseconds, 18000);
    },
  );

  test(
    'confirmation waits behind a pending record write without dropping it',
    () async {
      await playback.close();
      final gated = GatedRecordStore();
      await startWith(gated);
      final request = playback.replacementStart;
      expect(request, isNotNull);
      gated.gate = Completer<void>();
      final saving = playback.flush();
      await Future<void>.delayed(Duration.zero);
      final confirming = playback.confirmReplacement(request!);
      gated.gate!.complete();
      await Future.wait([saving, confirming]);
      expect(playback.editionMilliseconds, 0);
      await playback.bind(account(), [title]);
      expect(playback.position?.milliseconds, 18000);
      expect(playback.bookmarks.single.id, originalBookmark);
    },
  );

  testWidgets(
    'fresh start requires confirmation and Cancel keeps saved records',
    (tester) async {
      addTearDown(() => tester.runAsync(playback.close));
      await tester.pumpWidget(
        MaterialApp(
          theme: bookfinTheme(Brightness.light),
          home: Scaffold(body: PlayerView(playback: playback)),
        ),
      );
      await tester.runAsync(() => tester.tap(find.text('Start replacement')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('history and bookmarks'), findsOneWidget);
      expect(playback.position, isNull);
      await tester.runAsync(() => tester.tap(find.text('Cancel')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(playback.position, isNull);
      expect(playback.bookmarks.single.id, originalBookmark);
      await tester.runAsync(() => playback.open(revisedBook, replacement));
      await tester.pumpAndSettle();
      await tester.runAsync(() => tester.tap(find.text('Start replacement')));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Start from beginning'));
        await playback.flush();
      });
      await tester.pumpAndSettle();
      expect(playback.editionMilliseconds, 0);
      expect(playback.active, isTrue);
      expect(playback.bookmarks.single.id, originalBookmark);
    },
  );
}

class ReplacementEngine extends TestEngine {
  bool failLoad = false;
  Completer<void>? gate;
  final loadStarted = Completer<void>();

  @override
  Future<void> load(List<Uri> sources, int fileIndex, int position) async {
    if (gate != null) {
      loadStarted.complete();
      await gate!.future;
    }
    if (failLoad) throw Exception('replacement decoder failed');
    await super.load(sources, fileIndex, position);
  }
}
