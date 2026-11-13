import 'package:bookfin/appearance/preferences.dart';
import 'package:bookfin/catalog/controller.dart';
import 'package:bookfin/catalog/glass.dart';
import 'package:bookfin/main.dart';
import 'package:bookfin/playback/native.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:bookfin/playback/record_codec.dart';
import 'package:bookfin/playback/screen.dart';
import 'package:bookfin/playback/store.dart';
import 'package:bookfin/sync/journal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../appearance/preferences_test.dart' show MemoryAppearanceStore;
import '../catalog/controller_test.dart'
    show FixtureClient, MemoryCatalogStore, MemoryCredentials;
import '../playback/playback_test.dart' show LocalFiles, TestEngine;
import '../real_time.dart';

class _Store extends LocalResumeStore {
  bool fail = false;
  @override
  Future<void> save(String account, ListeningChanges changes) {
    if (fail) throw Exception('disk full');
    return super.save(account, changes);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CatalogController catalog;
  late FixtureClient client;
  late Playback player;
  late TestEngine engine;
  late _Store store;
  late LocalFiles downloads;
  late AppearanceController appearance;
  late RecordJournal remote;

  Future<void> receive(WidgetTester tester, int milliseconds) async {
    final edition = player.edition!;
    final file = edition.files.single;
    remote.change(resumeRecordAddress(edition), {
      'edition': edition.id,
      'source': file.key,
      'revision': file.revision,
      'sources': editionSources(edition),
      'milliseconds': milliseconds,
      'pendingOffline': false,
    }, device: 'Other phone');
    await finish(
      tester,
      store.receivePage(catalog.session!.scope.key, remote.uploads, 0),
    );
    await finish(tester, player.refreshPersonalRecords());
  }

  Future<void> show(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    client = FixtureClient(Uri.parse('https://books.example'));
    catalog = CatalogController(
      credentials: MemoryCredentials(),
      store: MemoryCatalogStore(),
      clientFactory: (_, _) => client,
    );
    await finish(
      tester,
      catalog.connect('https://books.example', 'alice', 'password'),
    );
    await finish(tester, catalog.refresh());
    store = _Store();
    engine = TestEngine();
    downloads = LocalFiles();
    final book = catalog.books.single;
    final edition = book.editions.single;
    downloads.files[edition.files.single.key] = Uri.file('/local.m4b');
    player = Playback(downloads: downloads, engine: engine, store: store);
    appearance = AppearanceController(MemoryAppearanceStore());
    await tester.pumpWidget(
      BookfinApp(
        catalog: catalog,
        playback: player,
        downloads: downloads,
        appearance: appearance,
      ),
    );
    await finish(tester, player.open(book, edition, autoplay: false));
    await finish(tester, player.seekEdition(11000));
    await finish(tester, player.flush());
    remote = RecordJournal(catalog.session!.scope.key, 'remote');
    remote.receive(
      await tester.runAsync(
            () => store.pendingUploads(catalog.session!.scope.key),
          ) ??
          [],
    );
    await receive(tester, 40000);
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    store.fail = false;
    await tester.pumpWidget(const SizedBox());
    await finish(tester, player.close());
    downloads.dispose();
    catalog.dispose();
    appearance.dispose();
    client.close();
  }

  for (final surface in [
    'mini player',
    'full player',
    'book page',
    'reader cover',
  ]) {
    testWidgets('$surface Play presents one glass choice before sound', (
      tester,
    ) async {
      await show(tester);
      try {
        if (surface == 'full player') {
          await tester.tap(find.text('Listening'));
        } else if (surface == 'book page') {
          await tester.tap(find.text('The Orchard').first);
        } else if (surface == 'reader cover') {
          final navigator = tester.state<NavigatorState>(
            find.byType(Navigator).first,
          );
          navigator.push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  Scaffold(body: PlaybackCoverButton(playback: player)),
            ),
          );
        }
        await tester.pumpAndSettle();
        await tester.tap(
          surface == 'book page'
              ? find.text('Resume')
              : surface == 'reader cover'
              ? find.byType(CoverPlayButton)
              : find.byTooltip('Play').first,
        );
        await runUntil(tester, () => player.playChoiceNotifier.value != null);
        await tester.pumpAndSettle();
        expect(engine.playCount, 0);
        expect(find.text('Where would you like to listen?'), findsOneWidget);
        expect(
          find.ancestor(
            of: find.text('Where would you like to listen?'),
            matching: find.byType(CoverGlass),
          ),
          findsOneWidget,
        );
        await tester.tap(find.text('Other phone · 0:40'));
        await runUntil(tester, () => player.playing);
        expect(player.position!.milliseconds, 40000);
        expect(player.undoAction?.before.milliseconds, 11000);
      } finally {
        await close(tester);
      }
    });
  }

  testWidgets(
    'external Play starts in the background and asks once when the app resumes',
    (tester) async {
      await show(tester);
      try {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await finish(tester, (PlaybackHandler()..attach(player)).play());
        await tester.pumpAndSettle();
        expect(player.playing, isTrue);
        expect(player.position!.milliseconds, 11000);
        expect(find.text('Where would you like to listen?'), findsNothing);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(find.text('Where would you like to listen?'), findsOneWidget);
        await tester.tap(find.text('This phone · 0:11'));
        await runUntil(tester, () => player.playChoiceNotifier.value == null);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(find.text('Where would you like to listen?'), findsNothing);
        expect(player.position!.milliseconds, 11000);
      } finally {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await close(tester);
      }
    },
  );

  testWidgets(
    'dismissing the in-app choice does not start and a later tap asks again',
    (tester) async {
      await show(tester);
      try {
        await tester.tap(find.byTooltip('Play'));
        await runUntil(tester, () => player.playChoiceNotifier.value != null);
        await tester.pumpAndSettle();
        await tester.tapAt(const Offset(8, 8));
        await tester.pumpAndSettle();
        expect(player.playing, isFalse);
        expect(player.playChoiceNotifier.value, isNull);
        await tester.tap(find.byTooltip('Play'));
        await runUntil(tester, () => player.playChoiceNotifier.value != null);
        await tester.pumpAndSettle();
        expect(find.text('Where would you like to listen?'), findsOneWidget);
      } finally {
        await close(tester);
      }
    },
  );

  testWidgets('Play can ask again after saving an answer failed', (
    tester,
  ) async {
    await show(tester);
    try {
      await tester.tap(find.byTooltip('Play'));
      await runUntil(tester, () => player.playChoiceNotifier.value != null);
      await tester.pumpAndSettle();
      store.fail = true;
      await tester.tap(find.text('This phone · 0:11'));
      await runUntil(tester, () => player.saveFailed);
      await tester.pumpAndSettle();
      expect(player.playing, isFalse);
      store.fail = false;
      await tester.tap(find.byTooltip('Play'));
      await tester.pumpAndSettle();
      expect(find.text('Where would you like to listen?'), findsOneWidget);
    } finally {
      await close(tester);
    }
  });

  testWidgets(
    'an answer made stale by sync cannot start at the old remote place',
    (tester) async {
      await show(tester);
      try {
        await tester.tap(find.byTooltip('Play'));
        await runUntil(tester, () => player.playChoiceNotifier.value != null);
        await tester.pumpAndSettle();
        await receive(tester, 50000);
        await tester.tap(find.text('Other phone · 0:40'));
        await tester.pumpAndSettle();
        expect(engine.playCount, 0);
        expect(find.text('Other phone · 0:50'), findsOneWidget);
      } finally {
        await close(tester);
      }
    },
  );
}
