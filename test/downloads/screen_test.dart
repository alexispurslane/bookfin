import 'dart:io';

import 'package:bookfin/catalog/controller.dart';
import 'package:bookfin/catalog/jellyfin.dart';
import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/catalog/screen.dart';
import 'package:bookfin/downloads/downloads.dart';
import 'package:bookfin/downloads/local_downloads.dart';
import 'package:bookfin/foundation/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../catalog/controller_test.dart'
    show MemoryCredentials, MemoryCatalogStore;
import 'transfer_test.dart' show MediaFixture;

void main() {
  late MediaFixture fixture;
  late Directory root;
  late CatalogController catalog;
  late LocalDownloads downloads;
  late MediaPolicy policy;
  setUp(() async {
    HttpOverrides.global = _RealHttp();
    fixture = await MediaFixture.start();
    root = await Directory.systemTemp.createTemp('bookfin-download-widget-');
    catalog = CatalogController(
      credentials: MemoryCredentials(),
      store: MemoryCatalogStore(),
      clientFactory: (_, _) => _CatalogFixture(fixture),
    );
    await catalog.connect(fixture.uri.toString(), 'alice', 'unused');
    await catalog.refresh(selected: {'books'});
    await catalog.linkBooks('book:text', 'book:audio1');
    policy = MediaPolicy()..network = MediaNetwork.wifi;
    downloads = LocalDownloads(
      root: root,
      freeBytes: () async => 1000000,
      policy: policy,
    );
    await downloads.bind(catalog.session, catalog.books);
  });
  tearDown(() async {
    downloads.dispose();
    await downloads.idle;
    catalog.dispose();
    policy.dispose();
    await fixture.close();
    await root.delete(recursive: true);
  });
  Future<void> show(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      theme: bookfinTheme(Brightness.light),
      home: CatalogHome(
        catalog: catalog,
        downloads: downloads,
        onAppearance: () {},
      ),
    ),
  );

  testWidgets('the book list separates audio and ebook availability', (
    tester,
  ) async {
    final text = catalog.books
        .expand((book) => book.editions)
        .firstWhere((edition) => edition.kind == EditionKind.text);
    await tester.runAsync(() async {
      await downloads.request(text);
      await downloads.idle;
    });
    expect(downloads.status(text).phase, DownloadPhase.downloaded);
    await show(tester);
    expect(find.text('Audio · Not downloaded'), findsNWidgets(2));
    expect(find.text('Ebook · Downloaded'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Downloaded'));
    await tester.pumpAndSettle();
    expect(find.text('audio1'), findsNothing);
    expect(find.text('No books found.'), findsOneWidget);
  });

  testWidgets('Downloads lists real status and removes a verified local copy', (
    tester,
  ) async {
    final text = catalog.books
        .expand((book) => book.editions)
        .firstWhere((edition) => edition.kind == EditionKind.text);
    await tester.runAsync(() async {
      await downloads.request(text);
      await downloads.idle;
    });
    expect(downloads.status(text).phase, DownloadPhase.downloaded);
    await show(tester);
    await tester.tap(find.text('Downloads'));
    await tester.pumpAndSettle();
    expect(find.text('6 / 6 bytes · 1 / 1 files'), findsOneWidget);
    await tester.runAsync(
      () => tester.tap(find.widgetWithText(TextButton, 'Remove')),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Remove download'));
      await downloads.idle;
    });
    await tester.pumpAndSettle();
    expect(downloads.status(text).phase, DownloadPhase.none);
    expect(find.text('No downloads yet.'), findsOneWidget);
    expect(
      await tester.runAsync(() => downloads.localFile(text.files.single)),
      isNull,
    );
  });

  testWidgets('book details queue an edition and Downloads can cancel it', (
    tester,
  ) async {
    policy.network = MediaNetwork.unknown;
    await show(tester);
    await tester.tap(find.text('audio1'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(OutlinedButton, 'Download').first);
      await downloads.idle;
    });
    await tester.pumpAndSettle();
    expect(find.text('Waiting for Wi-Fi'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Downloads'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await downloads.idle;
    });
    await tester.pumpAndSettle();
    expect(find.text('No downloads yet.'), findsOneWidget);
    expect(fixture.mediaRequests, isEmpty);
  });
}

class _CatalogFixture extends JellyfinClient {
  _CatalogFixture(this.fixture) : super(fixture.uri, deviceId: 'fixture');
  final MediaFixture fixture;
  @override
  Future<JellyfinSession> signIn(String username, String password) async =>
      fixture.session();
  @override
  Future<JellyfinSession> validate(JellyfinSession session) async => session;
  @override
  Future<List<BookLibrary>> libraries(JellyfinSession session) async => [
    const BookLibrary('books', 'Books'),
  ];
  @override
  Future<List<CatalogEntry>> catalog(
    JellyfinSession session,
    Set<String> selected,
  ) async => [
    for (final id in ['audio1', 'audio2', 'text'])
      CatalogEntry.fromJson(fixture.dto(id), libraryId: 'books'),
  ];
}

class _RealHttp extends HttpOverrides {}
