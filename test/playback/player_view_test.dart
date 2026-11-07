import 'package:bookfin/catalog/book_cover.dart';
import 'package:bookfin/catalog/glass.dart';
import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/foundation/theme.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:bookfin/playback/screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'playback_test.dart'
    show LocalFiles, TestEngine, MemoryResume, account, first, second;

const narrated = Edition(
  id: 'narrated',
  kind: EditionKind.audio,
  label: 'Ines Okoro',
  narrator: 'Ines Okoro',
  files: [first, second],
  memberIds: ['one:m1', 'two:m2'],
);
const book = Book(
  id: 'book',
  title: 'The journey',
  author: 'A. Writer',
  editions: [narrated],
);

void main() {
  late Playback playback;
  late LocalFiles downloads;
  setUp(() async {
    downloads = LocalFiles();
    playback = Playback(
      downloads: downloads,
      engine: TestEngine(),
      store: MemoryResume(),
    );
    await playback.bind(account(), [book]);
    await playback.open(book, narrated, autoplay: false);
  });
  tearDown(() async {
    await playback.close();
    downloads.dispose();
  });

  Future<void> showPlayer(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    ValueChanged<Book>? onOpenBook,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: bookfinTheme(brightness),
        home: Scaffold(
          body: PlayerView(playback: playback, onOpenBook: onOpenBook),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the player credits the author and the narrator', (tester) async {
    await showPlayer(tester);
    expect(
      find.text('A. Writer · read by Ines Okoro', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('the player names the current chapter and its place', (
    tester,
  ) async {
    await showPlayer(tester);
    expect(find.text('Opening · 1 of 4'), findsOneWidget);
    expect(find.text('chapter 40 s left'), findsOneWidget);

    await tester.runAsync(() => playback.seekEdition(75000));
    await tester.pumpAndSettle();
    expect(find.text('Return · 4 of 4'), findsOneWidget);
  });

  testWidgets('the tool row opens chapters and shows the current speed', (
    tester,
  ) async {
    await showPlayer(tester);
    expect(find.text('1×'), findsOneWidget);
    await tester.tap(find.text('Speed'));
    await tester.pumpAndSettle();
    expect(find.text('Playback speed'), findsOneWidget);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Chapters'));
    await tester.pumpAndSettle();
    expect(find.text('Arrival'), findsOneWidget);
  });

  testWidgets('the chapters sheet floats on glass over the open book', (
    tester,
  ) async {
    await showPlayer(tester);
    await tester.tap(find.text('Chapters'));
    await tester.pumpAndSettle();
    final glass = find.ancestor(
      of: find.text('Arrival'),
      matching: find.byType(CoverGlass),
    );
    expect(glass, findsOneWidget);
    final behind = find.descendant(of: glass, matching: find.byType(CoverBlur));
    expect(tester.widget<CoverBlur>(behind).book, book);
  });

  testWidgets('tapping Bookmark saves an untitled bookmark at once', (
    tester,
  ) async {
    await showPlayer(tester);
    await tester.runAsync(() async {
      await tester.tap(find.text('Bookmark'));
      await playback.flush();
    });
    await tester.pumpAndSettle();
    expect(playback.bookmarks.single.title, isNull);
    expect(find.byType(GlassDialog), findsNothing);
    expect(find.text('Bookmarked'), findsOneWidget);
  });

  testWidgets('every tool label stays on one line, even Bookmarked', (
    tester,
  ) async {
    await showPlayer(tester);
    await tester.runAsync(() async {
      await tester.tap(find.text('Bookmark'));
      await playback.flush();
    });
    await tester.pumpAndSettle();
    final line = tester.getSize(find.text('Sleep')).height;
    for (final label in ['Chapters', 'Bookmarked', 'Speed', 'History']) {
      expect(tester.getSize(find.text(label)).height, line, reason: label);
    }
  });

  testWidgets('a tap on Bookmarked names the bookmark at this place', (
    tester,
  ) async {
    await tester.runAsync(() => playback.addBookmark());
    await showPlayer(tester);
    await tester.tap(find.text('Bookmarked'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Title (optional)'),
      'The letter',
    );
    await tester.runAsync(() async {
      await tester.tap(find.text('Save bookmark'));
      await playback.flush();
    });
    await tester.pumpAndSettle();
    expect(playback.bookmarks.single.title, 'The letter');
  });

  testWidgets('the position bar marks each bookmark where it is', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await playback.seekEdition(75000);
      await playback.addBookmark();
      await playback.seekEdition(0);
    });
    await showPlayer(tester);
    final marks = find.byKey(const ValueKey('position marks'));
    expect(
      tester.getRect(marks).width,
      tester.getRect(find.byType(Slider)).width,
    );
    // 75 s of 150 s is halfway along the bar. The chapter starts are drawn as
    // rectangles, so the one circle is the bookmark.
    expect(
      tester.renderObject(marks),
      paints..circle(x: tester.getSize(marks).width / 2),
    );
  });

  testWidgets('a long press on a jump button sets the jump lengths', (
    tester,
  ) async {
    await showPlayer(tester);
    await tester.longPress(find.byTooltip('Forward 30 seconds'));
    await tester.pumpAndSettle();
    expect(find.text('Save jump lengths'), findsOneWidget);
  });

  testWidgets('the more menu offers jump lengths and the book details', (
    tester,
  ) async {
    Book? opened;
    await showPlayer(tester, onOpenBook: (book) => opened = book);
    await tester.tap(find.byTooltip('More player actions'));
    await tester.pumpAndSettle();
    expect(find.text('Jump lengths'), findsOneWidget);
    await tester.tap(find.text('Book details'));
    await tester.pumpAndSettle();
    expect(opened, book);
  });

  testWidgets('at night the player stage uses the dark theater colors', (
    tester,
  ) async {
    await showPlayer(tester, brightness: Brightness.dark);
    final scheme = Theme.of(tester.element(find.text('The journey')))
        .colorScheme;
    expect(scheme.surface, const Color(0xFF22170F));
    expect(scheme.onSurface, const Color(0xFFF3E6D2));
  });

  testWidgets('by day the player stage keeps the paper colors', (tester) async {
    await showPlayer(tester);
    final scheme = Theme.of(tester.element(find.text('The journey')))
        .colorScheme;
    expect(scheme.surface, bookfinTheme(Brightness.light).colorScheme.surface);
  });

  testWidgets('the player controls are announced as named buttons', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await showPlayer(tester);
    for (final label in ['Back 10 seconds', 'Forward 30 seconds', 'Play']) {
      expect(
        tester.getSemantics(find.bySemanticsLabel(label)),
        isSemantics(label: label, isButton: true),
      );
    }
    for (final tool in ['Chapters', 'Bookmark', 'Sleep']) {
      expect(
        tester.getSemantics(find.bySemanticsLabel(tool)),
        isSemantics(isButton: true),
      );
    }
    expect(
      tester.getSemantics(find.bySemanticsLabel(RegExp('Speed'))),
      isSemantics(isButton: true),
    );
    semantics.dispose();
  });

  /// Whether a repaint of [ticking] also repaints [blur]: the nearest repaint
  /// boundary above [ticking] holds [blur] too.
  bool repaintsWith(WidgetTester tester, Finder ticking, Finder blur) {
    var boundary = tester.renderObject(ticking);
    while (!boundary.isRepaintBoundary) {
      boundary = boundary.parent!;
    }
    for (
      RenderObject? node = tester.renderObject(blur);
      node != null;
      node = node.parent
    ) {
      if (node == boundary) return true;
    }
    return false;
  }

  testWidgets('the ticking position repaints apart from the blurred stage', (
    tester,
  ) async {
    await showPlayer(tester);
    final stage = find.byType(CoverBlur);
    expect(repaintsWith(tester, find.byType(Slider), stage), isFalse);
    expect(
      repaintsWith(tester, find.text('chapter 40 s left'), stage),
      isFalse,
    );
    expect(repaintsWith(tester, find.byTooltip('Play'), stage), isFalse);
  });

  testWidgets('in the popup the ticking position repaints apart from the '
      'glass', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: bookfinTheme(Brightness.light),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => openPlayer(context, playback),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final glass = find.byType(BackdropFilter);
    expect(repaintsWith(tester, find.byType(Slider), glass), isFalse);
    expect(
      repaintsWith(tester, find.text('chapter 40 s left'), glass),
      isFalse,
    );
  });

  testWidgets('the mini player\'s progress repaints apart from its glass', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: bookfinTheme(Brightness.light),
        home: Scaffold(
          bottomNavigationBar: PlaybackMiniPlayer(playback: playback),
        ),
      ),
    );
    final glass = find.byType(BackdropFilter);
    expect(
      repaintsWith(tester, find.byType(LinearProgressIndicator), glass),
      isFalse,
    );
  });
}
