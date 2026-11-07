import 'package:bookfin/app/account_binding.dart';
import 'package:bookfin/catalog/controller.dart';
import 'package:bookfin/catalog/screen.dart';
import 'package:bookfin/foundation/theme.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../catalog/controller_test.dart'
    show FixtureClient, MemoryCredentials, MemoryCatalogStore;
import 'playback_test.dart' show LocalFiles, TestEngine, MemoryResume;

void main() {
  late FixtureClient client;
  late CatalogController catalog;
  late LocalFiles downloads;
  late Playback playback;
  setUp(() async {
    client = FixtureClient(Uri.parse('https://books.example'));
    catalog = CatalogController(
      credentials: MemoryCredentials(),
      store: MemoryCatalogStore(),
      clientFactory: (_, _) => client,
    );
    downloads = LocalFiles();
    playback = Playback(
      downloads: downloads,
      engine: TestEngine(),
      store: MemoryResume(),
    );
    await catalog.connect('https://books.example', 'alice', 'fixture-password');
    await catalog.refresh(selected: {'books'});
    final book = catalog.books.first;
    final edition = book.editions.first;
    for (final file in edition.files) {
      downloads.files[file.key] = Uri.file('/fixture.wav');
    }
    await playback.bind(catalog.session, catalog.books);
    await playback.open(book, edition);
    await playback.addBookmark(title: 'Alice private bookmark');
  });
  tearDown(() async {
    await playback.close();
    downloads.dispose();
    catalog.dispose();
    client.close();
  });
  testWidgets(
    'root Listening opens the history timeline and sign-out dismisses it',
    (tester) async {
      final binding = AccountBinding(
        catalog: catalog,
        downloads: downloads,
        playback: playback,
      );
      addTearDown(binding.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: bookfinTheme(Brightness.light),
          home: CatalogHome(
            catalog: catalog,
            onAppearance: () {},
            onReaderNightChanged: (_) {},
            downloads: downloads,
            playback: playback,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Listening'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('History'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();
      expect(find.text('Alice private bookmark'), findsOneWidget);
      await tester.runAsync(() async {
        await catalog.signOut();
        await playback.flush();
      });
      await tester.pumpAndSettle();
      expect(find.text('Alice private bookmark'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
      expect(playback.bookmarks, isEmpty);
      expect(playback.history, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
