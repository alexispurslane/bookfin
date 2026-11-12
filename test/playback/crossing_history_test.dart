import 'dart:convert';
import 'dart:typed_data';

import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/crossings/crossings.dart';
import 'package:bookfin/crossings/scope.dart';
import 'package:bookfin/foundation/theme.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:bookfin/playback/screen.dart';
import 'package:bookfin/playback/timeline.dart';
import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/epub/publication.dart';
import 'package:bookfin/reader/scope.dart';
import 'package:bookfin/reader/session.dart';
import 'package:bookfin/reader/text_outline.dart';
import 'package:bookfin/speech/book_words.dart';
import 'package:bookfin/speech/heard_windows.dart';
import 'package:bookfin/speech/words.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../crossings/crossings_test.dart' show MemoryOutlines;
import '../crossings/speech_landings_test.dart' show readsOf;
import '../speech/heard_windows_test.dart'
    show FakeHearing, MemoryStore, inline;
import '../speech/place_test.dart' show zipfBook;
import '../reader/publication_test.dart' show epub;
import '../reader/session_test.dart' show edition, source;
import 'mapped_moves_test.dart' show MediumSpy;
import 'playback_test.dart'
    show LocalFiles, TestEngine, MemoryResume, account, recording;

// The History sheet routes each choice to the owner of the open edition
// (docs/plans/cross-edition-places.md, "One routing rule"). In the player,
// Go to on a reading place plays from its landing in the audiobook, as a
// listening move with Undo, and writes no reading record. When no landing
// exists, the tile says why, and Go to opens the reader as before.

/// A book with an audio edition and an EPUB edition.
const both = Book(
  id: 'work',
  title: 'River',
  author: 'Writer',
  editions: [recording, edition],
);

/// The ebook's outline: one section of 1500 characters with the chapters
/// of [recording], each at 10 characters a second of its recording.
final matching = TextOutline(
  parts: const [(path: 'OPS/one.xhtml', characters: 1500)],
  entries: const [
    (title: 'Opening', depth: 0, start: 0),
    (title: 'Arrival', depth: 0, start: 400),
    (title: 'Return', depth: 0, start: 700),
  ],
);

/// An outline whose chapters match none of [recording]'s.
final unmatching = TextOutline(
  parts: const [(path: 'OPS/one.xhtml', characters: 1500)],
  entries: const [
    (title: 'Economy', depth: 0, start: 0),
    (title: 'Reading', depth: 0, start: 750),
  ],
);

/// An outline whose chapters pair with [recording]'s by their titles, but
/// read Arrival nearly twice as fast as Return, so that the starts of the
/// pairs do not place each other: Arrival, placed from Opening and Return,
/// lands 1543 characters, more than two pages, from its start.
final misaligned = TextOutline(
  parts: const [(path: 'OPS/one.xhtml', characters: 18600)],
  entries: const [
    (title: 'Opening', depth: 0, start: 0),
    (title: 'Arrival', depth: 0, start: 7600),
    (title: 'Return', depth: 0, start: 10600),
  ],
);

/// A reading place [progress] of the way through the ebook's one section,
/// whose quote is [quote].
TextPosition reading(double progress, String quote) => TextPosition(
  editionId: edition.id,
  sourceKey: source.key,
  revision: source.revision,
  anchor: jsonEncode(
    EpubDocument(publication).save(
      EpubAddress(
        ReadingLocation(
          'epubcfi(/6/2!/4/2/1:0)',
          'OPS/one.xhtml',
          quote,
          progress: progress,
        ),
      ),
    ),
  ),
);

/// The EPUB of the book, which the reader opens when Go to opens it.
final publication = Publication.admit(epub());

