import 'package:bookfin/appearance/appearance.dart';
import 'package:bookfin/appearance/preferences.dart';
import 'package:bookfin/catalog/controller.dart';
import 'package:bookfin/main.dart';
import 'package:bookfin/reader/screen.dart';
import 'package:bookfin/reader/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_epub_viewer/publication.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../catalog/controller_test.dart'
    show FixtureClient, MemoryCredentials, MemoryCatalogStore;
import '../catalog/model_test.dart' show entry;
import '../playback/playback_test.dart' show LocalFiles, MemoryResume;
import 'appearance_test.dart' show BridgePlatform, finishLoading;
import 'publication_test.dart' show epub;
import 'session_test.dart' show visible;

class ReadingApp {
  final platform = BridgePlatform();
  final client = FixtureClient(Uri.parse('https://books.example'));
  final downloads = LocalFiles();
  final records = MemoryResume();
  final publication = Publication.admit(epub());
  late final catalog = CatalogController(
    credentials: MemoryCredentials(),
    store: MemoryCatalogStore(),
    clientFactory: (server, device) => client,
  );
  AppearanceController appearance = AppearanceController(
    LocalAppearanceStore(),
  );
  late ReaderSession reader = newReader();

  ReaderSession newReader() => ReaderSession(
    downloads: downloads,
    store: records,
    load: (_) async => publication,
  );

  Widget build() => BookfinApp(
    appearance: appearance,
    catalog: catalog,
    downloads: downloads,
    reader: reader,
    clock: () => DateTime.utc(2026, 11, 2, 12),
  );

  Future<void> prepare(WidgetTester tester, AppearanceMode mode) async {
    final previous = InAppWebViewPlatform.instance;
    InAppWebViewPlatform.instance = platform;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      reader.dispose();
      appearance.dispose();
      downloads.dispose();
      catalog.dispose();
      client.close();
      if (previous != null) InAppWebViewPlatform.instance = previous;
    });
    await appearance.selectMode(mode);
    client.entries = [entry('ebook', type: 'Book', container: 'epub')];
    await catalog.connect('https://books.example', 'alice', 'fixture-password');
    await catalog.refresh(selected: {'books'});
    downloads.files[catalog.books.single.editions.single.files.single.key] =
        Uri.file('/verified.epub');
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();
    await tester.tap(find.text('The Orchard'));
    await tester.pumpAndSettle();
    await openReader(tester);
  }

  Future<void> openReader(WidgetTester tester) async {
    final read = find.widgetWithText(FilledButton, 'Read');
    await tester.ensureVisible(read);
    await tester.tap(read);
    await tester.pumpAndSettle();
    await finishLoading(tester);
    expect(reader.ready, isTrue);
  }

  Future<void> leaveReader(WidgetTester tester) async {
    Navigator.of(tester.element(find.byType(ReaderScreen))).pop();
    await tester.pumpAndSettle();
    await reader.flush();
    expect(find.byType(ReaderScreen), findsNothing);
  }
}

Brightness screenBrightness(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(Scaffold).last)).brightness;

