import 'dart:async';

import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:flutter_test/flutter_test.dart';

import 'playback_test.dart'
    show LocalFiles, TestEngine, MemoryResume, account, title, recording;
import 'timeline_test.dart' show other;

/// An audio engine whose loads can be held, as a slow decoder holds them,
/// and which counts its loads.
class GatedEngine extends TestEngine {
  Completer<void>? loadGate;
  int loads = 0;
  @override
  Future<void> load(List<Uri> sources, int fileIndex, int position) async {
    loads++;
    await loadGate?.future;
    await super.load(sources, fileIndex, position);
  }
}

/// [book] as a library refresh rebuilds it: equal values in new objects.
/// [title] corrects the book's title. [revision] gives every source file a
/// new revision, as when the server replaced the audio.
Book refreshed(Book book, {String? title, String? revision}) => Book(
  id: book.id,
  title: title ?? book.title,
  author: book.author,
  editions: [
    for (final edition in book.editions)
      Edition(
        id: edition.id,
        kind: edition.kind,
        label: edition.label,
        memberIds: [...edition.memberIds],
        files: [
          for (final file in edition.files)
            SourceFile(
              itemId: file.itemId,
              displayName: file.displayName,
              mediaSourceId: file.mediaSourceId,
              revision: revision ?? file.revision,
              durationMs: file.durationMs,
              container: file.container,
              sizeBytes: file.sizeBytes,
              chapters: [...file.chapters],
            ),
        ],
      ),
  ],
);

/// Lets every pending step run up to the next held gate.
Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  late LocalFiles downloads;
  late GatedEngine engine;
  late MemoryResume store;
  late Playback playback;
  late List<String> savedHistory;

  // The listener left the recording paused 72 s in, then closed Bookfin.
  setUp(() async {
    downloads = LocalFiles();
    store = MemoryResume();
    final earlier = Playback(
      downloads: downloads,
      engine: TestEngine(),
      store: store,
    );
    await earlier.bind(account(), [title, other]);
    await earlier.open(title, recording, autoplay: false);
    await earlier.seekEdition(72000);
    await earlier.pause();
    await earlier.flush();
    savedHistory = [for (final event in earlier.history) event.id];
    await earlier.close();
    engine = GatedEngine();
    playback = Playback(downloads: downloads, engine: engine, store: store);
  });
  tearDown(() async {
    await playback.close();
    downloads.dispose();
  });

  /// Starts Bookfin again with the same account and store, binds [books],
  /// and returns where the saved book reopened, in edition milliseconds.
  Future<int?> relaunch(List<Book> books) async {
    await playback.close();
    playback = Playback(
      downloads: downloads,
      engine: TestEngine(),
      store: store,
    );
    await playback.bind(account(), books);
    await playback.flush();
    return playback.editionMilliseconds;
  }

  group('at launch the saved book', () {
    test('reopens paused at its saved position while the library refresh '
        'replaces it with equal books', () async {
      downloads.lookupGate = Completer<void>();
      final launch = playback.bind(account(), [title, other]);
      await settle();
      final fresh = refreshed(title);
      final refresh = playback.bind(account(), [fresh, refreshed(other)]);
      downloads.lookupGate!.complete();
      await launch;

      expect(playback.edition?.id, recording.id);
      expect(playback.editionMilliseconds, 72000);
      expect(playback.playing, isFalse);

      await refresh;
      await playback.flush();
      expect(playback.book, same(fresh));
      expect(playback.selectionNotifier.value.book, same(fresh));
      expect(playback.editionMilliseconds, 72000);
      expect(engine.loads, 1, reason: 'the refresh does not reload audio');
      playback.checkInvariants();
    });

    test(
      'shows a title correction that arrives while its audio loads',
      () async {
        engine.loadGate = Completer<void>();
        final launch = playback.bind(account(), [title, other]);
        await settle();
        final corrected = refreshed(title, title: 'Corrected journey');
        final refresh = playback.bind(account(), [corrected, other]);
        engine.loadGate!.complete();
        await Future.wait([launch, refresh]);
        await playback.flush();

        expect(playback.book, same(corrected));
        expect(
          playback.selectionNotifier.value.book?.title,
          'Corrected journey',
        );
        expect(playback.editionMilliseconds, 72000);
        playback.checkInvariants();
      },
    );

    test('stays open and plays from downloads when the refresh cannot reach '
        'Jellyfin and the library keeps only downloaded books', () async {
      downloads.lookupGate = Completer<void>();
      final launch = playback.bind(account(), [title, other]);
      await settle();
      final downloaded = refreshed(title);
      final refresh = playback.bind(account(), [downloaded]);
      downloads.lookupGate!.complete();
      await launch;
      expect(playback.edition?.id, recording.id);
      await refresh;

      await playback.play();

      expect(playback.book, same(downloaded));
      expect(playback.playing, isTrue);
      expect(playback.position?.milliseconds, 12000);
      expect(downloads.requested, isEmpty);
      expect(engine.loads, 1, reason: 'the refresh does not reload audio');
      playback.checkInvariants();
    });

    test(
      'keeps its saved position and history through the replacement',
      () async {
        engine.loadGate = Completer<void>();
        final launch = playback.bind(account(), [title, other]);
        await settle();
        final refresh = playback.bind(account(), [
          refreshed(title),
          refreshed(other),
        ]);
        engine.loadGate!.complete();
        await Future.wait([launch, refresh]);
        await playback.flush();

        expect(await relaunch([title, other]), 72000);
        expect([for (final event in playback.history) event.id], savedHistory);
      },
    );

    test('stays closed and keeps its saved position when the refresh changes '
        'its audio mid-reopen', () async {
      downloads.lookupGate = Completer<void>();
      final launch = playback.bind(account(), [title, other]);
      await settle();
      final revised = refreshed(title, revision: 'r9');
      final refresh = playback.bind(account(), [revised, other]);
      downloads.lookupGate!.complete();
      await Future.wait([launch, refresh]);
      await playback.flush();

      expect(playback.edition, isNull);
      expect(playback.replacementStart?.edition, same(revised.editions.single));
      expect(engine.loads, 0);
      playback.checkInvariants();

      expect(await relaunch([title, other]), 72000);
      expect([for (final event in playback.history) event.id], savedHistory);
    });
  });

  test(
    'a book that the listener opens while the library refreshes plays',
    () async {
      downloads.files[other.editions.single.files.single.key] = Uri.file(
        '/three.wav',
      );
      await playback.bind(account(), [title, other]);
      downloads.lookupGate = Completer<void>();
      final opening = playback.open(other, other.editions.single);
      await settle();
      final fresh = refreshed(other);
      final refresh = playback.bind(account(), [refreshed(title), fresh]);
      downloads.lookupGate!.complete();
      await Future.wait([opening, refresh]);

      expect(playback.book, same(fresh));
      expect(playback.playing, isTrue);
      playback.checkInvariants();
    },
  );
}
