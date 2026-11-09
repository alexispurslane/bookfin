import 'package:bookfin/catalog/controller.dart';
import 'package:bookfin/catalog/jellyfin.dart';
import 'package:bookfin/catalog/layout.dart';
import 'package:bookfin/catalog/library_services.dart';
import 'package:bookfin/catalog/library_view.dart' show BookRow;
import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/downloads/downloads.dart';
import 'package:bookfin/downloads/screen.dart';
import 'package:bookfin/foundation/theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../catalog/controller_test.dart'
    show FixtureClient, MemoryCatalogStore, MemoryCredentials;
import '../catalog/layout_test.dart' show MemoryLayoutStore;
import '../catalog/model_test.dart' show entry;
import 'verified_reads.dart';

void main() {
  late FixtureClient client;
  late CatalogController catalog;
  late LibraryLayout layout;
  late _ShownDownloads downloads;
  late Edition first;
  late Edition second;
  setUp(() async {
    client = FixtureClient(Uri.parse('https://books.example'))
      ..entries = [
        entry('one', title: 'First', source: 'one'),
        entry('two', title: 'Second', source: 'two'),
      ];
    catalog = CatalogController(
      credentials: MemoryCredentials(),
      store: MemoryCatalogStore(),
      clientFactory: (server, device) => client,
    );
    await catalog.connect('https://books.example', 'alice', 'password');
    await catalog.refresh();
    Edition edition(String title) => catalog.books
        .singleWhere((book) => book.title == title)
        .editions
        .single;
    first = edition('First');
    second = edition('Second');
    layout = LibraryLayout(MemoryLayoutStore());
    downloads = _ShownDownloads();
  });
  tearDown(() {
    downloads.dispose();
    layout.dispose();
    catalog.dispose();
    client.close();
  });

  Future<void> showTab(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      theme: bookfinTheme(Brightness.light),
      home: Scaffold(
        body: DownloadsTab(
          services: LibraryServices(
            catalog: catalog,
            layout: layout,
            onReaderNightChanged: (_) {},
            downloads: downloads,
          ),
        ),
      ),
    ),
  );

  EditionDownload downloading(int bytes) => EditionDownload(
    phase: DownloadPhase.downloading,
    bytes: bytes,
    totalBytes: 1000,
    totalFiles: 1,
  );
  const downloaded = EditionDownload(
    phase: DownloadPhase.downloaded,
    bytes: 1000,
    totalBytes: 1000,
    completeFiles: 1,
    totalFiles: 1,
  );
  BookRow rowOf(WidgetTester tester, String title) =>
      tester.widget<BookRow>(find.widgetWithText(BookRow, title));

  testWidgets('a byte notice redraws only the row of its edition', (
    tester,
  ) async {
    downloads.states[first.id] = downloading(100);
    downloads.states[second.id] = downloading(200);
    await showTab(tester);
    final summary = tester.widget(find.byType(BookfinPanel));
    final secondRow = rowOf(tester, 'Second');

    downloads.showBytes(first, downloading(500));
    await tester.pump();

    expect(
      find.text('Audiobook · 500 B of 1 KB · 0 of 1 files'),
      findsOneWidget,
    );
    expect(rowOf(tester, 'Second'), same(secondRow));
    expect(tester.widget(find.byType(BookfinPanel)), same(summary));
  });

  testWidgets('a finished download moves to the phone and into the total', (
    tester,
  ) async {
    downloads.states[first.id] = downloading(100);
    await showTab(tester);
    expect(find.text('IN PROGRESS'), findsOneWidget);
    expect(find.text('ON THIS PHONE'), findsNothing);

    downloads.showPhase(first, downloaded);
    await tester.pump();

    expect(find.text('IN PROGRESS'), findsNothing);
    expect(find.text('ON THIS PHONE'), findsOneWidget);
    expect(find.text('saved on this phone · 1 audiobook'), findsOneWidget);
  });

  testWidgets('the trash icon removes an edition only after the tab confirms', (
    tester,
  ) async {
    downloads.states[first.id] = downloaded;
    await showTab(tester);

    await tester.tap(find.byTooltip('Remove download'));
    await tester.pumpAndSettle();
    expect(find.text('Remove download?'), findsOneWidget);
    expect(downloads.calls, isEmpty);
    await tester.tap(find.widgetWithText(TextButton, 'Keep download'));
    await tester.pumpAndSettle();
    expect(downloads.calls, isEmpty);

    await tester.tap(find.byTooltip('Remove download'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove download'));
    await tester.pumpAndSettle();
    expect(downloads.calls, ['remove ${first.id}']);
  });

  testWidgets(
    'mobile data is allowed only after the tab confirms, and the network line follows the policy',
    (tester) async {
      final policy = downloads.policy..network = MediaNetwork.mobile;
      await showTab(tester);
      expect(
        find.text('On mobile data · downloads wait for Wi-Fi'),
        findsOneWidget,
      );

      await tester.tap(find.text('Allow mobile data this session'));
      await tester.pumpAndSettle();
      expect(find.text('Allow mobile data?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Wait for Wi-Fi'));
      await tester.pumpAndSettle();
      expect(policy.mobileAllowed, isFalse);

      await tester.tap(find.text('Allow mobile data this session'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Allow this session'));
      await tester.pumpAndSettle();
      expect(policy.mobileAllowed, isTrue);
      expect(
        find.text('On mobile data · allowed for this session'),
        findsOneWidget,
      );

      await tester.tap(find.text('Use Wi-Fi only'));
      await tester.pumpAndSettle();
      expect(policy.mobileAllowed, isFalse);
      expect(
        find.text('On mobile data · downloads wait for Wi-Fi'),
        findsOneWidget,
      );
    },
  );

  testWidgets('the leftover line shows what Downloads last read', (
    tester,
  ) async {
    downloads.shownLeftovers.value = LeftoverFiles(
      entries: [_leftover('kept', bytes: 2000)],
    );
    await showTab(tester);

    expect(
      find.text('2 KB from books no longer in your library'),
      findsOneWidget,
    );
    expect(downloads.storageReads, 0);

    downloads.shownLeftovers.value = const LeftoverFiles();
    await tester.pump();
    expect(find.text('Leftover files'), findsNothing);
  });

  testWidgets('a failed leftover read offers a retry that asks Downloads', (
    tester,
  ) async {
    downloads.shownLeftovers.value = LeftoverFiles(
      entries: [_leftover('kept')],
      error: StateError('unreadable'),
    );
    await showTab(tester);

    await tester.tap(
      find.text('Cannot check leftover files. Tap to try again.'),
    );
    await tester.pump();
    expect(downloads.leftoverReloads, 1);
  });

  testWidgets(
    'the leftover line opens a page of the leftovers that Downloads read',
    (tester) async {
      downloads.shownLeftovers.value = LeftoverFiles(
        entries: [_leftover('kept')],
      );
      await showTab(tester);

      await tester.tap(find.text('Leftover files'));
      await tester.pumpAndSettle();

      expect(find.text('Source kept:source'), findsOneWidget);
      expect(downloads.storageReads, 0);
      await tester.tap(find.byTooltip('Check again'));
      await tester.pump();
      expect(downloads.leftoverReloads, 1);
    },
  );

  testWidgets('a leftover file is removed only after the page confirms', (
    tester,
  ) async {
    downloads.shownLeftovers.value = LeftoverFiles(
      entries: [_leftover('kept')],
    );
    await tester.pumpWidget(
      MaterialApp(home: LeftoverFilesPage(downloads: downloads)),
    );

    await tester.tap(find.byTooltip('Remove leftover files'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Keep files'));
    await tester.pumpAndSettle();
    expect(downloads.removedLeftovers, isEmpty);

    await tester.tap(find.byTooltip('Remove leftover files'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove files'));
    await tester.pumpAndSettle();
    expect(downloads.removedLeftovers, ['kept']);
  });

  testWidgets('a failed leftover read on the page shows no old entries', (
    tester,
  ) async {
    downloads.shownLeftovers.value = LeftoverFiles(
      entries: [_leftover('kept')],
      error: StateError('unreadable'),
    );
    await tester.pumpWidget(
      MaterialApp(home: LeftoverFilesPage(downloads: downloads)),
    );

    expect(find.textContaining('Cannot read leftover files.'), findsOneWidget);
    expect(find.text('Source kept:source'), findsNothing);
    expect(find.text('Remove all'), findsNothing);
  });

  testWidgets('the book page button follows its edition by itself', (
    tester,
  ) async {
    final actions = <DownloadAction>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DownloadButton(
            downloads: downloads,
            edition: first,
            onAction: actions.add,
          ),
        ),
      ),
    );
    expect(find.byTooltip('Download'), findsOneWidget);

    downloads.showBytes(first, downloading(100));
    await tester.pump();

    expect(find.byTooltip('Cancel download'), findsOneWidget);
    await tester.tap(find.byTooltip('Cancel download'));
    expect(actions, [DownloadAction.cancel]);
    expect(downloads.calls, isEmpty);
  });

  testWidgets('the edition controls follow their edition by themselves', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DownloadControls(
            downloads: downloads,
            edition: first,
            onAction: (_) {},
          ),
        ),
      ),
    );
    expect(find.text('Not downloaded'), findsOneWidget);

    downloads.showBytes(first, downloading(100));
    await tester.pump();

    expect(find.text('Downloading'), findsOneWidget);
    expect(find.text('100 B of 1 KB · 0 of 1 files'), findsOneWidget);
  });
}

