import 'dart:convert';

import 'package:bookfin/catalog/controller.dart';
import 'package:bookfin/catalog/layout.dart';
import 'package:bookfin/catalog/jellyfin.dart';
import 'package:bookfin/settings/screen.dart';
import 'package:bookfin/sync/coordinator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../catalog/controller_test.dart'
    show FixtureClient, MemoryCatalogStore, MemoryCredentials;
import '../catalog/model_test.dart' show entry;
import '../real_time.dart';
import '../sync/status_test.dart' show ControlledRecords;

void main() {
  testWidgets(
    'the density switch reports the chosen density and changes nothing itself',
    (tester) async {
      final chosen = <LibraryDensity>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DensitySwitch(
              density: LibraryDensity.spacious,
              onChanged: chosen.add,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Compact'));
      await tester.pump();
      expect(chosen, [LibraryDensity.compact]);
      final segments = tester.widget<SegmentedButton<LibraryDensity>>(
        find.byType(SegmentedButton<LibraryDensity>),
      );
      expect(segments.selected, {LibraryDensity.spacious});
    },
  );

  group('the Settings tab', () {
    late FixtureClient client;
    late CatalogController catalog;
    late MemoryLayoutStore layoutStore;
    late LibraryLayout layout;

    setUp(() {
      client = FixtureClient(Uri.parse('https://books.example'));
      catalog = CatalogController(
        credentials: MemoryCredentials(),
        store: MemoryCatalogStore(),
        clientFactory: (server, device) => client,
      );
      layoutStore = MemoryLayoutStore();
      layout = LibraryLayout(layoutStore);
    });
    tearDown(() {
      catalog.dispose();
      client.close();
    });

    // The catalog talks to the fixture client in real time.
    Future<void> signIn(WidgetTester tester) => tester.runAsync(() async {
      await catalog.connect('https://books.example', 'alice', 'password');
      await catalog.refresh();
    });

    Future<void> showTab(WidgetTester tester, {RecordSync? sync}) =>
        tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SettingsTab(
                catalog: catalog,
                layout: layout,
                onAppearance: () {},
                sync: sync,
              ),
            ),
          ),
        );

    testWidgets('choosing Compact saves it in the layout', (tester) async {
      await signIn(tester);
      await showTab(tester);
      await tester.tap(find.text('Compact'));
      await tester.pump();
      // The layout saves on a future that began outside fake time.
      await tester.runAsync(() => layout.saved);
      expect(layout.density, LibraryDensity.compact);
      expect(jsonDecode(layoutStore.value!)['density'], 'compact');
      expect(
        tester
            .widget<SegmentedButton<LibraryDensity>>(
              find.byType(SegmentedButton<LibraryDensity>),
            )
            .selected,
        {LibraryDensity.compact},
      );
    });

    testWidgets('the Libraries row names the libraries that show', (
      tester,
    ) async {
      client.views = [
        const BookLibrary('books', 'Books'),
        const BookLibrary('more', 'More books'),
      ];
      await signIn(tester);
      await showTab(tester);
      expect(find.text('Books, More books · 2 of 2 shown'), findsOneWidget);
      await tester.runAsync(() => catalog.refresh(hidden: {'more'}));
      await tester.pump();
      expect(find.text('Books · 1 of 2 shown'), findsOneWidget);
    });

    testWidgets('unticking a library in Settings hides it, and ticking it '
        'again shows it', (tester) async {
      client.views = [
        const BookLibrary('books', 'Books'),
        const BookLibrary('more', 'More books'),
      ];
      await signIn(tester);
      await showTab(tester);
      Future<void> toggle(String library) async {
        await tester.tap(find.text('Libraries'));
        await tester.pumpAndSettle();
        expect(find.byType(CheckboxListTile), findsNWidgets(2));
        await tester.tap(find.widgetWithText(CheckboxListTile, library));
        await tester.pump();
        await tester.tap(find.widgetWithText(FilledButton, 'Save libraries'));
        await runUntil(tester, () => !catalog.busy);
        await tester.pumpAndSettle();
      }

      await toggle('More books');
      expect(catalog.accountNotifier.value.hidden, {'more'});
      expect(find.text('Books · 1 of 2 shown'), findsOneWidget);
      await toggle('More books');
      expect(catalog.accountNotifier.value.hidden, isEmpty);
      expect(find.text('Books, More books · 2 of 2 shown'), findsOneWidget);
    });

    testWidgets(
      'after a library refresh, the record sync page names the book from the new library',
      (tester) async {
        await signIn(tester);
        final edition = catalog.books.single.editions.single.id;
        final records = ControlledRecords()
          ..found = {
            jsonEncode(['audio', 'resumes', edition]): [
              {
                'replica': 'phone',
                'sequence': 1,
                'value': {'edition': edition, 'milliseconds': 1000},
              },
            ],
          };
        final sync = RecordSync(records: records)..bind(catalog.session);
        await sync.synchronize();
        await showTab(tester, sync: sync);
        await tester.tap(find.text('Personal-record sync'));
        await tester.pumpAndSettle();
        expect(find.text('The Orchard'), findsOneWidget);
        client.entries = [entry('one', title: 'The River')];
        await tester.runAsync(catalog.refresh);
        await tester.pump();
        expect(find.text('The River'), findsOneWidget);
        // A live 30-second sync timer fails a widget test.
        sync.dispose();
      },
    );
  });
}

class MemoryLayoutStore implements LayoutStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async => this.value = value;
}
