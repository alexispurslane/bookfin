import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'package:bookfin/app/account_binding.dart';
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
    show MemoryCredentials, MemoryCatalogStore, pagesOf;
import 'transfer_test.dart' show MediaFixture;

void main() {
  late MediaFixture fixture;
  late Directory root;
  late CatalogController catalog;
  late _CountedLeftovers downloads;
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
    downloads = _CountedLeftovers(
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
  Future<void> show(WidgetTester tester) {
    final binding = AccountBinding(catalog: catalog, downloads: downloads);
    addTearDown(binding.dispose);
    return tester.pumpWidget(
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
  }

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
            body: DownloadsPage(downloads: downloads, books: fixture.books),
          ),
        ),
      ),
    );
    await showDownloads();
    await _settleStorage(tester, downloads);
    expect(find.byTooltip('Remove download'), findsOneWidget);
    expect(
      find.textContaining('6 B saved but unavailable for playback'),
      findsOneWidget,
    );
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Retry download'));
      await downloads.idle;
    });
    await _settleStorage(tester, downloads);
    expect(find.textContaining('Waiting for Wi-Fi'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Cancel download'));
      await downloads.idle;
    });
    await _settleStorage(tester, downloads);
    expect(find.byTooltip('Remove download'), findsOneWidget);
    expect(
      find.textContaining('6 B saved but unavailable for playback'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      downloads.dispose();
      await downloads.idle;
      downloads = _CountedLeftovers(
        root: root,
        freeBytes: () async => 1000000,
        policy: policy,
      );
      await downloads.bind(fixture.session(), fixture.books);
      expect(await saved.exists(), isTrue);
      expect(await downloads.localFile(fixture.text.files.single), isNull);
    });
    await showDownloads();
    await _settleStorage(tester, downloads);
    expect(find.byTooltip('Remove download'), findsOneWidget);
    expect(
      find.textContaining('6 B saved but unavailable for playback'),
      findsOneWidget,
    );
    await tester.runAsync(() => tester.tap(find.byTooltip('Remove download')));
    await tester.pumpAndSettle();
    expect(find.text('Remove download?'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.text('Remove download'));
      await downloads.idle;
      expect(await saved.exists(), isFalse);
    });
    await tester.pumpAndSettle();
    expect(find.byTooltip('Remove download'), findsNothing);
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

  testWidgets('Downloads totals the saved size and names the network', (
    tester,
  ) async {
    final text = catalog.books
        .expand((book) => book.editions)
        .firstWhere((edition) => edition.kind == EditionKind.text);
    await tester.runAsync(() async {
      await downloads.request(text);
      await downloads.idle;
    });
    await show(tester);
    await tester.tap(find.text('Downloads'));
    await tester.pumpAndSettle();
    expect(find.text('6 B'), findsOneWidget);
    expect(find.text('saved on this phone · 1 ebook'), findsOneWidget);
    expect(find.textContaining('Wi-Fi'), findsWidgets);
  });

  testWidgets(
    'a downloaded book opens its details, but its remove button only removes',
    (tester) async {
      final text = catalog.books
          .expand((book) => book.editions)
          .firstWhere((edition) => edition.kind == EditionKind.text);
      await tester.runAsync(() async {
        await downloads.request(text);
        await downloads.idle;
      });
      await show(tester);
      await tester.tap(find.text('Downloads'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Remove download'));
      await tester.pumpAndSettle();
      expect(find.text('Remove download?'), findsOneWidget);
      expect(find.byTooltip('More actions'), findsNothing);
      await tester.tap(find.widgetWithText(TextButton, 'Keep download'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('audio1'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('More actions'), findsOneWidget);
    },
  );

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
    expect(find.text('EPUB · 6 B'), findsOneWidget);
    await tester.runAsync(() => tester.tap(find.byTooltip('Remove download')));
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
      await tester.tap(find.byTooltip('Cancel download'));
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
            body: DownloadsPage(downloads: downloads, books: const []),
          ),
        ),
      ),
    );
    await _settleStorage(tester, downloads);
  }

  Future<void> openLeftovers(WidgetTester tester) async {
    await tester.tap(find.text('Leftover files'));
    await _settleStorage(tester, downloads);
  }

  testWidgets(
    'leftover files show as one summary row that opens their own page',
    (tester) async {
      await showRetained(tester);
      expect(find.text('No downloads yet.'), findsOneWidget);
      expect(find.text('Retained storage'), findsNothing);
      expect(
        find.text('6 B from books no longer in your library'),
        findsOneWidget,
      );
      await openLeftovers(tester);
      expect(find.text('Source text:text'), findsOneWidget);
      expect(find.text('Downloaded'), findsNothing);
      expect(find.text('Download'), findsNothing);
    },
  );

  testWidgets(
    'without leftover files the Downloads page does not mention them',
    (tester) async {
      await tester.runAsync(
        () => tester.pumpWidget(
          MaterialApp(
            theme: bookfinTheme(Brightness.light),
            home: Scaffold(
              body: DownloadsPage(downloads: downloads, books: const []),
            ),
          ),
        ),
      );
      await _settleStorage(tester, downloads);
      expect(find.text('Leftover files'), findsNothing);
      expect(find.textContaining('leftover'), findsNothing);
    },
  );

  testWidgets(
    'leftover removal requires confirmation and Keep preserves files',
    (tester) async {
      await showRetained(tester);
      await openLeftovers(tester);
      await tester.runAsync(
        () => tester.tap(find.byTooltip('Remove leftover files')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Remove leftover files?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Keep files'));
      await tester.pumpAndSettle();
      expect(await tester.runAsync(downloads.retainedStorage), hasLength(1));
      await tester.runAsync(
        () => tester.tap(find.byTooltip('Remove leftover files')),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(FilledButton, 'Remove files'));
        await downloads.idle;
      });
      await _settleStorage(tester, downloads);
      expect(await tester.runAsync(downloads.retainedStorage), isEmpty);
      expect(find.text('No leftover files.'), findsOneWidget);
      await tester.pageBack();
      await _settleStorage(tester, downloads);
      expect(find.text('Leftover files'), findsNothing);
    },
  );

  testWidgets('remove all clears every removable leftover file', (
    tester,
  ) async {
    await showRetained(tester);
    await openLeftovers(tester);
    await tester.runAsync(() => tester.tap(find.text('Remove all')));
    await tester.pumpAndSettle();
    expect(find.text('Remove all leftover files?'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Remove files'));
      await downloads.idle;
    });
    await _settleStorage(tester, downloads);
    expect(await tester.runAsync(downloads.retainedStorage), isEmpty);
  });

  testWidgets('switching accounts clears the previously displayed inventory', (
    tester,
  ) async {
    await showRetained(tester);
    expect(find.text('Leftover files'), findsOneWidget);
    await tester.runAsync(
      () => downloads.bind(fixture.session(user: 'bob'), []),
    );
    await _settleStorage(tester, downloads);
    expect(find.text('Leftover files'), findsNothing);
  });

  testWidgets('byte progress alone does not reread leftover files', (
    tester,
  ) async {
    var notifications = 0;
    await tester.runAsync(() async {
      downloads.dispose();
      await downloads.idle;
      fixture.payload = Uint8List(12 << 20);
      fixture.pieceBytes = 48 << 10;
      var now = DateTime(2026);
      downloads = _CountedLeftovers(
        root: root,
        freeBytes: () async => 64 << 20,
        policy: policy,
        clock: () => now = now.add(const Duration(seconds: 1)),
      );
      await downloads.bind(fixture.session(), fixture.books);
      await tester.pumpWidget(
        MaterialApp(home: LeftoverFilesPage(downloads: downloads)),
      );
    });
    await _settleStorage(tester, downloads);
    final before = downloads.reads;
    downloads.watch(fixture.text).addListener(() => notifications++);
    await tester.runAsync(() async {
      await downloads.request(fixture.text);
      await downloads.idle;
    });
    await _settleStorage(tester, downloads);
    expect(downloads.status(fixture.text).phase, DownloadPhase.downloaded);
    expect(notifications, greaterThan(20));
    expect(downloads.reads - before, lessThanOrEqualTo(3));
  });

  testWidgets(
    'opening the Downloads tab again shows the leftovers without a new storage read',
    (tester) async {
      await tester.runAsync(() async {
        final text = catalog.books
            .expand((book) => book.editions)
            .firstWhere((edition) => edition.kind == EditionKind.text);
        await downloads.request(text);
        await downloads.idle;
        await show(tester);
        await catalog.refresh(selected: {});
        await downloads.idle;
        await tester.tap(find.text('Downloads'));
      });
      await _settleStorage(tester, downloads);
      expect(find.text('Leftover files'), findsOneWidget);
      final reads = downloads.reads;

      await tester.tap(find.text('Settings'));
      await _settleStorage(tester, downloads);
      await tester.tap(find.text('Downloads'));
      await _settleStorage(tester, downloads);

      expect(find.text('Leftover files'), findsOneWidget);
      expect(downloads.reads, reads);
    },
  );

  testWidgets('unreadable identities have no removal action', (tester) async {
    await showRetained(tester);
    await openLeftovers(tester);
    await tester.runAsync(() async {
      final records = await root
          .list(recursive: true)
          .where(
            (entry) => entry is File && entry.path.endsWith('/record.json'),
          )
          .toList();
      await File(records.single.path).writeAsString('unreadable');
      await tester.tap(find.byTooltip('Check again'));
    });
    await _settleStorage(tester, downloads);
    expect(find.text('Unidentified files'), findsOneWidget);
    expect(find.text('6 B'), findsOneWidget);
    expect(find.byTooltip('Remove leftover files'), findsNothing);
  });

  testWidgets(
    'unavailable private storage shows an error without exposing old entries',
    (tester) async {
      await showRetained(tester);
      await openLeftovers(tester);
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
        await tester.tap(find.byTooltip('Check again'));
      });
      await _settleStorage(tester, downloads);
      expect(downloads.leftovers.value.error, isStateError);
      expect(find.text('Source text:text'), findsNothing);
      expect(find.byTooltip('Remove leftover files'), findsNothing);
      expect(
        find.textContaining('Cannot read leftover files.'),
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
      await _settleStorage(tester, downloads);
      expect(catalog.books, isEmpty);
      expect(find.text('Leftover files'), findsOneWidget);
      await tester.runAsync(() async {
        await catalog.refresh(selected: {'books'});
        await downloads.idle;
      });
      await _settleStorage(tester, downloads);
      expect(find.text('Leftover files'), findsNothing);
      expect(downloads.status(text).phase, DownloadPhase.downloaded);
      expect(fixture.mediaRequests, ['text']);
    },
  );
}

