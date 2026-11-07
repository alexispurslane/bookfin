import 'package:bookfin/catalog/book_page.dart';
import 'package:bookfin/catalog/controller.dart';
import 'package:bookfin/catalog/jellyfin.dart';
import 'package:bookfin/catalog/layout.dart';
import 'package:bookfin/catalog/library_services.dart';
import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/downloads/downloads.dart';
import 'package:bookfin/downloads/screen.dart';
import 'package:bookfin/foundation/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'controller_test.dart'
    show MemoryCatalogStore, MemoryCredentials, FixtureClient;
import 'layout_test.dart' show MemoryLayoutStore;
import 'model_test.dart' show entry;

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

  testWidgets(
    'a partial download offers Retry and Remove on the book page and in Downloads',
    (tester) async {
      downloads.state = const EditionDownload(
        phase: DownloadPhase.partial,
        bytes: 400,
        totalBytes: 1000,
        totalFiles: 1,
      );
      await showBook(tester);
      // The main download button retries, as everywhere else.
      expect(find.byTooltip('Retry download'), findsOneWidget);
      expect(find.byTooltip('Download'), findsNothing);
      // The edition's own controls.
      expect(find.widgetWithText(OutlinedButton, 'Retry'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Remove'), findsOneWidget);

      await tester.pumpWidget(
        MaterialApp(
          theme: bookfinTheme(Brightness.light),
          home: Scaffold(
            body: DownloadsPage(downloads: downloads, books: catalog.books),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Retry download'), findsOneWidget);
      expect(find.byTooltip('Remove download'), findsOneWidget);
      expect(find.byTooltip('Download'), findsNothing);
    },
  );

  testWidgets('a failed download retries from the book page button', (
    tester,
  ) async {
    downloads.state = const EditionDownload(
      phase: DownloadPhase.failed,
      totalFiles: 1,
    );
    await showBook(tester);
    await tester.tap(find.byTooltip('Download failed. Retry download'));
    await tester.pumpAndSettle();
    expect(downloads.calls, ['request']);
    expect(find.widgetWithText(TextButton, 'Remove'), findsOneWidget);
  });

  testWidgets('a chapter an hour in reads as hours, minutes and seconds', (
    tester,
  ) async {
    const twoHours = 72000000000;
    client.entries = [
      entry(
        'one',
        fields: {
          'RunTimeTicks': twoHours,
          'MediaSources': [
            {
              'Id': 'source',
              'Container': 'm4b',
              'Size': 1000,
              'RunTimeTicks': twoHours,
            },
          ],
          'Chapters': [
            {'Name': 'Opening', 'StartPositionTicks': 0},
            {'Name': 'Night falls', 'StartPositionTicks': 39000000000},
          ],
        },
      ),
    ];
    await showBook(tester);
    await tester.scrollUntilVisible(find.byType(ExpansionTile), 200);
    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Night falls'),
        matching: find.text('1:05:00'),
      ),
      findsOneWidget,
    );
  });
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
