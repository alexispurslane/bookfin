import 'package:bookfin/appearance/appearance.dart';
import 'package:bookfin/appearance/preferences.dart';
import 'package:bookfin/catalog/controller.dart';
import 'package:bookfin/main.dart';
import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/epub/pager.dart';
import 'package:bookfin/reader/screen.dart';
import 'package:bookfin/reader/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../catalog/controller_test.dart'
    show FixtureClient, MemoryCredentials, MemoryCatalogStore;
import '../catalog/model_test.dart' show entry;
import '../playback/playback_test.dart' show LocalFiles, MemoryResume;
import '../real_time.dart';
import 'epub/helpers.dart' show loadReaderFont;
import 'native_reader.dart';
import 'reader_settings.dart';

class ReadingApp {
  final client = FixtureClient(Uri.parse('https://books.example'));
  final downloads = LocalFiles();
  final records = MemoryResume();
  final publication = twoChapterBook();
  late final catalog = CatalogController(
    credentials: MemoryCredentials(),
    store: MemoryCatalogStore(),
    clientFactory: (server, device) => client,
  );
  AppearanceController appearance = AppearanceController(
    LocalAppearanceStore(),
    clock: () => DateTime.utc(2026, 11, 2, 12),
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
  );

  Future<void> prepare(WidgetTester tester, AppearanceMode mode) async {
    runIdleStepsDuringAnimations();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      reader.dispose();
      appearance.dispose();
      downloads.dispose();
      catalog.dispose();
      client.close();
    });
    await appearance.selectMode(mode);
    client.entries = [entry('ebook', type: 'Book', container: 'epub')];
    await finish(
      tester,
      catalog.connect('https://books.example', 'alice', 'fixture-password'),
    );
    await finish(tester, catalog.refresh(selected: {'books'}));
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
    await waitForPage(tester, reader);
    await settleReader(tester, () => reader.visibleAddress != null);
    expect(reader.ready, isTrue);
  }

  /// The page that the open book shows once it is laid out at [fontSize]
  /// pixels, in night or cream.
  Future<ShownPage> pageAt(
    WidgetTester tester, {
    required double fontSize,
    required bool night,
  }) => waitForPage(
    tester,
    reader,
    (shown) =>
        shown.page.settings.fontSize == fontSize &&
        shown.page.settings.night == night,
  );

  /// Turns to the next page and waits until the session saves it.
  Future<void> turn(WidgetTester tester) async {
    final before = reader.visibleAddress;
    await finishReader(tester, reader.move(true));
    await settleReader(
      tester,
      () => reader.visibleAddress != before && reader.position != null,
    );
  }

  /// The CFI of the open book's visible place.
  String? get cfi => (reader.visibleAddress as EpubAddress?)?.location.cfi;

  Future<void> leaveReader(WidgetTester tester) async {
    Navigator.of(tester.element(find.byType(ReaderScreen))).pop();
    await tester.pumpAndSettle();
    await finishReader(tester, reader.flush());
    expect(find.byType(ReaderScreen), findsNothing);
  }
}

Brightness screenBrightness(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(Scaffold).last)).brightness;

void main() {
  setUpAll(loadReaderFont);
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
        await app.turn(tester);
        final cfi = app.cfi;
        await app.reader.addBookmark(title: 'A saved river');
        await chooseSetting(tester, 'Larger text');
        await app.pageAt(tester, fontSize: 22, night: !choice.night);
        final anchor = app.reader.position!.anchor;
        await chooseSetting(tester, choice.tooltip);
        expect(app.appearance.settings.mode, choice.mode);
        expect(app.appearance.saveState, PreferenceSaveState.saved);
        expect(screenBrightness(tester), choice.brightness);
        await app.pageAt(tester, fontSize: 22, night: choice.night);
        expect(app.reader.position!.anchor, anchor);
        expect(app.cfi, cfi);
        await app.leaveReader(tester);
        expect(screenBrightness(tester), choice.brightness);
        await app.openReader(tester);
        await app.pageAt(tester, fontSize: 22, night: choice.night);
        expect(app.cfi, cfi, reason: 'The book opens at the saved place.');
        expect(app.reader.bookmarks.single.title, 'A saved river');
        await tester.pumpWidget(const SizedBox());
        app.reader.dispose();
        await finishReader(tester, app.reader.flush());
        app.appearance.dispose();
        app.appearance = AppearanceController(
          LocalAppearanceStore(),
          clock: () => DateTime.utc(2026, 11, 2, 12),
        );
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
        await app.pageAt(tester, fontSize: 22, night: choice.night);
        expect(app.cfi, cfi, reason: 'The book opens at the saved place.');
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
      await chooseSetting(tester, 'Night reading theme');
      await app.turn(tester);
      final anchor = app.reader.position!.anchor;
      await app.pageAt(tester, fontSize: 20, night: true);
      await app.appearance.selectMode(AppearanceMode.day);
      await tester.pump();
      final day = await app.pageAt(tester, fontSize: 20, night: false);
      expect(app.reader.position!.anchor, anchor);
      await app.appearance.selectMode(AppearanceMode.automatic);
      await tester.pumpAndSettle();
      expect(
        app.reader.pager!.shown.value!.page,
        same(day.page),
        reason: 'Automatic keeps the day page in a light system.',
      );
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pump();
      await app.pageAt(tester, fontSize: 20, night: true);
      expect(screenBrightness(tester), Brightness.dark);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await tester.pump();
      await app.pageAt(tester, fontSize: 20, night: false);
      expect(app.reader.position!.anchor, anchor);
      await app.leaveReader(tester);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Appearance'));
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
