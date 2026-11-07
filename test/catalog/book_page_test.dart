import 'package:bookfin/catalog/book_page.dart';
import 'package:bookfin/catalog/controller.dart';
import 'package:bookfin/catalog/jellyfin.dart';
import 'package:bookfin/catalog/layout.dart';
import 'package:bookfin/catalog/library_services.dart';
import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/downloads/downloads.dart';
import 'package:bookfin/foundation/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'controller_test.dart'
    show MemoryCatalogStore, MemoryCredentials, FixtureClient;
import 'layout_test.dart' show MemoryLayoutStore;

void main() {
  late CatalogController catalog;
  late FixtureClient client;
  late StaticDownloads downloads;
  setUp(() async {
    client = FixtureClient(Uri.parse('https://books.example'));
    catalog = CatalogController(
      credentials: MemoryCredentials(),
      store: MemoryCatalogStore(),
      clientFactory: (server, device) => client,
    );
    downloads = StaticDownloads();
  });
  tearDown(() {
    catalog.dispose();
    client.close();
    downloads.dispose();
  });

  Future<void> showBook(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await catalog.connect('https://books.example', 'alice', 'password');
    await catalog.refresh(selected: {'books'});
    await tester.pumpWidget(
      MaterialApp(
        theme: bookfinTheme(Brightness.light),
        home: BookPage(
          services: LibraryServices(
            catalog: catalog,
            layout: LibraryLayout(MemoryLayoutStore()),
            onReaderNightChanged: (_) {},
            downloads: downloads,
          ),
          bookId: catalog.books.single.id,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'removing a download from the book page asks the same question as Downloads',
    (tester) async {
      downloads.state = const EditionDownload(
        phase: DownloadPhase.downloaded,
        bytes: 1000,
        totalBytes: 1000,
        completeFiles: 1,
        totalFiles: 1,
      );
      await showBook(tester);
      await tester.tap(find.byTooltip('Downloaded. Remove download'));
      await tester.pumpAndSettle();
      expect(find.text('Remove download?'), findsOneWidget);
      expect(
        find.text(
          'Remove this edition’s local files and unfinished transfers. Your Jellyfin files will not change.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Remove download'));
      await tester.pumpAndSettle();
      expect(downloads.calls, ['remove']);
    },
  );
}

/// Downloads that report one fixed [state] for every edition and record the
/// changes asked of them.
class StaticDownloads extends Downloads {
  StaticDownloads() : super(MediaPolicy());
  EditionDownload state = const EditionDownload();
  final calls = <String>[];

  @override
  bool get supported => true;
  @override
  Future<void> bind(JellyfinSession? session, List<Book> books) async {}
  @override
  EditionDownload status(Edition edition) => state;
  @override
  Future<void> request(Edition edition) async => calls.add('request');
  @override
  Future<void> cancel(Edition edition) async => calls.add('cancel');
  @override
  Future<void> remove(Edition edition) async => calls.add('remove');
  @override
  Future<Uri?> localFile(SourceFile source) async => null;
  @override
  Future<void> get idle async {}
  @override
  void checkInvariants() {}
}
