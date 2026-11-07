import 'package:bookfin/app/account_binding.dart';
import 'package:bookfin/catalog/controller.dart';
import 'package:bookfin/catalog/screen.dart';
import 'package:bookfin/foundation/theme.dart';
import 'package:bookfin/reader/screen.dart';
import 'package:bookfin/reader/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_epub_viewer/publication.dart';
import 'package:flutter_test/flutter_test.dart';

import '../catalog/controller_test.dart'
    show FixtureClient, MemoryCredentials, MemoryCatalogStore;
import '../catalog/model_test.dart' show entry;
import '../playback/playback_test.dart' show LocalFiles, MemoryResume;
import 'publication_test.dart' show epub;

void main() {
  testWidgets(
    'book details opens the production reader and sign-out closes the old account',
    (tester) async {
      final client = FixtureClient(Uri.parse('https://books.example'));
      client.entries = [entry('ebook', type: 'Book', container: 'epub')];
      final catalog = CatalogController(
        credentials: MemoryCredentials(),
        store: MemoryCatalogStore(),
        clientFactory: (server, device) => client,
      );
      final downloads = LocalFiles();
      final reader = ReaderSession(
        downloads: downloads,
        store: MemoryResume(),
        load: (_) async => Publication.admit(epub()),
      );
      await catalog.connect(
        'https://books.example',
        'alice',
        'fixture-password',
      );
      await catalog.refresh(selected: {'books'});
      downloads.files[catalog.books.single.editions.single.files.single.key] =
          Uri.file('/verified.epub');
      final binding = AccountBinding(
        catalog: catalog,
        downloads: downloads,
        reader: reader,
      );
      addTearDown(binding.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: bookfinTheme(Brightness.light),
          home: CatalogHome(
            catalog: catalog,
            downloads: downloads,
            reader: reader,
            onAppearance: () {},
            onReaderNightChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('The Orchard'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Read'));
      await tester.tap(find.widgetWithText(FilledButton, 'Read'));
      await tester.pumpAndSettle();
      expect(find.byType(ReaderScreen), findsOneWidget);
      expect(reader.publication, isNotNull);
      await catalog.signOut();
      await tester.pumpAndSettle();
      expect(find.byType(ReaderScreen), findsNothing);
      expect(reader.publication, isNull);
      expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      reader.dispose();
      downloads.dispose();
      catalog.dispose();
      client.close();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );
}
