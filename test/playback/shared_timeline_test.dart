import 'dart:convert';

import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/foundation/theme.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:bookfin/playback/screen.dart';
import 'package:bookfin/playback/timeline.dart';
import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/epub/publication.dart';
import 'package:bookfin/reader/scope.dart';
import 'package:bookfin/reader/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../reader/publication_test.dart' show epub;
import '../reader/session_test.dart' show edition, source;
import 'playback_test.dart'
    show LocalFiles, TestEngine, MemoryResume, account, recording;

// One History timeline for both media (docs/plans/reading-history.md,
// decision 1, design A): a book with an audiobook and an ebook lists its
// listening and reading entries together, newest first, with a glyph for
// each entry's medium. Go to opens the player or the reader at the place.

/// A book with an audio edition and an EPUB edition.
const both = Book(
  id: 'work',
  title: 'River',
  author: 'Writer',
  editions: [recording, edition],
);

/// The EPUB of the book. Each new archive has a new time stamp, so the
/// reader and the saved places share this one.
final publication = Publication.admit(epub());

/// A saved place in the EPUB edition whose quote is [quote].
TextPosition reading(String quote) => TextPosition(
  editionId: edition.id,
  sourceKey: source.key,
  revision: source.revision,
  anchor: jsonEncode(
    EpubDocument(publication).save(
      EpubAddress(
        ReadingLocation('epubcfi(/6/2!/4/2/1:0)', 'OPS/one.xhtml', quote),
      ),
    ),
  ),
);