/// Waits until [downloads] ends its transfers and leftover reads, and no
/// read starts after the last one.
Future<void> _settleStorage(
  WidgetTester tester,
  _CountedLeftovers downloads,
) async {
  // Frames built in real time let a shown inventory start its read there,
  // so the read can finish.
  await tester.runAsync(() async {
    int reads;
    do {
      reads = downloads.reads;
      await tester.pump();
      await downloads.idle;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await downloads.lastRead;
    } while (reads != downloads.reads);
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
  Future<CatalogPages> catalog(
    JellyfinSession session,
    Set<String> selected,
  ) async => pagesOf([
    if (selected.contains('books'))
      for (final id in ['audio1', 'audio2', 'text'])
        CatalogEntry.fromJson(fixture.dto(id), libraryId: 'books'),
  ]);
}

class _CountedLeftovers extends LocalDownloads {
  _CountedLeftovers({
    required super.root,
    required super.freeBytes,
    required super.policy,
    super.clock,
  });
  int reads = 0;

  /// Ends when the last storage read ends, whether it failed or not.
  Future<void> lastRead = Future.value();
  @override
  Future<List<RetainedDownload>> retainedStorage() {
    reads++;
    final read = super.retainedStorage();
    lastRead = read.then((_) {}, onError: (Object _) {});
    return read;
  }
}

class _RealHttp extends HttpOverrides {}