void main() {
  late LocalFiles downloads;
  late MediumSpy listeningStore;
  late Playback playback;
  late MemoryResume readingStore;
  late ReaderSession reader;
  late Crossings crossings;
  late TextOutline outline;
  late int measured;

  // 900 characters: a quarter of the way through Return, which plays from
  // 70 s to 150 s, so 90 s into the edition.
  final searched = HistoryEvent(
    id: 'search',
    at: DateTime.now().toUtc().add(const Duration(minutes: 1)),
    kind: HistoryAction.search,
    before: reading(.2, 'A river follows the road.'),
    after: reading(.6, 'The far shore at last.'),
    bookTitle: both.title,
    editionLabel: edition.label,
  );
  final mark = Bookmark(
    id: 'mark',
    position: reading(.6, 'The far shore at last.'),
    createdAt: DateTime.now().toUtc().subtract(const Duration(minutes: 20)),
    bookTitle: both.title,
    editionLabel: edition.label,
  );

  setUp(() async {
    outline = matching;
    measured = 0;
    downloads = LocalFiles()..files[source.key] = Uri.file('/verified.epub');
    listeningStore = MediumSpy();
    playback = Playback(
      downloads: downloads,
      engine: TestEngine(),
      store: listeningStore,
    );
    await playback.bind(account(), [both]);
    await playback.open(both, recording, autoplay: false);
    await playback.seekEdition(5000);
    await playback.flush();
    playback.dismissUndo();
    readingStore = MemoryResume()
      ..values[account().scope.key] = {
        'version': 1,
        'resumes': <dynamic>[],
        'bookmarks': [mark.toJson()],
        'history': [searched.toJson()],
      };
    reader = ReaderSession(
      downloads: downloads,
      store: readingStore,
      load: (_) async => publication,
    );
    await reader.bind(account(), [both]);
    crossings = Crossings(
      store: MemoryOutlines(),
      measure: (_) async {
        measured++;
        return outline;
      },
      hop: <M, R>(work, input) async => work(input),
    );
  });
  tearDown(() async {
    crossings.dispose();
    reader.dispose();
    await playback.close();
    downloads.dispose();
  });

  /// Shows [home] in the app, under the reader and the crossings of the
  /// test. The reader screen is a stand-in, so a test sees that the
  /// timeline asked for it.
  Future<void> show(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: bookfinTheme(Brightness.light),
        home: CrossingsScope(
          crossings: crossings,
          child: ReaderScope(
            reader: reader,
            show: (context) => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => const Text('Reader screen')),
            ),
            child: Scaffold(body: home),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> showPlayerHistory(WidgetTester tester) async {
    await show(tester, PlayerView(playback: playback));
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
  }

  Finder inTimeline(Finder finder) =>
      find.descendant(of: find.byType(HistoryTimeline), matching: finder);

  /// The tile of an open entry whose role word is [role], such as AFTER.
  Finder tile(String role) => find
      .ancestor(of: inTimeline(find.text(role)), matching: find.byType(InkWell))
      .first;

  Finder inTile(String role, Finder finder) =>
      find.descendant(of: tile(role), matching: finder);

  /// Opens the row labeled [row], and lets the landings of its places
  /// arrive.
  Future<void> open(WidgetTester tester, String row) async {
    await tester.tap(inTimeline(find.text(row, findRichText: true)));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }

  /// Lets real time pass and pumps frames until [done] holds, for up to
  /// five seconds, while the reader opens a book.
  Future<void> settle(WidgetTester tester, bool Function() done) async {
    for (var tries = 0; tries < 500 && !done(); tries++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(done(), isTrue, reason: 'the work did not end');
  }

  /// Taps the tile [role] and lets the work that it starts run until
  /// [until] holds.
  Future<void> go(
    WidgetTester tester,
    String role, {
    required bool Function() until,
  }) async {
    await tester.runAsync(() => tester.tap(inTimeline(find.text(role))));
    await settle(tester, until);
    await tester.runAsync(() async {
      await playback.flush();
      await reader.flush();
    });
    await tester.pumpAndSettle();
  }

  /// Whether the player recorded a move since the test began.
  bool playerMoved() => playback.history.first.kind != HistoryAction.seek;

  /// Whether the reader opened its book.
  bool opened() => reader.document != null;

  testWidgets('in the player, a reading move names where each end lands in '
      'the audiobook', (tester) async {
    await showPlayerHistory(tester);

    await open(tester, 'From search');

    expect(inTile('BEFORE', find.text('about 0:30')), findsOneWidget);
    expect(inTile('AFTER', find.text('about 1:30')), findsOneWidget);
    expect(inTile('AFTER', find.text('Return')), findsOneWidget);
  });

  testWidgets('the History in the player starts to align the audiobook '
      'with the ebook as it opens', (tester) async {
    await showPlayerHistory(tester);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));

    expect(measured, 1);
    expect(
      crossings.landingNow(searched.after, from: edition, into: recording),
      isA<AudioLanding>(),
    );
  });

  testWidgets('in the player, Go to on a reading place plays from its '
      'landing as a listening move with Undo, and writes no reading '
      'record', (tester) async {
    final records = jsonEncode(readingStore.values);
    await showPlayerHistory(tester);
    await open(tester, 'From search');

    await go(tester, 'AFTER', until: playerMoved);

    expect(find.byType(HistoryTimeline), findsNothing);
    expect(find.text('Reader screen'), findsNothing);
    expect(playback.editionMilliseconds, 90000);
    final moved = playback.history.first;
    expect(moved.kind, HistoryAction.historyRestore);
    expect(moved.counterpartOf, isA<TextPosition>());
    expect(
      (moved.counterpartOf! as TextPosition).anchor,
      searched.after.anchor,
    );
    expect(playback.undoAction, same(moved));
    expect(reader.book, isNull);
    expect(jsonEncode(readingStore.values), records);
    expect(listeningStore.reading, isEmpty);
  });

  testWidgets('in the player, Go to on a reading bookmark plays from its '
      'landing as a bookmark restore', (tester) async {
    final records = jsonEncode(readingStore.values);
    await showPlayerHistory(tester);
    await open(tester, 'Bookmark');

    await go(tester, 'GO TO', until: playerMoved);

    expect(playback.editionMilliseconds, 90000);
    expect(playback.history.first.kind, HistoryAction.bookmarkRestore);
    expect(playback.bookmarks, isEmpty);
    expect(jsonEncode(readingStore.values), records);
  });

  testWidgets('after a mapped jump, the player\'s History names the move by '
      'where it went in the ebook', (tester) async {
    await showPlayerHistory(tester);
    await open(tester, 'From search');
    await go(tester, 'AFTER', until: playerMoved);

    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();

    expect(
      inTimeline(find.text('From ebook', findRichText: true)),
      findsOneWidget,
    );
  });

  testWidgets('in the player, a reading place whose chapters do not match '
      'says why before the tap, and Go to opens the reader there', (
    tester,
  ) async {
    outline = unmatching;
    await showPlayerHistory(tester);
    await open(tester, 'From search');

    expect(
      inTimeline(
        find.text(
          'The chapters of these editions do not match, so this opens the '
          'ebook.',
        ),
      ),
      findsOneWidget,
    );
    expect(
      inTile('AFTER', find.text('“The far shore at last.”')),
      findsOneWidget,
    );

    await go(tester, 'AFTER', until: opened);

    expect(find.text('Reader screen'), findsOneWidget);
    expect(reader.initialAddress?.quote, 'The far shore at last.');
    expect(playback.editionMilliseconds, 5000);
    expect(playback.history.first.counterpartOf, isNull);
  });

  testWidgets('in the player, a reading place whose chapters do not line up '
      'says so before the tap', (tester) async {
    outline = misaligned;
    await showPlayerHistory(tester);
    await open(tester, 'From search');

    expect(
      inTimeline(
        find.text(
          'The chapters of these editions do not line up, so this opens the '
          'ebook.',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('on the book page, which shows no edition, Go to on a reading '
      'place opens the reader as before', (tester) async {
    await show(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => openHistory(context, playback, book: both),
          child: const Text('History of the book'),
        ),
      ),
    );
    await tester.tap(find.text('History of the book'));
    await tester.pumpAndSettle();
    await open(tester, 'From search');

    expect(
      inTile('AFTER', find.text('“The far shore at last.”')),
      findsOneWidget,
    );
    await go(tester, 'AFTER', until: opened);

    expect(find.text('Reader screen'), findsOneWidget);
    expect(playback.editionMilliseconds, 5000);
  });

  group('with speech', () {
    late FakeHearing hearing;

    // Speech hears words that the ebook does not hold, so it refuses, and
    // the landing of matched chapters stays. Each window waits until the
    // test releases it.
    setUp(() {
      hearing = FakeHearing()
        ..gated = true
        ..answer = (_, _) => Heard(
          normalizeWords('quantum zebra xylophone apparatus nebula vortex'),
          const [0, 1000, 2000, 3000, 4000, 5000],
        );
      crossings.dispose();
      crossings = Crossings(
        store: MemoryOutlines(),
        measure: (_) async => outline,
        hop: <M, R>(work, input) async => work(input),
        speech: (
          heard: HeardWindows(
            hear: hearing.call,
            store: MemoryStore(),
            localPath: (file) async => '/media/${file.itemId}.mp3',
            hop: inline,
          ),
          words: (_) async => readsOf(
            BookWords(
              zipfBook(length: 300).words,
              Int32List.fromList([
                for (var word = 0; word < 300; word++) word * 5,
              ]),
              bodyEnd: 300,
            ),
          ),
        ),
      );
    });

    /// Stops the worker of the ebook's words, whose idle timer would still
    /// wait when the test ends. The tear-down disposes a Crossings without
    /// speech.
    void stopSpeech() {
      crossings.dispose();
      crossings = Crossings(
        store: MemoryOutlines(),
        measure: (_) async => outline,
      );
    }

    /// Lets every window that waits, and every later one, be heard.
    Future<void> release(WidgetTester tester) async {
      hearing.gated = false;
      for (final gate in hearing.gates) {
        if (!gate.isCompleted) gate.complete();
      }
    }

    testWidgets('Go to waits in the sheet with a progress state while speech '
        'finds the place, then plays from the landing', (tester) async {
      await showPlayerHistory(tester);
      await open(tester, 'From search');

      await tester.runAsync(() => tester.tap(inTimeline(find.text('AFTER'))));
      await tester.pump();

      expect(find.byType(HistoryTimeline), findsOneWidget);
      expect(inTimeline(find.text('Finding the sentence…')), findsOneWidget);
      expect(inTimeline(find.text('Cancel')), findsOneWidget);
      expect(playerMoved(), isFalse);

      await release(tester);
      await settle(tester, playerMoved);
      await tester.pumpAndSettle();

      expect(find.byType(HistoryTimeline), findsNothing);
      expect(playback.editionMilliseconds, 90000);
      expect(playback.history.first.kind, HistoryAction.historyRestore);
      stopSpeech();
    });

    testWidgets('closing the sheet ends the wait and makes no move', (
      tester,
    ) async {
      await showPlayerHistory(tester);
      await open(tester, 'From search');
      await tester.runAsync(() => tester.tap(inTimeline(find.text('AFTER'))));
      await tester.pump();

      // The system's Back closes the sheet.
      await tester.binding.handlePopRoute();
      for (var frame = 0; frame < 10; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(HistoryTimeline), findsNothing);

      await release(tester);
      await settle(
        tester,
        () =>
            crossings.landingNow(searched.after, from: edition, into: recording)
                is Settled,
      );
      await tester.pumpAndSettle();

      expect(playerMoved(), isFalse);
      expect(playback.editionMilliseconds, 5000);
      stopSpeech();
    });

    testWidgets('Cancel ends the wait and makes no move', (tester) async {
      await showPlayerHistory(tester);
      await open(tester, 'From search');
      await tester.runAsync(() => tester.tap(inTimeline(find.text('AFTER'))));
      await tester.pump();

      await tester.tap(inTimeline(find.text('Cancel')));
      await tester.pump();
      expect(inTimeline(find.text('Finding the sentence…')), findsNothing);

      await release(tester);
      await settle(
        tester,
        () =>
            crossings.landingNow(searched.after, from: edition, into: recording)
                is Settled,
      );
      await tester.pumpAndSettle();

      expect(find.byType(HistoryTimeline), findsOneWidget);
      expect(playerMoved(), isFalse);
      expect(playback.editionMilliseconds, 5000);
      stopSpeech();
    });
  });
}
