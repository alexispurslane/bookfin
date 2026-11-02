import 'package:bookfin/appearance/appearance.dart';
import 'package:bookfin/appearance/preferences.dart';
import 'package:bookfin/main.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:bookfin/appearance/city_search.dart';

import '../contrast_test.dart' show contrast;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'preferences_test.dart' show MemoryAppearanceStore;

late String cityData;

class BundledCities extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) => rootBundle.load(key);

  @override
  Future<String> loadString(String key, {bool cache = true}) =>
      key == 'assets/cities/cities.tsv'
      ? SynchronousFuture(cityData)
      : rootBundle.loadString(key, cache: cache);
}

Widget productionApp(
  AppearanceController controller, {
  DateTime Function()? clock,
}) => DefaultAssetBundle(
  bundle: BundledCities(),
  child: BookfinApp(appearance: controller, clock: clock),
);

Future<void> openCitySearch(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Appearance'));
  await tester.pumpAndSettle();
  expect(find.text('Choose city'), findsOneWidget);
  await tester.tap(find.text('Choose city'));
  await tester.pumpAndSettle();
}

Future<void> search(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField), query);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    cityData = await rootBundle.loadString('assets/cities/cities.tsv');
  });
  testWidgets('city route text stays opaque during entry and exit', (
    tester,
  ) async {
    final controller = AppearanceController(MemoryAppearanceStore());
    await tester.pumpWidget(productionApp(controller));
    for (final mode in [AppearanceMode.day, AppearanceMode.night]) {
      await controller.selectMode(mode);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Appearance'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose city'));
      await tester.pump();
      for (final exiting in [false, true]) {
        if (exiting) {
          Navigator.of(tester.element(find.byType(CitySearch))).pop();
          await tester.pump();
        }
        for (var frame = 0; frame < 12; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          final title = find.descendant(
            of: find.byType(AppBar),
            matching: find.text('Choose city'),
          );
          if (title.evaluate().isEmpty) break;
          final paragraph = tester.renderObject<RenderParagraph>(title);
          var opacity = 1.0;
          RenderObject? node = paragraph;
          while (node != null) {
            if (node is RenderAnimatedOpacity) opacity *= node.opacity.value;
            if (node is RenderOpacity) opacity *= node.opacity;
            node = node.parent;
          }
          final theme = Theme.of(tester.element(title));
          final surface = theme.appBarTheme.backgroundColor!;
          final ink = paragraph.text.style!.color!;
          expect(
            contrast(
              Color.alphaBlend(ink.withValues(alpha: ink.a * opacity), surface),
              surface,
            ),
            greaterThanOrEqualTo(4.5),
          );
        }
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('reduced motion opens city search without moving its text', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(
      productionApp(AppearanceController(MemoryAppearanceStore())),
    );
    await tester.tap(find.byTooltip('Appearance'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose city'));
    await tester.pump();
    final title = find.descendant(
      of: find.byType(AppBar),
      matching: find.text('Choose city'),
    );
    final initialPosition = tester.getTopLeft(title);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getTopLeft(title), initialPosition);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(title), initialPosition);
  });

  testWidgets(
    'large text city results remain selectable above a landscape keyboard',
    (tester) async {
      tester.view.physicalSize = const Size(800, 360);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = AppearanceController(MemoryAppearanceStore());
      await tester.pumpWidget(
        DefaultAssetBundle(
          bundle: BundledCities(),
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(2),
                viewInsets: const EdgeInsets.only(bottom: 180),
              ),
              child: child!,
            ),
            home: CitySearch(appearance: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await search(tester, 'Tokyo');
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('Tokyo, Tokyo, Japan'),
        100,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tokyo, Tokyo, Japan'));
      await tester.pumpAndSettle();
      expect(controller.settings.location?.name, 'Tokyo, Tokyo, Japan');
    },
  );

  testWidgets('production search distinguishes cities with the same name', (
    tester,
  ) async {
    await tester.pumpWidget(
      productionApp(AppearanceController(MemoryAppearanceStore())),
    );
    await openCitySearch(tester);
    await search(tester, 'Springfield');
    expect(find.text('Springfield, Illinois, United States'), findsOneWidget);
    expect(find.text('Springfield, Missouri, United States'), findsOneWidget);
    await search(tester, 'springfield illinois');
    expect(find.text('Springfield, Illinois, United States'), findsOneWidget);
    expect(find.text('Springfield, Missouri, United States'), findsNothing);
    await search(tester, 'zzzznotacity');
    expect(
      find.text('No matching city. Try a nearby larger city.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'production search accepts ASCII names and discards blank input',
    (tester) async {
      final controller = AppearanceController(MemoryAppearanceStore());
      await tester.pumpWidget(productionApp(controller));
      await openCitySearch(tester);
      await search(tester, '  SAO   PAULO  ');
      expect(find.text('São Paulo, São Paulo, Brazil'), findsOneWidget);
      await search(tester, '   ');
      expect(find.byType(ListTile), findsNothing);
      expect(
        find.text('Enter a city name. You can add a region or country.'),
        findsOneWidget,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(controller.settings.location, isNull);
    },
  );

  testWidgets('a production city persists and drives sunrise and sunset', (
    tester,
  ) async {
    final store = MemoryAppearanceStore();
    final controller = AppearanceController(store);
    var instant = DateTime.utc(2026, 3, 20, 22, 55);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(productionApp(controller, clock: () => instant));
    await openCitySearch(tester);
    await search(tester, 'new york');
    await tester.tap(find.text('New York City, New York, United States'));
    await tester.pumpAndSettle();
    expect(controller.settings.location?.latitude, closeTo(40.71427, 0.001));
    expect(controller.settings.location?.longitude, closeTo(-74.00597, 0.001));
    await tester.ensureVisible(find.text('Done'));
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(
      find.text('Daylight · New York City, New York, United States'),
      findsOneWidget,
    );
    expect(
      Theme.of(tester.element(find.byType(Scaffold).first)).brightness,
      Brightness.light,
    );
    final reopened = AppearanceController(store);
    await reopened.restore();
    instant = DateTime.utc(2026, 3, 20, 23, 20);
    await tester.pumpWidget(productionApp(reopened, clock: () => instant));
    await tester.pumpAndSettle();
    expect(
      find.text('After sunset · New York City, New York, United States'),
      findsOneWidget,
    );
    expect(
      Theme.of(tester.element(find.byType(Scaffold).first)).brightness,
      Brightness.dark,
    );
    instant = DateTime.utc(2026, 3, 21, 11, 10);
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    expect(
      find.text('Daylight · New York City, New York, United States'),
      findsOneWidget,
    );
  });

  testWidgets(
    'production removal persists fallback without losing manual override',
    (tester) async {
      final store = MemoryAppearanceStore();
      final controller = AppearanceController(store);
      await tester.pumpWidget(productionApp(controller));
      await openCitySearch(tester);
      await search(tester, 'tokyo');
      await tester.tap(find.text('Tokyo, Tokyo, Japan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Night'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Remove selected location'));
      await tester.tap(find.text('Remove selected location'));
      await tester.pumpAndSettle();
      expect(controller.settings.location, isNull);
      expect(controller.settings.mode, AppearanceMode.night);
      final reopened = AppearanceController(store);
      await reopened.restore();
      expect(reopened.settings.location, isNull);
      expect(reopened.settings.mode, AppearanceMode.night);
      await tester.ensureVisible(find.text('Automatic'));
      await tester.tap(find.text('Automatic'));
      await tester.pumpAndSettle();
      expect(
        find.text('System appearance · no location selected'),
        findsWidgets,
      );
    },
  );
}
