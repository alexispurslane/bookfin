import 'package:bookfin/catalog/book_cover.dart';
import 'package:bookfin/catalog/glass.dart';
import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/foundation/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const playing = Book(
  id: 'playing',
  title: 'Blood Music',
  author: 'Greg Bear',
  editions: [],
);
const opened = Book(
  id: 'opened',
  title: "'Salem's Lot",
  author: 'Stephen King',
  editions: [],
);

void main() {
  /// Shows a page inside the app's cover scope, with [playingBook] in the
  /// player, and gives the page's context to [open] when the button is tapped.
  /// A [pageBook] makes it the page about that book.
  Future<void> showPage(
    WidgetTester tester, {
    Book? playingBook,
    Book? pageBook,
    required void Function(BuildContext context) open,
  }) async {
    final page = Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => open(context),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: bookfinTheme(Brightness.dark),
        home: CoverScope(
          covers: null,
          session: null,
          playing: playingBook,
          child: pageBook == null
              ? page
              : PageBook(book: pageBook, child: page),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  /// The glass pane around [text].
  Finder glassAround(String text) =>
      find.ancestor(of: find.text(text), matching: find.byType(CoverGlass));

  /// The book whose cover shows behind the glass around [text], or null for
  /// plain frost.
  Book? bookBehind(WidgetTester tester, String text) {
    final blur = find.descendant(
      of: glassAround(text),
      matching: find.byType(CoverBlur),
    );
    if (blur.evaluate().isEmpty) return null;
    return tester.widget<CoverBlur>(blur.first).book;
  }

  testWidgets('a sheet about a book shows that book behind its glass', (
    tester,
  ) async {
    await showPage(
      tester,
      playingBook: playing,
      open: (context) => showGlassSheet<void>(
        context,
        book: opened,
        builder: (_) => const Text('Download'),
      ),
    );
    expect(glassAround('Download'), findsOneWidget);
    expect(bookBehind(tester, 'Download'), opened);
  });

  testWidgets('a dialog that belongs to no book shows the playing book', (
    tester,
  ) async {
    await showPage(
      tester,
      playingBook: playing,
      open: (context) => showDialog<void>(
        context: context,
        builder: (_) => const GlassDialog(
          title: Text('Remove leftover files?'),
          content: Text('The files go away.'),
        ),
      ),
    );
    expect(glassAround('Remove leftover files?'), findsOneWidget);
    expect(bookBehind(tester, 'Remove leftover files?'), playing);
  });

  testWidgets('a dialog opened on a book\'s page shows that book', (
    tester,
  ) async {
    await showPage(
      tester,
      playingBook: playing,
      open: (context) => showDialog<void>(
        context: context,
        builder: (_) => const GlassDialog(title: Text('Correct book details')),
      ),
      pageBook: opened,
    );
    expect(bookBehind(tester, 'Correct book details'), opened);
  });

  testWidgets('a layer that names its own book shows it on any page', (
    tester,
  ) async {
    await showPage(
      tester,
      playingBook: playing,
      open: (context) => showGlassSheet<void>(
        context,
        book: playing,
        builder: (_) => const Text('Player'),
      ),
      pageBook: opened,
    );
    expect(bookBehind(tester, 'Player'), playing);
  });

  testWidgets('with nothing playing, a dialog is plain frost', (tester) async {
    await showPage(
      tester,
      open: (context) => showDialog<void>(
        context: context,
        builder: (_) => const GlassDialog(title: Text('Sign out?')),
      ),
    );
    expect(glassAround('Sign out?'), findsOneWidget);
    expect(bookBehind(tester, 'Sign out?'), isNull);
  });

  testWidgets('a dialog keeps its actions and returns the chosen answer', (
    tester,
  ) async {
    bool? answer;
    await showPage(
      tester,
      open: (context) async => answer = await showDialog<bool>(
        context: context,
        builder: (context) => GlassDialog(
          title: const Text('Remove files?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Remove files'),
            ),
          ],
        ),
      ),
    );
    await tester.tap(find.text('Remove files'));
    await tester.pumpAndSettle();
    expect(answer, isTrue);
    expect(find.text('Remove files?'), findsNothing);
  });

  testWidgets('a confirmation is true only when its filled action is chosen', (
    tester,
  ) async {
    final answers = <bool>[];
    Future<void> ask(BuildContext context) async => answers.add(
      await confirmAction(
        context,
        title: 'Remove files?',
        message: 'The files leave this phone.',
        action: 'Remove files',
        cancel: 'Keep files',
      ),
    );
    await showPage(tester, open: ask);
    expect(glassAround('The files leave this phone.'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Remove files'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Keep files'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(answers, [true, false, false]);
  });

  testWidgets('a sheet\'s title row holds its heading and one quiet action, '
      'which closes the sheet and reports the tap', (tester) async {
    final handle = tester.ensureSemantics();
    final log = <String>[];
    await showPage(
      tester,
      open: (context) async {
        await showGlassSheet<void>(
          context,
          title: 'Note',
          action: GlassSheetAction(
            'Go to note',
            icon: Icons.arrow_forward_rounded,
            onPressed: () => log.add('Go to note'),
          ),
          builder: (_) => const Text('The note.'),
        );
        log.add('sheet closed');
      },
    );
    final heading = find.text('Note');
    final action = find.widgetWithText(TextButton, 'Go to note');
    expect(glassAround('Note'), findsOneWidget);
    expect(glassAround('Go to note'), findsOneWidget);
    expect(
      tester.getCenter(action).dy,
      moreOrLessEquals(tester.getCenter(heading).dy, epsilon: 1),
      reason: 'The heading and the action share one row.',
    );
    expect(
      tester.getCenter(action).dx,
      greaterThan(tester.getCenter(heading).dx),
      reason: 'The action sits at the end of the row.',
    );
    expect(
      tester.getCenter(find.text('The note.')).dy,
      greaterThan(tester.getRect(action).bottom),
      reason: 'The content sits under the title row.',
    );
    expect(tester.getSize(action).height, greaterThanOrEqualTo(48));
    expect(
      tester.getSemantics(action),
      isSemantics(label: 'Go to note', isButton: true, hasTapAction: true),
    );
    expect(tester.getSemantics(heading), isSemantics(isHeader: true));

    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(find.text('The note.'), findsNothing);
    expect(log, ['Go to note', 'sheet closed']);
    handle.dispose();
  });

  testWidgets('a glass sheet steps back while another layer covers it', (
    tester,
  ) async {
    late BuildContext lower;
    await showPage(
      tester,
      open: (context) => showGlassSheet<void>(
        context,
        builder: (context) {
          lower = context;
          return const SizedBox(width: 300, height: 120, child: Text('Lower'));
        },
      ),
    );
    final alone = tester.getRect(find.byType(SizedBox).last);

    showGlassSheet<void>(lower, builder: (_) => const Text('Upper'));
    await tester.pumpAndSettle();
    final covered = tester.getRect(find.byType(SizedBox).last);
    expect(covered.width, lessThan(alone.width));

    Navigator.of(lower).pop();
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(SizedBox).last), alone);
  });

  testWidgets('a message floats on glass with the playing book behind it', (
    tester,
  ) async {
    await showPage(
      tester,
      playingBook: playing,
      open: (context) => showGlassMessage(context, 'The download stopped.'),
    );
    expect(glassAround('The download stopped.'), findsOneWidget);
    expect(bookBehind(tester, 'The download stopped.'), playing);
  });

  testWidgets('a menu opens on glass and runs the chosen action', (
    tester,
  ) async {
    var chosen = '';
    await tester.pumpWidget(
      MaterialApp(
        theme: bookfinTheme(Brightness.light),
        home: CoverScope(
          covers: null,
          session: null,
          playing: playing,
          child: Scaffold(
            appBar: AppBar(
              actions: [
                GlassMenuButton(
                  tooltip: 'More actions',
                  items: [
                    GlassMenuItem(
                      'Edit details',
                      onSelected: () => chosen = 'edit',
                    ),
                    GlassMenuItem(
                      'Combine',
                      onSelected: () => chosen = 'combine',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    expect(glassAround('Combine'), findsOneWidget);
    expect(bookBehind(tester, 'Combine'), playing);

    await tester.tap(find.text('Combine'));
    await tester.pumpAndSettle();
    expect(chosen, 'combine');
    expect(find.text('Combine'), findsNothing);
  });

  testWidgets('glass panes in one backdrop group share one blur', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BackdropGroup(
          child: Row(
            children: [
              for (final label in ['left', 'right'])
                Expanded(child: CoverGlass(child: Text(label))),
            ],
          ),
        ),
      ),
    );
    final keys = {
      for (final filter in tester.widgetList<BackdropFilter>(
        find.byType(BackdropFilter),
      ))
        filter.backdropGroupKey,
    };
    expect(keys, hasLength(1));
    expect(keys.single, isNotNull);
  });
}
