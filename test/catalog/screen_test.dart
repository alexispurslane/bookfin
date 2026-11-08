import 'dart:async';
import 'dart:typed_data';

import 'package:bookfin/catalog/controller.dart';
import 'package:bookfin/catalog/covers.dart';
import 'package:bookfin/catalog/layout.dart';
import 'package:bookfin/catalog/jellyfin.dart';
import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/catalog/screen.dart';
import 'package:bookfin/catalog/book_cover.dart';
import 'package:bookfin/catalog/glass.dart';
import 'package:bookfin/downloads/downloads.dart';
import 'package:bookfin/foundation/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'controller_test.dart'
    show MemoryCatalogStore, MemoryCredentials, FixtureClient;
import 'layout_test.dart' show MemoryLayoutStore;
import 'model_test.dart' show entry;
import '../real_time.dart';

void main() {
  late CatalogController controller;
  late FixtureClient client;
  late LibraryLayout layout;
  Covers? covers;
  setUp(() {
    layout = LibraryLayout(MemoryLayoutStore());
    covers = null;
    client = FixtureClient(Uri.parse('https://books.example'));
    controller = CatalogController(
      credentials: MemoryCredentials(),
      store: MemoryCatalogStore(),
      clientFactory: (server, device) => client,
    );
  });
  tearDown(() {
    controller.dispose();
    client.close();
  });
  Future<void> show(WidgetTester tester, {Downloads? downloads}) =>
      tester.pumpWidget(
        MaterialApp(
          theme: bookfinTheme(Brightness.light),
          home: CatalogHome(
            catalog: controller,
            layout: layout,
            covers: covers,
            downloads: downloads,
            onAppearance: () {},
            onReaderNightChanged: (_) {},
          ),
        ),
      );

  /// Signs in and selects the Books library, in real time.
  Future<void> signIn(WidgetTester tester) async {
    await finish(
      tester,
      controller.connect('https://books.example', 'alice', 'password'),
    );
    await finish(tester, controller.refresh(selected: {'books'}));
  }

  List<CatalogEntry> orchardCycle() => [
    for (final (index, title) in ['First Frost', 'Graft', 'Windfall'].indexed)
      entry(
        'cycle$index',
        title: title,
        type: 'Book',
        container: 'epub',
        fields: {'SeriesName': 'The Orchard Cycle', 'IndexNumber': index + 1},
      ),
    entry('salt', title: 'Salt and Lantern'),
  ];

  testWidgets(
    'the library shows a series as one card that opens its books in order',
    (tester) async {
      client.entries = orchardCycle();
      await signIn(tester);
      await show(tester);
      expect(find.text('Salt and Lantern'), findsOneWidget);
      expect(find.text('The Orchard Cycle'), findsOneWidget);
      expect(find.text('Graft'), findsNothing);
      await tester.tap(find.text('The Orchard Cycle'));
      await tester.pumpAndSettle();
      expect(find.text('BOOK 1'), findsOneWidget);
      expect(find.text('Graft'), findsOneWidget);
      expect(find.text('Salt and Lantern'), findsNothing);
    },
  );

  testWidgets('search is its own screen and lists series books one by one', (
    tester,
  ) async {
    client.entries = orchardCycle();
    await signIn(tester);
    await show(tester);
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'orchard');
    await tester.pump();
    expect(find.text('First Frost'), findsOneWidget);
    expect(find.text('Graft'), findsOneWidget);
    expect(find.text('Windfall'), findsOneWidget);
    expect(find.text('The Orchard Cycle'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('The Orchard Cycle'), findsOneWidget);
  });

  testWidgets(
    'a restored library shows its books with no Saved library label',
    (tester) async {
      final credentials = MemoryCredentials();
      final store = MemoryCatalogStore();
      final first = CatalogController(
        credentials: credentials,
        store: store,
        clientFactory: (server, device) => client,
      );
      await finish(
        tester,
        first.connect('https://books.example', 'alice', 'password'),
      );
      await finish(tester, first.refresh(selected: {'books'}));
      first.dispose();
      controller.dispose();
      controller = CatalogController(
        credentials: credentials,
        store: store,
        clientFactory: (server, device) => client,
      );
      await finish(tester, controller.restore());
      await show(tester);
      expect(find.text('The Orchard'), findsOneWidget);
      expect(find.textContaining('Saved library'), findsNothing);
    },
  );

  group('the catalog keeps its own messages', () {
    testWidgets('an expired sign-in says so and offers no Retry', (
      tester,
    ) async {
      await signIn(tester);
      await show(tester);
      client.failure = const CatalogFailure(CatalogFailureKind.unauthorized);
      await finish(tester, controller.refresh());
      await tester.pumpAndSettle();
      expect(
        find.text('Sign in again. Your Jellyfin session has expired.'),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextButton, 'Retry'), findsNothing);
    });

    testWidgets('revoked access says so and offers no Retry', (tester) async {
      await signIn(tester);
      await show(tester);
      client.failure = const CatalogFailure(CatalogFailureKind.forbidden);
      await finish(tester, controller.refresh());
      await tester.pumpAndSettle();
      expect(find.text('This account does not have access.'), findsOneWidget);
      expect(find.textContaining('Cannot reach Jellyfin'), findsNothing);
      expect(find.widgetWithText(TextButton, 'Retry'), findsNothing);
    });

    testWidgets(
      'a sign-in that cannot reach Jellyfin offers no downloaded books',
      (tester) async {
        await show(tester);
        client.pendingSignIn = Completer();
        final signingIn = controller.connect(
          'https://books.example',
          'alice',
          'password',
        );
        await tester.pump();
        client.pendingSignIn!.completeError(
          const CatalogFailure(CatalogFailureKind.unavailable),
        );
        await signingIn;
        await tester.pumpAndSettle();
        expect(
          find.text(
            'Cannot reach Jellyfin. Check the server address and your connection.',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('downloaded books'), findsNothing);
        expect(find.widgetWithText(TextButton, 'Retry'), findsNothing);
      },
    );

    testWidgets(
      'saving libraries that cannot reach Jellyfin keeps the page open and says so',
      (tester) async {
        await signIn(tester);
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => Scaffold(
                      body: LibrarySelector(
                        catalog: controller,
                        closeOnSave: true,
                      ),
                    ),
                  ),
                ),
                child: const Text('Libraries'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Libraries'));
        await tester.pumpAndSettle();
        client.failure = const CatalogFailure(CatalogFailureKind.unavailable);
        await tester.tap(find.text('Save libraries'));
        await tester.pumpAndSettle();
        expect(find.text('Choose book libraries'), findsOneWidget);
        expect(find.textContaining('Cannot reach Jellyfin'), findsOneWidget);
      },
    );
  });

  testWidgets('the top bar switches the library between a grid and a list', (
    tester,
  ) async {
    await signIn(tester);
    await show(tester);
    expect(find.byType(SliverLayoutBuilder), findsOneWidget);
    await tester.tap(find.byTooltip('Show as list'));
    await tester.pumpAndSettle();
    expect(find.byType(SliverLayoutBuilder), findsNothing);
    expect(layout.view, LibraryView.list);
    await tester.tap(find.byTooltip('Show as grid'));
    await tester.pumpAndSettle();
    expect(find.byType(SliverLayoutBuilder), findsOneWidget);
  });

  testWidgets('settings make the library compact', (tester) async {
    await signIn(tester);
    await show(tester);
    final spacious = tester.getSize(find.byType(BookCover)).width;
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compact'));
    await tester.pumpAndSettle();
    expect(layout.density, LibraryDensity.compact);
    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(BookCover)).width, lessThan(spacious));
  });

  testWidgets('pages opened from the library show Jellyfin covers too', (
    tester,
  ) async {
    covers = _NoCovers();
    client.entries = [
      for (final entry in orchardCycle())
        CatalogEntry.fromJson({
          ...entry.json,
          'ImageTags': {'Primary': 'tag'},
        }, libraryId: 'books'),
    ];
    await signIn(tester);
    await show(tester);
    final coverImages = find.byWidgetPredicate(
      (widget) => widget is Image && widget.image is CoverImage,
    );
    expect(coverImages, findsWidgets);
    await tester.tap(find.text('The Orchard Cycle'));
    await tester.pumpAndSettle();
    expect(coverImages, findsWidgets, reason: 'the series page');
    await tester.tap(find.text('Graft'));
    await tester.pumpAndSettle();
    expect(coverImages, findsWidgets, reason: 'the book page');
  });

  testWidgets('permission recovery closes only the library selector', (
    tester,
  ) async {
    await signIn(tester);
    await show(tester);
    client.failure = const CatalogFailure(CatalogFailureKind.forbidden);
    await finish(tester, controller.refresh());
    await tester.pumpAndSettle();
    client.failure = null;
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Libraries'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save libraries'));
    await runUntil(tester, () => !controller.busy);
    await tester.pumpAndSettle();
    expect(find.byType(CatalogHome), findsOneWidget);
    expect(find.text('The Orchard'), findsOneWidget);
    expect(
      Navigator.of(tester.element(find.byType(CatalogHome))).canPop(),
      isFalse,
    );
  });

  testWidgets('password managers recognize the sign-in fields as one login', (
    tester,
  ) async {
    await show(tester);
    List<String>? hints(String label) => tester
        .widget<EditableText>(
          find.descendant(
            of: find.widgetWithText(TextFormField, label),
            matching: find.byType(EditableText),
          ),
        )
        .autofillHints
        ?.toList();
    expect(hints('Server address'), [AutofillHints.url]);
    expect(hints('Username'), [AutofillHints.username]);
    expect(hints('Password'), [AutofillHints.password]);
    final group = find.byType(AutofillGroup);
    expect(group, findsOneWidget);
    for (final label in ['Server address', 'Username', 'Password']) {
      expect(
        find.descendant(
          of: group,
          matching: find.widgetWithText(TextFormField, label),
        ),
        findsOneWidget,
      );
    }
  });

  testWidgets(
    'sign-in is usable without gallery labels or enabled media controls',
    (tester) async {
      await show(tester);
      expect(
        find.widgetWithText(TextFormField, 'Server address'),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextFormField, 'Username'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Password'), findsOneWidget);
      final password = tester.widget<TextFormField>(
        find.widgetWithText(TextFormField, 'Password'),
      );
      expect(password.restorationId, isNull);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Server address'),
        'https://books.example',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Username'),
        'alice',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'private-password',
      );
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();
      expect(find.text('Choose book libraries'), findsOneWidget);
      expect(find.textContaining('Development gallery'), findsNothing);
      expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
    },
  );

  testWidgets(
    'the main navigation appears only after sign-in, at the bottom screen edge',
    (tester) async {
      await show(tester);
      expect(find.byType(NavigationBar), findsNothing);
      await signIn(tester);
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
      final navigation = tester.getRect(find.byType(NavigationBar));
      expect(
        navigation.bottom,
        tester.view.physicalSize.height / tester.view.devicePixelRatio,
      );
      final destinations = tester
          .widgetList<NavigationDestination>(find.byType(NavigationDestination))
          .toList();
      expect(
        destinations
            .where((destination) => destination.enabled)
            .map((destination) => destination.label),
        ['Library', 'Downloads', 'Settings'],
        reason: 'Listening needs a player',
      );
    },
  );

  testWidgets(
    'selecting a book library reveals saved books and their real editions',
    (tester) async {
      await finish(
        tester,
        controller.connect('https://books.example', 'alice', 'password'),
      );
      await show(tester);
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Books'));
      await tester.tap(find.widgetWithText(FilledButton, 'Save libraries'));
      await runUntil(tester, () => !controller.busy);
      await tester.pumpAndSettle();
      expect(find.text('The Orchard'), findsOneWidget);
      await tester.tap(find.text('The Orchard'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Audiobook'), 300);
      expect(find.text('Audiobook'), findsOneWidget);
      expect(find.text('Not downloaded'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Play'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Download'), findsNothing);
    },
  );

  testWidgets('book search filters the real cached catalog', (tester) async {
    client.entries = [entry('one'), entry('two', title: 'The River')];
    await signIn(tester);
    await show(tester);
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'river');
    await tester.pump();
    expect(find.text('The River'), findsOneWidget);
    expect(find.text('The Orchard'), findsNothing);
  });

  testWidgets(
    'a series opens its books in explicit fractional order rather than title order',
    (tester) async {
      client.entries = [
        entry('one', title: 'Z first'),
        entry('two', title: 'A side story'),
      ];
      {
        await signIn(tester);
        await finish(
          tester,
          controller.correctBook(
            'book:one',
            const BookDetails(
              title: 'Z first',
              author: 'Writer',
              series: 'Garden',
              seriesOrder: 1,
            ),
          ),
        );
        await finish(
          tester,
          controller.correctBook(
            'book:two',
            const BookDetails(
              title: 'A side story',
              author: 'Writer',
              series: 'Garden',
              seriesOrder: 1.5,
            ),
          ),
        );
      }
      await show(tester);
      expect(
        find.text('Z first'),
        findsNothing,
        reason: 'the series is grouped',
      );
      await tester.tap(find.text('Garden'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Show as list'));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('Z first')).dy,
        lessThan(tester.getTopLeft(find.text('A side story')).dy),
      );
    },
  );

  testWidgets(
    'the correction dialog shows the corrected book behind its glass',
    (tester) async {
      await signIn(tester);
      await show(tester);
      await tester.tap(find.text('The Orchard'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Correct book details'));
      await tester.pumpAndSettle();
      final behind = find.descendant(
        of: find.ancestor(
          of: find.text('Correct book details'),
          matching: find.byType(CoverGlass),
        ),
        matching: find.byType(CoverBlur),
      );
      expect(behind, findsOneWidget);
      expect(tester.widget<CoverBlur>(behind).book.title, 'The Orchard');
    },
  );

  testWidgets('sign-out dismisses open corrections from the previous account', (
    tester,
  ) async {
    await signIn(tester);
    await show(tester);
    await tester.tap(find.text('The Orchard'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Correct book details'));
    await tester.pumpAndSettle();
    expect(find.text('Correct book details'), findsOneWidget);
    await controller.signOut();
    await tester.pumpAndSettle();
    expect(find.text('Correct book details'), findsNothing);
    expect(find.text('The Orchard'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
  });

  testWidgets('revoked library access dismisses an open book correction', (
    tester,
  ) async {
    await signIn(tester);
    await show(tester);
    await tester.tap(find.text('The Orchard'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Correct book details'));
    await tester.pumpAndSettle();
    client.failure = const CatalogFailure(CatalogFailureKind.forbidden);
    await finish(tester, controller.refresh());
    await tester.pumpAndSettle();
    expect(controller.books, isEmpty);
    expect(find.text('Correct book details'), findsNothing);
    expect(find.text('The Orchard'), findsNothing);
  });

  testWidgets(
    'recording file choices use source names and require confirmation',
    (tester) async {
      client.entries = [
        entry('one', title: 'Orchard part 1', track: 1),
        entry('two', title: 'Orchard part 2', track: 2),
      ];
      await signIn(tester);
      await finish(tester, controller.linkBooks('book:two', 'book:one'));
      await show(tester);
      await tester.tap(find.text('Orchard part 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Combine files of one recording'));
      await tester.pumpAndSettle();
      final first = find.widgetWithText(CheckboxListTile, 'Orchard part 1');
      final second = find.widgetWithText(CheckboxListTile, 'Orchard part 2');
      expect(first, findsOneWidget);
      expect(second, findsOneWidget);
      await tester.tap(first);
      await tester.tap(second);
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Combine as one recording?'), findsOneWidget);
      expect(controller.books.single.editions, hasLength(2));
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(controller.books.single.editions, hasLength(2));
      await tester.tap(find.byTooltip('More actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Combine files of one recording'));
      await tester.pumpAndSettle();
      await tester.tap(first);
      await tester.tap(second);
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Combine files'));
      await runUntil(
        tester,
        () => controller.books.single.editions.length == 1,
      );
      await tester.pumpAndSettle();
      expect(
        controller.books.single.editions.single.files.map(
          (file) => file.itemId,
        ),
        ['one', 'two'],
      );
    },
  );

  testWidgets('ambiguous matches stay separate until the final confirmation', (
    tester,
  ) async {
    client.entries = [
      entry('one'),
      entry('two', type: 'Book', container: 'epub'),
    ];
    await signIn(tester);
    await show(tester);
    await tester.tap(find.text('The Orchard').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Link another book or ebook'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(ListTile, 'The Orchard').hitTestable(),
    );
    await tester.pumpAndSettle();
    expect(controller.books, hasLength(2));
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(controller.books, hasLength(2));
    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Link another book or ebook'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(ListTile, 'The Orchard').hitTestable(),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Link editions'));
    await runUntil(tester, () => controller.books.length == 1);
    await tester.pumpAndSettle();
    expect(find.text('Link editions?'), findsNothing);
    expect(controller.message, isNull);
    expect(controller.books, hasLength(1));
    expect(controller.books.single.editions, hasLength(2));
  });

  testWidgets(
    'resetting corrections requires confirmation and restores source details',
    (tester) async {
      await signIn(tester);
      await finish(
        tester,
        controller.correctBook(
          'book:one',
          const BookDetails(title: 'My title', author: 'Writer'),
        ),
      );
      await show(tester);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Reset catalog corrections'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reset catalog corrections'));
      await tester.pumpAndSettle();
      expect(controller.books.single.title, 'My title');
      await tester.tap(find.widgetWithText(FilledButton, 'Reset corrections'));
      await runUntil(tester, () => controller.books.single.title != 'My title');
      await tester.pumpAndSettle();
      expect(controller.books.single.title, 'The Orchard');
    },
  );
}

class _NoCovers implements Covers {
  @override
  Future<Uint8List?> load(JellyfinSession session, CoverRef cover) async =>
      null;
  @override
  Future<void> clear() async {}
}
