import 'dart:convert';

import 'package:bookfin/catalog/controller.dart';
import 'package:bookfin/catalog/layout.dart';
import 'package:bookfin/catalog/jellyfin.dart';
import 'package:bookfin/foundation/theme.dart';
import 'package:bookfin/settings/screen.dart';
import 'package:bookfin/playback/record_codec.dart';
import 'package:bookfin/sync/record_address.dart';
import 'package:bookfin/sync/journal.dart';
import 'package:bookfin/sync/coordinator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

    Future<void> showTab(
      WidgetTester tester, {
      RecordSync? sync,
      double scale = 1,
    }) => tester.pumpWidget(
      MaterialApp(
        theme: bookfinTheme(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
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

    testWidgets('large-text density choices stay readable and tappable on a '
        'narrow phone', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await signIn(tester);
      await showTab(tester, scale: 3.2);
      expect(tester.takeException(), isNull);
      final segmented = find.byType(SegmentedButton<LibraryDensity>);
      await tester.scrollUntilVisible(find.text('Layout density'), 300);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final heading = tester.getRect(find.text('Layout density'));
      final choices = tester.getRect(segmented);
      expect(heading.top, greaterThanOrEqualTo(0));
      expect(heading.bottom, lessThanOrEqualTo(choices.top));
      expect(heading.left, greaterThanOrEqualTo(0));
      expect(heading.right, lessThanOrEqualTo(320));
      expect(choices.bottom, lessThanOrEqualTo(900));
      final context = tester.element(segmented);
      final shape =
          tester
              .widget<SegmentedButton<LibraryDensity>>(segmented)
              .style
              ?.shape
              ?.resolve({}) ??
          SegmentedButtonTheme.of(context).style!.shape!.resolve({})!;
      final painted = shape.getInnerPath(
        choices,
        textDirection: Directionality.of(context),
      );
      var previousBottom = choices.top;
      for (final label in ['Compact', 'Spacious']) {
        final button = find.ancestor(
          of: find.text(label),
          matching: find.byType(TextButton),
        );
        final bounds = tester.getRect(button);
        expect(bounds.width, greaterThanOrEqualTo(48));
        expect(bounds.height, greaterThanOrEqualTo(48));
        expect(bounds.left, greaterThanOrEqualTo(choices.left));
        expect(bounds.right, lessThanOrEqualTo(choices.right));
        expect(bounds.bottom, lessThanOrEqualTo(choices.bottom));
        expect(bounds.top, greaterThanOrEqualTo(previousBottom));
        previousBottom = bounds.bottom;
        final paragraph = tester.renderObject<RenderParagraph>(
          find.text(label),
        );
        expect(paragraph.didExceedMaxLines, isFalse);
        final lines = paragraph.getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: label.length),
        );
        expect(lines, isNotEmpty);
        for (final line in lines) {
          final visible = line
              .toRect()
              .shift(paragraph.localToGlobal(Offset.zero))
              .deflate(1);
          expect(painted.contains(visible.topLeft), isTrue);
          expect(painted.contains(visible.bottomRight), isTrue);
        }
        await tester.tap(button);
        await tester.pump();
        await tester.runAsync(() => layout.saved);
        final expected = label == 'Compact'
            ? LibraryDensity.compact
            : LibraryDensity.spacious;
        expect(layout.density, expected);
        expect(jsonDecode(layoutStore.value!)['density'], expected.name);
      }
      expect(tester.takeException(), isNull);
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
        final edition = catalog.books.single.editions.single;
        // A valid place in an older source has no chapter in this library.
        final record = RecordAddress(
          'audio',
          'resumes',
          jsonEncode([edition.id, 'saved-source', 'previous-revision']),
        ).encoded;
        final journal =
            RecordJournal('alice', 'phone', null, validateRecordAction)
              ..change(record, {
                'edition': edition.id,
                'source': 'saved-source',
                'revision': 'previous-revision',
                'milliseconds': 1000,
              });
        final records = ControlledRecords()..found = {record: journal.uploads};
        final sync = RecordSync(records: records, transport: records.transport)
          ..bind(catalog.session);
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
