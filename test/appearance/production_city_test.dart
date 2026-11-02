import 'package:bookfin/appearance/appearance.dart';
import 'package:bookfin/appearance/preferences.dart';
import 'package:bookfin/main.dart';
import 'package:flutter/foundation.dart';
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
