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
}
