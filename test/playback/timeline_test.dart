import 'package:bookfin/catalog/glass.dart';
import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/foundation/theme.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:bookfin/playback/screen.dart';
import 'package:bookfin/playback/timeline.dart';
import 'package:flutter/material.dart';
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
  late Playback playback;
  setUp(() async {
    downloads = LocalFiles()..files[otherFile.key] = Uri.file('/three.wav');
    playback = Playback(
      downloads: downloads,
      engine: TestEngine(),
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

  Future<void> openHistory(WidgetTester tester) async {
    await showPlayer(tester);
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
  }

  Finder inTimeline(Finder finder) =>
      find.descendant(of: find.byType(ListeningTimeline), matching: finder);

  testWidgets('History in the tool row opens a glass timeline', (tester) async {
    await openHistory(tester);
    expect(
      find.ancestor(
        of: find.byType(ListeningTimeline),
        matching: find.byType(CoverGlass),
      ),
      findsOneWidget,
    );
    expect(inTimeline(find.text('Today')), findsOneWidget);
  });

  testWidgets('the player timeline shows only this book, newest first', (
    tester,
  ) async {
    await openHistory(tester);
    final jump = inTimeline(find.text('Jumped ahead 30 s'));
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
    await openHistory(tester);
    final line = tester.getSize(inTimeline(find.text('Today'))).height;
    final times = inTimeline(find.textContaining(RegExp(r'^\d{1,2}:\d\d')));
    expect(times, findsWidgets);
    for (final time in times.evaluate()) {
      expect(tester.getSize(find.byWidget(time.widget)).height, line);
    }
  });

  testWidgets('a tap on an action offers going back to where it began', (
    tester,
  ) async {
    await openHistory(tester);
    await tester.tap(inTimeline(find.text('Jumped ahead 30 s')));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(inTimeline(find.text('Go back to 00:00')));
      await playback.flush();
    });
    await tester.pumpAndSettle();
    expect(playback.editionMilliseconds, 0);
  });

  testWidgets('Go to on an action returns to where it ended', (tester) async {
    await openHistory(tester);
    await tester.tap(inTimeline(find.text('Jumped ahead 30 s')));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(inTimeline(find.text('Go to 00:30')));
      await playback.flush();
    });
    await tester.pumpAndSettle();
    expect(playback.editionMilliseconds, 30000);
    expect(find.byType(ListeningTimeline), findsNothing);
  });

  testWidgets('a tap on a bookmark offers going to it', (tester) async {
    await tester.runAsync(() => playback.seekEdition(10000));
    await openHistory(tester);
    await tester.tap(inTimeline(find.text('Bookmark')));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(inTimeline(find.text('Go to 01:15')));
      await playback.flush();
    });
    await tester.pumpAndSettle();
    expect(playback.editionMilliseconds, 75000);
    // Going somewhere closes the timeline, so the player shows the new place.
    expect(find.byType(ListeningTimeline), findsNothing);
  });

  testWidgets('an open timeline measures its places again when the library '
      'changes the length of an earlier file', (tester) async {
    await openHistory(tester);
    expect(inTimeline(find.text('01:15')), findsWidgets);
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
    expect(inTimeline(find.text('01:15')), findsNothing);
    expect(inTimeline(find.text('01:25')), findsWidgets);
  });

  testWidgets('an action can be deleted from the timeline', (tester) async {
    await openHistory(tester);
    await tester.tap(inTimeline(find.text('Jumped ahead 30 s')));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => tester.tap(inTimeline(find.byTooltip('Delete'))),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await Future<void>.delayed(Duration.zero);
      await playback.flush();
    });
    await tester.pumpAndSettle();
    expect(inTimeline(find.text('Jumped ahead 30 s')), findsNothing);
    expect(
      playback.history.where(
        (event) =>
            event.kind == ListeningAction.jump &&
            event.after.editionId == recording.id,
      ),
      isEmpty,
    );
  });

  testWidgets('Cancel in the delete confirmation keeps the action', (
    tester,
  ) async {
    await openHistory(tester);
    await tester.tap(inTimeline(find.text('Jumped ahead 30 s')));
    await tester.pumpAndSettle();
    await tester.tap(inTimeline(find.byTooltip('Delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(inTimeline(find.text('Jumped ahead 30 s')), findsOneWidget);
    expect(
      playback.history.where((event) => event.kind == ListeningAction.jump),
      hasLength(2),
    );
  });

  testWidgets('Name on a bookmark saves the title that the listener types', (
    tester,
  ) async {
    await openHistory(tester);
    await tester.tap(inTimeline(find.text('Bookmark')));
    await tester.pumpAndSettle();
    // The save runs in real time, so it starts outside the fake clock.
    await tester.runAsync(() => tester.tap(inTimeline(find.text('Name'))));
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
              onPressed: () => openListeningTimeline(context, playback),
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
    final jump = ListeningEvent(
      id: 'jump',
      at: at.subtract(const Duration(minutes: 2)),
      kind: ListeningAction.jump,
      before: placeAt(0),
      after: placeAt(30000),
      bookTitle: title.title,
      editionLabel: recording.label,
    );
    final mark = AudioBookmark(
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
            body: ListeningTimeline(
              entries: entries,
              editionTime: (place) => place.milliseconds,
              onGoBack: (event) => reports.add(('back', event)),
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

    testWidgets('Go back reports the action whose start to return to', (
      tester,
    ) async {
      await showTimeline(tester);
      await choose(tester, 'Jumped ahead 30 s', find.text('Go back to 00:00'));
      expect(reports, [('back', jump)]);
    });

    testWidgets('Go to on an action reports that action', (tester) async {
      await showTimeline(tester);
      await choose(tester, 'Jumped ahead 30 s', find.text('Go to 00:30'));
      expect(reports, hasLength(1));
      final (kind, entry) = reports.single as (String, ActionEntry);
      expect((kind, entry.event), ('go', jump));
    });

    testWidgets('Go to on a bookmark reports that bookmark', (tester) async {
      await showTimeline(tester);
      await choose(tester, 'Bookmark', find.text('Go to 01:15'));
      expect(reports, hasLength(1));
      final (kind, entry) = reports.single as (String, BookmarkEntry);
      expect((kind, entry.bookmark), ('go', mark));
    });

    testWidgets('Name reports the bookmark and opens no editor itself', (
      tester,
    ) async {
      await showTimeline(tester);
      await choose(tester, 'Bookmark', find.text('Name'));
      expect(reports, [('rename', mark)]);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('Delete reports the entry and asks nothing itself', (
      tester,
    ) async {
      await showTimeline(tester);
      await choose(tester, 'Jumped ahead 30 s', find.byTooltip('Delete'));
      expect(reports, hasLength(1));
      final (kind, entry) = reports.single as (String, ActionEntry);
      expect((kind, entry.event), ('delete', jump));
      expect(find.text('Delete history action?'), findsNothing);
    });

    testWidgets('shows a new entry when its entries change', (tester) async {
      await showTimeline(tester);
      entries.value = [
        BookmarkEntry(
          AudioBookmark(
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
}