RetainedDownload _leftover(String item, {int bytes = 6}) => RetainedDownload(
  accountKey: 'account',
  binding: Object(),
  id: item,
  sourceKey: '$item:source',
  revision: 'revision',
  bytes: bytes,
);

/// Downloads whose state a test sets. [showBytes] notifies like byte
/// progress, and [showPhase] like a phase change.
class _ShownDownloads extends Downloads with VerifiedReads {
  _ShownDownloads() : super(MediaPolicy());
  final states = <String, EditionDownload>{};
  final calls = <String>[];
  final removedLeftovers = <String>[];
  final shownLeftovers = ValueNotifier(const LeftoverFiles());
  final _phases = ChangeNotifier();
  int storageReads = 0;
  int leftoverReloads = 0;

  void showBytes(Edition edition, EditionDownload state) {
    states[edition.id] = state;
    notifyListeners();
  }

  void showPhase(Edition edition, EditionDownload state) {
    showBytes(edition, state);
    _phases.notifyListeners();
  }

  @override
  bool get supported => true;
  @override
  Future<void> bind(JellyfinSession? session, List<Book> books) async {}
  @override
  EditionDownload status(Edition edition) =>
      states[edition.id] ?? const EditionDownload();
  @override
  Future<void> request(Edition edition) async =>
      calls.add('request ${edition.id}');
  @override
  Future<void> cancel(Edition edition) async =>
      calls.add('cancel ${edition.id}');
  @override
  Future<void> remove(Edition edition) async =>
      calls.add('remove ${edition.id}');
  @override
  Listenable get phases => _phases;
  @override
  ValueListenable<LeftoverFiles> get leftovers => shownLeftovers;
  @override
  Future<void> reloadLeftovers() async => leftoverReloads++;
  @override
  Future<List<RetainedDownload>> retainedStorage() async {
    storageReads++;
    return const [];
  }

  @override
  Future<void> removeRetained(RetainedDownload download) async =>
      removedLeftovers.add(download.id);
  @override
  Future<Uri?> localFile(SourceFile source) async => null;
  @override
  Future<void> get idle async {}
  @override
  void checkInvariants() {}

  @override
  void dispose() {
    policy.dispose();
    shownLeftovers.dispose();
    _phases.dispose();
    super.dispose();
  }
}
