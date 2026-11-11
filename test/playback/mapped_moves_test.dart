// A mapped move: Go to on a place of the other medium moves the open
// edition to that place's landing, as a move in the open edition's own
// track, with Undo. It records the place of the other edition that it went
// to, and never writes a record of the other medium (docs/plans/
// cross-edition-places.md, "The move, Undo and the other edition").
import 'dart:convert';

import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/crossings/crossings.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:bookfin/reader/session.dart' show ReadingChanges;
import 'package:flutter_test/flutter_test.dart';

import 'playback_test.dart';

/// A reading place of an ebook edition of [title].
final readingPlace = TextPosition(
  editionId: 'ebook',
  sourceKey: 'book:original',
  revision: 't1',
  anchor: jsonEncode({
    'resource': 'OPS/b.xhtml',
    'progress': .2,
    'quote': 'Words.',
  }),
);

/// The landing of [readingPlace] 20 s into the second file of [recording].
final landing = AudioLanding(
  readingPlace,
  AudioPosition(
    editionId: recording.id,
    sourceKey: second.key,
    revision: second.revision,
    milliseconds: 20000,
  ),
);

/// A store that counts the saves of each medium.
class MediumSpy extends MemoryResume {
  final listening = <ListeningChanges>[];
  final reading = <ReadingChanges>[];

  @override
  Future<void> save(String accountKey, ListeningChanges changes) {
    listening.add(changes);
    return super.save(accountKey, changes);
  }

  @override
  Future<void> saveReading(String accountKey, ReadingChanges changes) {
    reading.add(changes);
    return super.saveReading(accountKey, changes);
  }
}

void main() {
  group('the record of a mapped move', () {
    final listeningPlace = AudioPosition(
      editionId: 'recording',
      sourceKey: 'one:m1',
      revision: 'r1',
      milliseconds: 3735000,
    );

    HistoryEvent<TextPosition> mapped() => HistoryEvent(
      id: 'move',
      at: DateTime.utc(2026, 11, 11, 21, 40),
      kind: HistoryAction.historyRestore,
      before: readingPlace,
      after: readingPlace,
      bookTitle: 'Moby-Dick',
      editionLabel: 'EPUB',
      counterpartOf: listeningPlace,
      matchedBy: MatchedBy.chapters,
    );

    test('names the place of the other edition that it went to, and how '
        'Bookfin found its landing', () {
      final json = mapped().toJson();

      expect(json['counterpartOf'], {
        'edition': 'recording',
        'source': 'one:m1',
        'revision': 'r1',
        'milliseconds': 3735000,
      });
      expect(json['matchedBy'], 'chapters');
    });

    test('reads back with a counterpart of the other medium', () {
      final read = HistoryEvent.fromJson(
        jsonDecode(jsonEncode(mapped().toJson())) as Map<String, dynamic>,
        decodeTextPosition,
      );

      expect(read.counterpartOf, isA<AudioPosition>());
      expect(
        (read.counterpartOf! as AudioPosition).milliseconds,
        listeningPlace.milliseconds,
      );
      expect(read.matchedBy, MatchedBy.chapters);
    });

    test('of a listening move names a reading place', () {
      final move = HistoryEvent(
        id: 'move',
        at: DateTime.utc(2026, 11, 11),
        kind: HistoryAction.historyRestore,
        before: listeningPlace,
        after: listeningPlace,
        bookTitle: 'Moby-Dick',
        editionLabel: 'Narrator',
        counterpartOf: readingPlace,
        matchedBy: MatchedBy.chapters,
      );

      final read = HistoryEvent.fromJson(
        jsonDecode(jsonEncode(move.toJson())) as Map<String, dynamic>,
        decodePosition,
      );

      expect((read.counterpartOf! as TextPosition).anchor, readingPlace.anchor);
    });

    test('of a move that is not mapped has neither field', () {
      final plain = HistoryEvent(
        id: 'move',
        at: DateTime.utc(2026, 11, 11),
        kind: HistoryAction.seek,
        before: readingPlace,
        after: readingPlace,
        bookTitle: 'Moby-Dick',
        editionLabel: 'EPUB',
      );

      expect(plain.toJson().keys, isNot(contains('counterpartOf')));
      expect(plain.toJson().keys, isNot(contains('matchedBy')));
    });

    test('with a counterpart that names no place is not a valid move', () {
      final json = mapped().toJson()..['counterpartOf'] = {'edition': 'x'};

      expect(
        () => HistoryEvent.fromJson(json, decodeTextPosition),
        throwsFormatException,
      );
    });
  });

  group('in the player', () {
    late LocalFiles downloads;
    late MediumSpy store;
    late Playback playback;

    setUp(() async {
      downloads = LocalFiles();
      store = MediumSpy();
      playback = Playback(
        downloads: downloads,
        engine: TestEngine(),
        store: store,
      );
      await playback.bind(account(), [title]);
      await playback.open(title, recording, autoplay: false);
      await playback.seekEdition(30000);
      await playback.flush();
      store.listening.clear();
    });
    tearDown(() async {
      await playback.close();
      downloads.dispose();
    });

    test('Go to a reading place plays from its landing, as a listening '
        'move from the place that played before', () async {
      final before = playback.position!;

      expect(
        await playback.goToLanding(landing, HistoryAction.historyRestore),
        isTrue,
      );
      await playback.flush();

      expect(playback.position!.sourceKey, second.key);
      expect(playback.position!.milliseconds, 20000);
      final move = playback.history.first;
      expect(move.kind, HistoryAction.historyRestore);
      expect(encodePosition(move.before), encodePosition(before));
      expect(encodePosition(move.after), encodePosition(playback.position!));
      expect(move.counterpartOf, same(readingPlace));
      expect(move.matchedBy, MatchedBy.chapters);
      expect(playback.undoAction, same(move));
      playback.checkInvariants();
    });

    test(
      'Undo after a mapped jump returns to the exact place before it',
      () async {
        final before = playback.position!;
        await playback.goToLanding(landing, HistoryAction.historyRestore);

        await playback.undoSeek();
        await playback.flush();

        expect(encodePosition(playback.position!), encodePosition(before));
      },
    );

    test('a mapped jump saves its move with the new place in one change '
        'set, and writes no reading record', () async {
      await playback.goToLanding(landing, HistoryAction.historyRestore);
      await playback.flush();

      final move = playback.history.first;
      final saves = [
        for (final changes in store.listening)
          if (changes.history.isNotEmpty) changes,
      ];
      expect(saves.first.history.keys, [move.id]);
      expect(saves.first.resumes[recording.id]!.last['milliseconds'], 20000);
      expect(store.reading, isEmpty);
    });

    test('Go to a reading bookmark records a bookmark restore and copies no '
        'bookmark', () async {
      await playback.goToLanding(landing, HistoryAction.bookmarkRestore);
      await playback.flush();

      expect(playback.history.first.kind, HistoryAction.bookmarkRestore);
      expect(playback.bookmarks, isEmpty);
    });

    test('a landing in an edition that is not open moves nothing', () async {
      final before = playback.position!;
      final elsewhere = AudioLanding(
        readingPlace,
        const AudioPosition(
          editionId: 'other recording',
          sourceKey: 'two:m2',
          revision: 'r2',
          milliseconds: 20000,
        ),
      );

      expect(
        await playback.goToLanding(elsewhere, HistoryAction.historyRestore),
        isFalse,
      );
      await playback.flush();

      expect(encodePosition(playback.position!), encodePosition(before));
      expect(store.listening.where((save) => save.history.isNotEmpty), isEmpty);
    });
  });
}