void main() {
  late LocalFiles downloads;
  late Playback playback;
  late MemoryResume readingStore;
  late ReaderSession reader;
  late DateTime jumped;

  final searched = HistoryEvent(
    id: 'search',
    at: DateTime.now().toUtc().add(const Duration(minutes: 1)),
    kind: HistoryAction.search,
    before: reading('A river follows the road.'),
    after: reading('The far shore at last.'),
    bookTitle: both.title,
    editionLabel: edition.label,
  );
  final chapter = HistoryEvent(
    id: 'chapter',
    at: DateTime.now().toUtc().subtract(const Duration(minutes: 30)),
    kind: HistoryAction.chapter,
    before: reading('A river follows the road.'),
    after: reading('Where the road ends.'),
    bookTitle: both.title,
    editionLabel: edition.label,
  );
  final mark = Bookmark(
    id: 'mark',
    position: reading('The far shore at last.'),
    createdAt: DateTime.now().toUtc().subtract(const Duration(minutes: 20)),
    bookTitle: both.title,
    editionLabel: edition.label,
  );

  setUp(() async {
    downloads = LocalFiles()..files[source.key] = Uri.file('/verified.epub');
    playback = Playback(
      downloads: downloads,
      engine: TestEngine(),
      store: MemoryResume(),
    );
    await playback.bind(account(), [both]);
    await playback.open(both, recording, autoplay: false);
    await playback.jump(forward: true);
    jumped = playback.history.first.at;
    await playback.flush();
    playback.dismissUndo();
    readingStore = MemoryResume()
      ..values[account().scope.key] = {
        'version': 1,
        'resumes': <dynamic>[],
        'bookmarks': [mark.toJson()],
        'history': [searched.toJson(), chapter.toJson()],
      };
    reader = ReaderSession(
      downloads: downloads,
      store: readingStore,
      load: (_) async => publication,
    );
    await reader.bind(account(), [both]);
  });
  tearDown(() async {
    // Each test that saves waits for the saved records, so the session
    // closes with nothing pending. A flush here would wait on the test
    // clock, which no longer runs.
    reader.dispose();
    await playback.close();
    downloads.dispose();
  });

  /// Pushes a stand-in for the reader screen, so a test sees that the
  /// timeline asked for the reader.
  void showReader(BuildContext context) => Navigator.of(
    context,
  ).push<void>(MaterialPageRoute(builder: (_) => const Text('Reader screen')));

  /// Shows [home] in the app, under the reader of the test.
  Future<void> show(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: bookfinTheme(Brightness.light),
        home: ReaderScope(
          reader: reader,
          show: showReader,
          child: Scaffold(body: home),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Opens the History of the book from a page outside the player, such as
  /// the book page.
  Future<void> showBookHistory(WidgetTester tester) async {
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
  }

  /// Opens the History from the tool row of the player.
  Future<void> showPlayerHistory(WidgetTester tester) async {
    await show(tester, PlayerView(playback: playback));
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
  }

  /// The glyph of a medium, which assistive technology reads as [medium].
  Finder glyph(String medium) => find.byWidgetPredicate(
    (widget) => widget is Icon && widget.semanticLabel == medium,
  );

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

  Finder inTimeline(Finder finder) =>
      find.descendant(of: find.byType(HistoryTimeline), matching: finder);

  /// Taps the row labeled [row], then its choice [choice], and lets the
  /// work that the choice starts run in real time.
  Future<void> choose(WidgetTester tester, String row, String choice) async {
    await tester.tap(inTimeline(find.text(row, findRichText: true)));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(inTimeline(find.text(choice)));
      await Future<void>.delayed(Duration.zero);
      await playback.flush();
      await reader.flush();
    });
    await tester.pumpAndSettle();
  }

  testWidgets('a book\'s timeline lists its listening and reading moves '
      'together, newest first', (tester) async {
    expect(jumped.isAfter(chapter.at) && jumped.isBefore(searched.at), isTrue);
    await showBookHistory(tester);

    final rows = [
      inTimeline(find.text('Went to a search result', findRichText: true)),
      inTimeline(find.text('Jumped ahead 30 s', findRichText: true)),
      inTimeline(find.text('Bookmark', findRichText: true)),
      inTimeline(find.text('Changed chapter', findRichText: true)),
    ];
    for (final row in rows) {
      expect(row, findsOneWidget);
    }
    final tops = [for (final row in rows) tester.getTopLeft(row).dy];
    expect(tops, orderedEquals([...tops]..sort()));
  });

  testWidgets('each entry of a mixed timeline shows a glyph for its medium', (
    tester,
  ) async {
    await showBookHistory(tester);

    expect(inTimeline(glyph('Listening')), findsWidgets);
    expect(inTimeline(glyph('Reading')), findsNWidgets(3));
  });

  testWidgets('a reading entry outside the open book reads as the first '
      'words of its quote', (tester) async {
    await showBookHistory(tester);

    expect(inTimeline(find.text('“The far shore at last.”')), findsWidgets);
    await tester.tap(
      inTimeline(find.text('Changed chapter', findRichText: true)),
    );
    await tester.pumpAndSettle();
    expect(
      inTimeline(find.text('Go back to “A river follows the road.”')),
      findsOneWidget,
    );
    expect(
      inTimeline(find.text('Go to “Where the road ends.”')),
      findsOneWidget,
    );
  });

  testWidgets('Go to on a reading entry from the player opens the reader '
      'there', (tester) async {
    await showPlayerHistory(tester);

    await choose(
      tester,
      'Went to a search result',
      'Go to “The far shore at last.”',
    );

    expect(find.byType(HistoryTimeline), findsNothing);
    expect(find.text('Reader screen'), findsOneWidget);
    await settle(tester, () => reader.document != null);
    expect(reader.edition?.id, edition.id);
    expect(reader.initialAddress?.quote, 'The far shore at last.');
  });

  testWidgets('Go back on a reading entry opens the reader where the move '
      'began', (tester) async {
    await showPlayerHistory(tester);

    await choose(
      tester,
      'Went to a search result',
      'Go back to “A river follows the road.”',
    );

    expect(find.text('Reader screen'), findsOneWidget);
    await settle(tester, () => reader.document != null);
    expect(reader.initialAddress?.quote, 'A river follows the road.');
  });

  testWidgets('Go to on a listening entry from outside the player opens the '
      'player there', (tester) async {
    await tester.runAsync(() => playback.seekEdition(5000));
    await showBookHistory(tester);

    await choose(tester, 'Jumped ahead 30 s', 'Go to 00:30');

    expect(playback.editionMilliseconds, 30000);
    expect(find.byType(PlayerView), findsOneWidget);
    expect(find.text('Reader screen'), findsNothing);
  });

  testWidgets('Go to on a listening entry in the player stays in the player', (
    tester,
  ) async {
    await tester.runAsync(() => playback.seekEdition(5000));
    await showPlayerHistory(tester);

    await choose(tester, 'Jumped ahead 30 s', 'Go to 00:30');

    expect(playback.editionMilliseconds, 30000);
    expect(find.byType(PlayerView), findsOneWidget);
  });

  testWidgets('renaming a reading bookmark from the timeline keeps its new '
      'title', (tester) async {
    await showBookHistory(tester);

    await tester.tap(inTimeline(find.text('Bookmark', findRichText: true)));
    await tester.pumpAndSettle();
    await tester.tap(inTimeline(find.text('Name')));
    await tester.pumpAndSettle();
    expect(find.text('Edit bookmark'), findsOneWidget);
    expect(find.text('“The far shore at last.”'), findsWidgets);
    await tester.enterText(
      find.widgetWithText(TextField, 'Title (optional)'),
      'The far shore',
    );
    await tester.tap(find.text('Save bookmark'));
    await tester.pumpAndSettle();
    Map<dynamic, dynamic> saved() =>
        (readingStore.values[account().scope.key]!['bookmarks'] as List).single
            as Map;
    await settle(tester, () => saved()['title'] == 'The far shore');
    await tester.pumpAndSettle();

    expect(
      inTimeline(find.text('The far shore', findRichText: true)),
      findsOneWidget,
    );
    expect(saved()['bookTitle'], both.title);
  });

  testWidgets('Delete on a reading move asks first, and Cancel keeps it', (
    tester,
  ) async {
    await showBookHistory(tester);

    await tester.tap(
      inTimeline(find.text('Changed chapter', findRichText: true)),
    );
    await tester.pumpAndSettle();
    await tester.tap(inTimeline(find.byTooltip('Delete')));
    await tester.pumpAndSettle();
    expect(find.text('Delete history action?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(
      inTimeline(find.text('Changed chapter', findRichText: true)),
      findsOneWidget,
    );
    expect(reader.history.map((event) => event.id), contains('chapter'));
  });

  testWidgets('Delete on a reading move removes it from the saved records and '
      'keeps the others', (tester) async {
    await showBookHistory(tester);

    await tester.tap(
      inTimeline(find.text('Changed chapter', findRichText: true)),
    );
    await tester.pumpAndSettle();
    await tester.tap(inTimeline(find.byTooltip('Delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    await settle(
      tester,
      () =>
          (readingStore.values[account().scope.key]!['history'] as List)
              .length ==
          1,
    );
    await tester.pumpAndSettle();

    expect(
      inTimeline(find.text('Changed chapter', findRichText: true)),
      findsNothing,
    );
    final saved = readingStore.values[account().scope.key]!['history'] as List;
    expect([for (final event in saved) (event as Map)['id']], ['search']);
  });

  test('a listening place reads as its time in the edition, with its '
      'chapter', () {
    // 75 seconds into the edition is 15 seconds into part two, whose
    // chapter "Return" starts at 10 seconds.
    final place = AudioPosition(
      editionId: recording.id,
      sourceKey: recording.files[1].key,
      revision: recording.files[1].revision,
      milliseconds: 15000,
    );

    final words = playback.describe(place);

    expect(words.short, '01:15');
    expect(words.chapter, 'Return');
    expect(words.quote, isNull);
    expect(
      words.along,
      isA<AlongAudio>().having((at) => at.milliseconds, 'ms', 75000),
    );
  });

  group('the timeline alone', () {
    final at = DateTime.now().toUtc();
    TextPosition page(int number) => TextPosition(
      editionId: edition.id,
      sourceKey: source.key,
      revision: source.revision,
      anchor: '$number',
    );
    PlaceWords words(TextPosition place) => switch (int.parse(place.anchor)) {
      final number when number > 1000 => (
        short: '${number - 1000}%',
        chapter: null,
        quote: null,
        along: AlongText(fraction: (number - 1000) / 100),
      ),
      final number when number > 500 => (
        short: '“Somewhere”',
        chapter: null,
        quote: 'Somewhere far away',
        along: null,
      ),
      final number => (
        short: 'p. $number',
        chapter: 'Chapter 4',
        quote: 'It was a bright cold day in April.',
        along: AlongText(page: number, fraction: number / 400),
      ),
    };
    HistoryEvent<TextPosition> seek(int from, int to) => HistoryEvent(
      id: '$from-$to',
      at: at,
      kind: HistoryAction.seek,
      before: page(from),
      after: page(to),
      bookTitle: both.title,
      editionLabel: edition.label,
    );

    Future<void> showAlone(
      WidgetTester tester,
      List<TimelineEntry> entries,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: bookfinTheme(Brightness.light),
          home: Scaffold(
            body: HistoryTimeline(
              entries: ValueNotifier(entries),
              describe: (place) => switch (place) {
                final TextPosition place => words(place),
                final AudioPosition place => (
                  short: '00:${place.milliseconds ~/ 1000}',
                  chapter: 'Arrival',
                  quote: null,
                  along: AlongAudio(place.milliseconds),
                ),
              },
              onGoBack: (_) {},
              onGoTo: (_) {},
              onRename: (_) {},
              onDelete: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a reading move says how many pages it went', (tester) async {
      await showAlone(tester, [
        ActionEntry(seek(122, 134)),
        ActionEntry(seek(134, 133)),
      ]);

      expect(
        find.text('Moved ahead 12 pages', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.text('Moved back 1 page', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('before its page numbers are known, a reading move says only '
        'its direction', (tester) async {
      await showAlone(tester, [ActionEntry(seek(1037, 1012))]);

      expect(find.text('Moved back', findRichText: true), findsOneWidget);
      expect(find.text('12%'), findsOneWidget);
    });

    testWidgets('a reading move that the open book cannot place reads as its '
        'verb alone', (tester) async {
      await showAlone(tester, [ActionEntry(seek(600, 700))]);

      expect(find.text('Moved', findRichText: true), findsOneWidget);
    });

    testWidgets('a reading entry shows its page, chapter and quote', (
      tester,
    ) async {
      await showAlone(tester, [ActionEntry(seek(122, 134))]);
      expect(find.text('p. 134'), findsOneWidget);
      expect(find.textContaining('Chapter 4'), findsNothing);

      await tester.tap(find.text('Moved ahead 12 pages', findRichText: true));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Chapter 4', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'It was a bright cold day in April.',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(find.text('Go back to p. 122'), findsOneWidget);
      expect(find.text('Go to p. 134'), findsOneWidget);
    });

    testWidgets('an open listening entry shows its chapter', (tester) async {
      final place = AudioPosition(
        editionId: recording.id,
        sourceKey: recording.files.first.key,
        revision: recording.files.first.revision,
        milliseconds: 45000,
      );
      await showAlone(tester, [
        ActionEntry(
          HistoryEvent(
            id: 'pause',
            at: at,
            kind: HistoryAction.pause,
            before: place,
            after: place,
            bookTitle: both.title,
            editionLabel: recording.label,
          ),
        ),
      ]);

      await tester.tap(find.text('Paused', findRichText: true));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Arrival', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('a timeline of one medium marks no medium, as before', (
      tester,
    ) async {
      await showAlone(tester, [ActionEntry(seek(122, 134))]);

      expect(glyph('Reading'), findsNothing);
    });
  });
}