void main() {
  setUp(() {
    final previous = SharedPreferencesAsyncPlatform.instance;
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    addTearDown(() => SharedPreferencesAsyncPlatform.instance = previous);
  });

  for (final choice in [
    (
      start: AppearanceMode.day,
      mode: AppearanceMode.night,
      tooltip: 'Night reading theme',
      brightness: Brightness.dark,
      night: true,
    ),
    (
      start: AppearanceMode.night,
      mode: AppearanceMode.day,
      tooltip: 'Cream reading theme',
      brightness: Brightness.light,
      night: false,
    ),
  ]) {
    testWidgets(
      'reader ${choice.mode.name} changes the app and survives reopen and controller restart',
      (tester) async {
        final app = ReadingApp();
        await app.prepare(tester, choice.start);
        await app.appearance.selectLocation(
          SelectedLocation('Tokyo', 35.6762, 139.6503),
        );
        await tester.pumpAndSettle();
        final bridge = app.platform.controllers.single;
        bridge.handlers['readerLocation']!([visible.toJson()]);
        await app.reader.addBookmark(title: 'A saved river');
        await tester.tap(find.byTooltip('Larger text'));
        await tester.pumpAndSettle();
        final anchor = app.reader.position!.anchor;
        bridge.calls.clear();
        await tester.tap(find.byTooltip(choice.tooltip));
        await tester.pumpAndSettle();
        expect(app.appearance.settings.mode, choice.mode);
        expect(app.appearance.saveState, PreferenceSaveState.saved);
        expect(screenBrightness(tester), choice.brightness);
        expect(bridge.calls.map((call) => call.arguments).toList(), [
          {'argument0': 22.0, 'argument1': choice.night},
        ]);
        expect(app.reader.position!.anchor, anchor);
        await app.leaveReader(tester);
        expect(screenBrightness(tester), choice.brightness);
        await app.openReader(tester);
        final reopened =
            app.platform.controllers.last.calls.single.arguments['argument0']
                as Map;
        expect(reopened['night'], choice.night);
        expect(reopened['fontSize'], 22);
        expect((reopened['initial'] as Map)['cfi'], visible.cfi);
        expect(app.reader.bookmarks.single.title, 'A saved river');
        await tester.pumpWidget(const SizedBox());
        app.reader.dispose();
        await app.reader.flush();
        app.appearance.dispose();
        app.appearance = AppearanceController(LocalAppearanceStore());
        await app.appearance.restore();
        expect(app.appearance.settings.mode, choice.mode);
        expect(app.appearance.settings.location?.name, 'Tokyo');
        app.reader = app.newReader();
        await tester.pumpWidget(app.build());
        await tester.pumpAndSettle();
        expect(screenBrightness(tester), choice.brightness);
        await tester.tap(find.text('The Orchard'));
        await tester.pumpAndSettle();
        await app.openReader(tester);
        final restarted =
            app.platform.controllers.last.calls.single.arguments['argument0']
                as Map;
        expect(restarted['night'], choice.night);
        expect(restarted['fontSize'], 22);
        expect((restarted['initial'] as Map)['cfi'], visible.cfi);
        expect(app.reader.bookmarks.single.title, 'A saved river');
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  }

  testWidgets(
    'global modes and Automatic follow system changes in an open reader after a reader selection',
    (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final app = ReadingApp();
      await app.prepare(tester, AppearanceMode.day);
      await tester.tap(find.byTooltip('Night reading theme'));
      await tester.pumpAndSettle();
      final bridge = app.platform.controllers.single;
      bridge.handlers['readerLocation']!([visible.toJson()]);
      final anchor = app.reader.position!.anchor;
      bridge.calls.clear();
      await app.appearance.selectMode(AppearanceMode.day);
      await tester.pumpAndSettle();
      expect(bridge.calls.map((call) => call.arguments).toList(), [
        {'argument0': 20.0, 'argument1': false},
      ]);
      expect(app.reader.position!.anchor, anchor);
      bridge.calls.clear();
      await app.appearance.selectMode(AppearanceMode.automatic);
      await tester.pumpAndSettle();
      expect(bridge.calls, isEmpty);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();
      expect(screenBrightness(tester), Brightness.dark);
      expect(bridge.calls.map((call) => call.arguments).toList(), [
        {'argument0': 20.0, 'argument1': true},
      ]);
      bridge.calls.clear();
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await tester.pumpAndSettle();
      expect(bridge.calls.map((call) => call.arguments).toList(), [
        {'argument0': 20.0, 'argument1': false},
      ]);
      expect(app.reader.position!.anchor, anchor);
      await app.leaveReader(tester);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Appearance'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Automatic'))
            .selected,
        isTrue,
      );
      await tester.tap(find.widgetWithText(ChoiceChip, 'Night'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Automatic'));
      await tester.pumpAndSettle();
      expect(app.appearance.settings.mode, AppearanceMode.automatic);
      expect(screenBrightness(tester), Brightness.light);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
