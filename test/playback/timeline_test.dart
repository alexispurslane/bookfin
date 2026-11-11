import 'package:bookfin/catalog/glass.dart';
import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/foundation/theme.dart';
import 'package:bookfin/foundation/time.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:bookfin/playback/screen.dart';
import 'package:bookfin/playback/timeline.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'playback_test.dart'
    show
        LocalFiles,
        TestEngine,
        MemoryResume,
        account,
        title,
        recording,
        first,
        second;

const otherFile = SourceFile(
  itemId: 'three',
  displayName: 'Only part',
  mediaSourceId: 'm3',
  revision: 'r3',
  durationMs: 120000,
  container: 'wav',
  sizeBytes: 42,
  chapters: [],
);
const otherRecording = Edition(
  id: 'other',
  kind: EditionKind.audio,
  label: 'Reader',
  files: [otherFile],
  memberIds: ['three:m3'],
);
const other = Book(
  id: 'other-book',
  title: 'A second story',
  author: 'B. Writer',
  editions: [otherRecording],
);

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
    // Listen to the other book first, then to this one.
    await playback.open(other, otherRecording, autoplay: false);
    await playback.jump(forward: true);
    await playback.open(title, recording, autoplay: false);
    await playback.jump(forward: true);
    await playback.seekEdition(75000);
    await playback.addBookmark();
    await playback.flush();
    playback.dismissUndo();
  });
  tearDown(() async {
    await playback.close();
    downloads.dispose();
  });

  Future<void> showPlayer(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: bookfinTheme(Brightness.dark),
        home: Scaffold(body: PlayerView(playback: playback)),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> showTimeline(WidgetTester tester) async {
    await showPlayer(tester);
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
  }

  Finder inTimeline(Finder finder) =>
      find.descendant(of: find.byType(HistoryTimeline), matching: finder);

  testWidgets('History in the tool row opens a glass timeline', (tester) async {
    await showTimeline(tester);
    expect(
      find.ancestor(
        of: find.byType(HistoryTimeline),
        matching: find.byType(CoverGlass),
      ),
      findsOneWidget,
    );
    expect(inTimeline(find.text('Today')), findsOneWidget);
  });

  testWidgets('the player timeline shows only this book, newest first', (
    tester,
  ) async {
    await showTimeline(tester);
    final jump = inTimeline(find.text('Ahead 30 s'));
    final bookmark = inTimeline(find.text('Bookmark'));
    expect(jump, findsOneWidget);
    expect(bookmark, findsOneWidget);
    expect(
      tester.getTopLeft(bookmark).dy,
      lessThan(tester.getTopLeft(jump).dy),
    );
    expect(inTimeline(find.textContaining('A second story')), findsNothing);
  });

  testWidgets('each time of day fits on one line, so entries stay dense', (
    tester,
  ) async {
    await showTimeline(tester);
    final line = tester.getSize(inTimeline(find.text('Today'))).height;
    final times = inTimeline(find.textContaining(RegExp(r'^\d{1,2}:\d\d')));
    expect(times, findsWidgets);
    for (final time in times.evaluate()) {
      expect(tester.getSize(find.byWidget(time.widget)).height, line);
    }
  });

  testWidgets('Before on an action returns to where it began', (tester) async {
    await showTimeline(tester);
    await tester.tap(inTimeline(find.text('Ahead 30 s')));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(inTimeline(find.text('BEFORE')));
      await playback.flush();
    });
    await tester.pumpAndSettle();
    expect(playback.editionMilliseconds, 0);
  });

  testWidgets('After on an action returns to where it ended', (tester) async {
    await showTimeline(tester);
    await tester.tap(inTimeline(find.text('Ahead 30 s')));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(inTimeline(find.text('AFTER')));
      await playback.flush();
    });
    await tester.pumpAndSettle();
    expect(playback.editionMilliseconds, 30000);
    expect(find.byType(HistoryTimeline), findsNothing);
  });

  testWidgets('a tap on a bookmark offers going to it', (tester) async {
    await tester.runAsync(() => playback.seekEdition(10000));
    await showTimeline(tester);
    await tester.tap(inTimeline(find.text('Bookmark')));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(inTimeline(find.text('GO TO')));
      await playback.flush();
    });
    await tester.pumpAndSettle();
    expect(playback.editionMilliseconds, 75000);
    // Going somewhere closes the timeline, so the player shows the new place.
    expect(find.byType(HistoryTimeline), findsNothing);
  });

  testWidgets('an open timeline measures its places again when the library '
      'changes the length of an earlier file', (tester) async {
    await showTimeline(tester);
    expect(inTimeline(find.text('1:15')), findsWidgets);
    // A refresh of the same account finds that part one runs ten seconds
    // longer, so the bookmark in part two is ten seconds later in the book.
    final longer = Edition(
      id: recording.id,
      kind: recording.kind,
      label: recording.label,
      files: [
        SourceFile(
          itemId: first.itemId,
          displayName: first.displayName,
          mediaSourceId: first.mediaSourceId,
          revision: first.revision,
          durationMs: first.durationMs! + 10000,
          container: first.container,
          sizeBytes: first.sizeBytes,
          chapters: first.chapters,
        ),
        second,
      ],
      memberIds: recording.memberIds,
    );
    final refreshed = Book(
      id: title.id,
      title: title.title,
      author: title.author,
      editions: [longer],
    );
    await tester.runAsync(() => playback.bind(account(), [refreshed, other]));
    await tester.pump();
    expect(inTimeline(find.text('1:15')), findsNothing);
    expect(inTimeline(find.text('1:25')), findsWidgets);
  });

  testWidgets('a playing tick redraws no entry of an open timeline', (
    tester,
  ) async {
    await showTimeline(tester);
    void tick() =>
        engine.emit(engine.index, engine.milliseconds + 200, playing: true);
    // The first report starts playing, which records an action.
    tick();
    await tester.pumpAndSettle();
    final rebuilt = <Widget>[];
    debugOnRebuildDirtyWidget = (element, _) => rebuilt.add(element.widget);
    try {
      tick();
      await tester.pump();
    } finally {
      debugOnRebuildDirtyWidget = null;
    }
    expect(rebuilt.whereType<Slider>(), isNotEmpty, reason: 'the tick arrived');
    expect(
      rebuilt.whereType<ValueListenableBuilder<List<TimelineEntry>>>(),
      isEmpty,
    );
  });

  testWidgets('an action can be deleted from the timeline', (tester) async {
    final semantics = tester.ensureSemantics();
    await showTimeline(tester);
    // The delete saves in real time, so it starts outside the fake clock,
    // from the row's Delete action for a screen reader.
    await tester.runAsync(
      () async => tester.semantics.customAction(
        find.semantics.byLabel(RegExp('Jumped ahead 30 s')),
        const CustomSemanticsAction(label: 'Delete'),
      ),
    );
    semantics.dispose();
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await Future<void>.delayed(Duration.zero);
      await playback.flush();
    });
    await tester.pumpAndSettle();
    expect(inTimeline(find.text('Ahead 30 s')), findsNothing);
    expect(
      playback.history.where(
        (event) =>
            event.kind == HistoryAction.jump &&
            event.after.editionId == recording.id,
      ),
      isEmpty,
    );
  });

  testWidgets('Cancel in the delete confirmation keeps the action', (
    tester,
  ) async {
    await showTimeline(tester);
    await tester.fling(
      inTimeline(find.text('Ahead 30 s')),
      const Offset(-400, 0),
      1000,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(inTimeline(find.text('Ahead 30 s')), findsOneWidget);
    expect(
      playback.history.where((event) => event.kind == HistoryAction.jump),
      hasLength(2),
    );
  });

  testWidgets('Name on a bookmark saves the title that the listener types', (
    tester,
  ) async {
    await showTimeline(tester);
    await tester.tap(inTimeline(find.text('Bookmark')));
    await tester.pumpAndSettle();
    // The save runs in real time, so it starts outside the fake clock.
    await tester.runAsync(() => tester.tap(inTimeline(find.byTooltip('Name'))));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Title (optional)'),
      'The storm',
    );
    await tester.runAsync(() async {
      await tester.tap(find.text('Save bookmark'));
      await Future<void>.delayed(Duration.zero);
      await playback.flush();
    });
    await tester.pumpAndSettle();
    expect(playback.bookmarks.single.title, 'The storm');
    // Naming stays in the timeline, which shows the new name.
    expect(inTimeline(find.text('The storm')), findsOneWidget);
  });

  testWidgets('without a book the timeline shows every book by name', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: bookfinTheme(Brightness.light),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => openHistory(context, playback),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(inTimeline(find.textContaining('A second story')), findsWidgets);
    expect(inTimeline(find.textContaining('The journey')), findsWidgets);
  });

  group('the timeline alone', () {
    final at = DateTime.now().toUtc();
    AudioPosition placeAt(int milliseconds) => AudioPosition(
      editionId: recording.id,
      sourceKey: recording.files.first.key,
      revision: recording.files.first.revision,
      milliseconds: milliseconds,
    );
    final jump = HistoryEvent(
      id: 'jump',
      at: at.subtract(const Duration(minutes: 2)),
      kind: HistoryAction.jump,
      before: placeAt(0),
      after: placeAt(30000),
      bookTitle: title.title,
      editionLabel: recording.label,
    );
    final mark = Bookmark(
      id: 'mark',
      position: placeAt(75000),
      createdAt: at.subtract(const Duration(minutes: 1)),
      bookTitle: title.title,
      editionLabel: recording.label,
    );
    late ValueNotifier<List<TimelineEntry>> entries;
    late List<Object> reports;
    setUp(() {
      entries = ValueNotifier([BookmarkEntry(mark), ActionEntry(jump)]);
      reports = [];
    });
    tearDown(() => entries.dispose());

    // The timeline gets no Playback, so it can only draw its entries and
    // report what the listener chose.
    Future<void> showTimeline(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: bookfinTheme(Brightness.light),
          home: Scaffold(
            body: HistoryTimeline(
              entries: entries,
              describe: (place) => switch (place) {
                AudioPosition(:final milliseconds) => (
                  short: audioTime(milliseconds),
                  chapter: null,
                  quote: null,
                  along: AlongAudio(milliseconds),
                ),
                TextPosition() => throw StateError('No reading place here.'),
              },
              onGoBefore: (event) => reports.add(('back', event)),
              onGoTo: (entry) => reports.add(('go', entry)),
              onRename: (bookmark) => reports.add(('rename', bookmark)),
              onDelete: (entry) => reports.add(('delete', entry)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> choose(WidgetTester tester, String row, Finder choice) async {
      await tester.tap(find.text(row));
      await tester.pumpAndSettle();
      await tester.tap(choice);
      await tester.pumpAndSettle();
    }

    testWidgets('Before reports the action whose start to return to', (
      tester,
    ) async {
      await showTimeline(tester);
      await choose(tester, 'Ahead 30 s', find.text('BEFORE'));
      expect(reports, [('back', jump)]);
    });

    testWidgets('After on an action reports that action', (tester) async {
      await showTimeline(tester);
      await choose(tester, 'Ahead 30 s', find.text('AFTER'));
      expect(reports, hasLength(1));
      final (kind, entry) = reports.single as (String, ActionEntry);
      expect((kind, entry.event), ('go', jump));
    });

    testWidgets('Go to on a bookmark reports that bookmark', (tester) async {
      await showTimeline(tester);
      await choose(tester, 'Bookmark', find.text('GO TO'));
      expect(reports, hasLength(1));
      final (kind, entry) = reports.single as (String, BookmarkEntry);
      expect((kind, entry.bookmark), ('go', mark));
    });

    testWidgets('Name reports the bookmark and opens no editor itself', (
      tester,
    ) async {
      await showTimeline(tester);
      await choose(tester, 'Bookmark', find.byTooltip('Name'));
      expect(reports, [('rename', mark)]);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('Delete reports the entry and asks nothing itself', (
      tester,
    ) async {
      await showTimeline(tester);
      await tester.fling(
        find.text('Ahead 30 s'),
        const Offset(-400, 0),
        1000,
      );
      await tester.pumpAndSettle();
      expect(reports, hasLength(1));
      final (kind, entry) = reports.single as (String, ActionEntry);
      expect((kind, entry.event), ('delete', jump));
      expect(find.text('Delete history action?'), findsNothing);
    });

    testWidgets('shows a new entry when its entries change', (tester) async {
      await showTimeline(tester);
      entries.value = [
        BookmarkEntry(
          Bookmark(
            id: 'storm',
            position: placeAt(5000),
            createdAt: at,
            bookTitle: title.title,
            editionLabel: recording.label,
            title: 'The storm',
          ),
        ),
        ...entries.value,
      ];
      await tester.pump();
      expect(find.text('The storm'), findsOneWidget);
    });
  });

  testWidgets('the timeline names the moves of reading', (tester) async {
    AudioPosition at(int milliseconds) => AudioPosition(
      editionId: recording.id,
      sourceKey: first.key,
      revision: first.revision,
      milliseconds: milliseconds,
    );
    final kinds = [
      HistoryAction.link,
      HistoryAction.search,
      HistoryAction.open,
      HistoryAction.close,
    ];
    await tester.pumpWidget(
      MaterialApp(
        theme: bookfinTheme(Brightness.light),
        home: Scaffold(
          body: HistoryTimeline(
            entries: ValueNotifier([
              for (final (minute, kind) in kinds.indexed)
                ActionEntry(
                  HistoryEvent(
                    id: kind.name,
                    at: DateTime(2026, 11, 9, 20, minute),
                    kind: kind,
                    before: at(0),
                    after: at(60000),
                    bookTitle: title.title,
                    editionLabel: recording.label,
                  ),
                ),
            ]),
            describe: (place) =>
                (short: '', chapter: null, quote: null, along: null),
            onGoBefore: (_) {},
            onGoTo: (_) {},
            onRename: (_) {},
            onDelete: (_) {},
          ),
        ),
      ),
    );

    for (final label in [
      'From link',
      'From search',
      'Opened',
      'Closed',
    ]) {
      expect(find.text(label, findRichText: true), findsOneWidget);
    }
  });
}
