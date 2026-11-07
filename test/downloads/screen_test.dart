import 'dart:io';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:bookfin/catalog/controller.dart';
import 'package:bookfin/catalog/jellyfin.dart';
import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/catalog/screen.dart';
import 'package:bookfin/downloads/downloads.dart';
import 'package:bookfin/downloads/local_downloads.dart';
import 'package:bookfin/downloads/screen.dart';
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
        onReaderNightChanged: (_) {},
      ),
    ),
  );

  testWidgets('rejected saved recordings stay discoverable and removable', (
    tester,
  ) async {
    late File saved;
    await tester.runAsync(() async {
      policy.network = MediaNetwork.disconnected;
      fixture.textSources = [fixture.source('alternate-text')];
      final source = fixture.text.files.single;
      String hash(String value) =>
          sha256.convert(utf8.encode(value)).toString();
      final directory = Directory(
        '${root.path}/${hash(fixture.session().scope.key)}/${hash(jsonEncode([source.key, source.revision]))}',
      );
      await directory.create(recursive: true);
      saved = File('${directory.path}/complete');
      await saved.writeAsBytes([1, 2, 3, 4, 5, 6]);
      await File('${directory.path}/record.json').writeAsString(
        jsonEncode({
          'key': source.key,
          'revision': source.revision,
          'length': 6,
          'digest': sha256.convert([1, 2, 3, 4, 5, 6]).toString(),
          'complete': true,
          'requested': false,
        }),
      );
      await downloads.bind(fixture.session(), fixture.books);
    });
    Future<void> showDownloads() => tester.runAsync(
      () => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnimatedBuilder(
              animation: downloads,
              builder: (_, _) =>
                  DownloadsPage(downloads: downloads, books: fixture.books),
            ),
          ),
        ),
      ),
    );
    await showDownloads();
    await settleStorage(tester);
    expect(find.text('Remove'), findsOneWidget);
    expect(find.text('6 B saved but unavailable for playback'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.text('Retry'));
      await downloads.idle;
    });
    await settleStorage(tester);
    expect(find.text('Waiting for Wi-Fi'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.text('Cancel'));
      await downloads.idle;
    });
    await settleStorage(tester);
    expect(find.text('Remove'), findsOneWidget);
    expect(find.text('6 B saved but unavailable for playback'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      downloads.dispose();
      await downloads.idle;
      downloads = LocalDownloads(
        root: root,
        freeBytes: () async => 1000000,
        policy: policy,
      );
      await downloads.bind(fixture.session(), fixture.books);
      expect(await saved.exists(), isTrue);
      expect(await downloads.localFile(fixture.text.files.single), isNull);
    });
    await showDownloads();
    await settleStorage(tester);
    expect(find.text('Remove'), findsOneWidget);
    expect(find.text('6 B saved but unavailable for playback'), findsOneWidget);
    await tester.runAsync(() => tester.tap(find.text('Remove')));
    await tester.pumpAndSettle();
    expect(find.text('Remove download?'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.text('Remove download'));
      await downloads.idle;
      expect(await saved.exists(), isFalse);
    });
    await tester.pumpAndSettle();
    expect(find.text('Remove'), findsNothing);
  });

  testWidgets('a book with audio shows as downloaded only when its audio is', (
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
    expect(find.text('audio1'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Downloaded'));
    await tester.pumpAndSettle();
    expect(find.text('audio1'), findsNothing);
    expect(find.text('No downloaded books yet.'), findsOneWidget);
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
    expect(find.text('6 B of 6 B · 1 of 1 files'), findsOneWidget);
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
    await tester.scrollUntilVisible(find.text('Audiobook'), 300);
    await tester.ensureVisible(
      find.widgetWithText(OutlinedButton, 'Download').first,
    );
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

  Future<void> showRetained(WidgetTester tester) async {
    await tester.runAsync(() async {
      final text = catalog.books
          .expand((book) => book.editions)
          .firstWhere((edition) => edition.kind == EditionKind.text);
      await downloads.request(text);
      await downloads.idle;
      await downloads.bind(catalog.session, []);
    });
    await tester.runAsync(
      () => tester.pumpWidget(
        MaterialApp(
          theme: bookfinTheme(Brightness.light),
          home: Scaffold(
            body: ListenableBuilder(
              listenable: downloads,
              builder: (context, child) =>
                  DownloadsPage(downloads: downloads, books: const []),
            ),
          ),
        ),
      ),
    );
    await settleStorage(tester);
  }

  testWidgets('retained files are separate from active edition availability', (
    tester,
  ) async {
    await showRetained(tester);
    expect(find.text('No downloads yet.'), findsOneWidget);
    expect(find.text('Retained storage'), findsOneWidget);
    expect(find.text('6 bytes'), findsOneWidget);
    expect(find.text('Downloaded'), findsNothing);
    expect(find.text('Download'), findsNothing);
  });

  testWidgets(
    'retained removal requires confirmation and Keep preserves files',
    (tester) async {
      await showRetained(tester);
      await tester.runAsync(
        () => tester.tap(
          find.widgetWithText(TextButton, 'Remove retained files'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Remove retained files?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Keep files'));
      await tester.pumpAndSettle();
      expect(await tester.runAsync(downloads.retainedStorage), hasLength(1));
      await tester.runAsync(
        () => tester.tap(
          find.widgetWithText(TextButton, 'Remove retained files'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(FilledButton, 'Remove files'));
        await downloads.idle;
      });
      await settleStorage(tester);
      expect(await tester.runAsync(downloads.retainedStorage), isEmpty);
      expect(find.text('No retained files.'), findsOneWidget);
    },
  );

  testWidgets('switching accounts clears the previously displayed inventory', (
    tester,
  ) async {
    await showRetained(tester);
    expect(find.text('Source text:text'), findsOneWidget);
    await tester.runAsync(
      () => downloads.bind(fixture.session(user: 'bob'), []),
    );
    await settleStorage(tester);
    expect(find.text('Source text:text'), findsNothing);
    expect(find.text('No retained files.'), findsOneWidget);
  });

  testWidgets('unreadable identities have no removal action', (tester) async {
    await showRetained(tester);
    await tester.runAsync(() async {
      final records = await root
          .list(recursive: true)
          .where(
            (entry) => entry is File && entry.path.endsWith('/record.json'),
          )
          .toList();
      await File(records.single.path).writeAsString('unreadable');
      await tester.tap(find.text('Refresh storage'));
    });
    await settleStorage(tester);
    expect(find.text('Unidentified stored files'), findsOneWidget);
    expect(find.text('6 bytes'), findsOneWidget);
    expect(find.text('Remove retained files'), findsNothing);
  });

  testWidgets(
    'unavailable private storage shows an error without exposing old entries',
    (tester) async {
      await showRetained(tester);
      await tester.runAsync(() async {
        final records = await root
            .list(recursive: true)
            .where(
              (entry) => entry is File && entry.path.endsWith('/record.json'),
            )
            .toList();
        final account = File(records.single.path).parent.parent;
        await account.rename('${root.path}/preserved-account');
        await File(account.path).writeAsString('not a directory');
        await tester.tap(find.text('Refresh storage'));
      });
      await tester.pump();
      final view = tester.widget<FutureBuilder<List<RetainedDownload>>>(
        find.byType(FutureBuilder<List<RetainedDownload>>),
      );
      await tester.runAsync(() => expectLater(view.future, throwsStateError));
      await tester.pumpAndSettle();
      expect(find.text('Source text:text'), findsNothing);
      expect(find.text('Remove retained files'), findsNothing);
      expect(
        find.textContaining('Cannot read retained storage.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'deselected libraries move files out of the catalog and reselection restores them',
    (tester) async {
      final text = catalog.books
          .expand((book) => book.editions)
          .firstWhere((edition) => edition.kind == EditionKind.text);
      await tester.runAsync(() async {
        await downloads.request(text);
        await downloads.idle;
        await show(tester);
        await catalog.refresh(selected: {});
        await downloads.idle;
        await tester.tap(find.text('Downloads'));
        await tester.pump();
      });
      await settleStorage(tester);
      expect(catalog.books, isEmpty);
      expect(find.text('Source text:text'), findsOneWidget);
      await tester.runAsync(() async {
        await catalog.refresh(selected: {'books'});
        await downloads.idle;
      });
      await settleStorage(tester);
      expect(find.text('Source text:text'), findsNothing);
      expect(find.text('No retained files.'), findsOneWidget);
      expect(downloads.status(text).phase, DownloadPhase.downloaded);
      expect(fixture.mediaRequests, ['text']);
    },
  );
}

Future<void> settleStorage(WidgetTester tester) async {
  await tester.pump();
  final view = tester.widget<FutureBuilder<List<RetainedDownload>>>(
    find.byType(FutureBuilder<List<RetainedDownload>>),
  );
  await tester.runAsync(() async {
    await view.future;
  });
  await tester.pumpAndSettle();
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
    if (selected.contains('books'))
      for (final id in ['audio1', 'audio2', 'text'])
        CatalogEntry.fromJson(fixture.dto(id), libraryId: 'books'),
  ];
}

class _RealHttp extends HttpOverrides {}
