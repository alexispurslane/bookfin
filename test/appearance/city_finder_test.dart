import 'dart:async';
import 'dart:isolate';

import 'package:bookfin/appearance/appearance.dart';
import 'package:bookfin/appearance/cities.dart';
import 'package:bookfin/appearance/city_search.dart';
import 'package:bookfin/appearance/preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cities_test.dart' show sampleCities;
import 'preferences_test.dart' show MemoryAppearanceStore;

/// Answers each search with one place named after the isolate that ran it.
List<SelectedLocation> isolateName(CityCatalog catalog, String query) => [
  SelectedLocation(Isolate.current.debugName ?? 'unnamed', 0, 0),
];

/// A finder whose answers the test gives, one query at a time.
class HeldFinder implements CityFinder {
  final asked = <String, Completer<List<SelectedLocation>>>{};

  @override
  Future<List<SelectedLocation>> search(String query) =>
      (asked[query] = Completer()).future;

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class SampleCities extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) => rootBundle.load(key);

  @override
  Future<String> loadString(String key, {bool cache = true}) =>
      SynchronousFuture(sampleCities);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a city search runs in the finder isolate, not the caller isolate',
    () async {
      final finder = await CityFinder.start(sampleCities, search: isolateName);
      addTearDown(finder.close);

      final answer = await finder.search('cambridge');

      expect(answer.single.name, isNot(Isolate.current.debugName));
    },
  );

  test('the finder answers with the catalog matches', () async {
    final finder = await CityFinder.start(sampleCities);
    addTearDown(finder.close);

    final answer = await finder.search('cambridge');

    expect(
      answer.map((city) => city.name),
      CityCatalog.fromTsv(sampleCities)
          .search('cambridge')
          .map((city) => city.name),
    );
  });

  testWidgets('the search page shows the latest answer and drops a stale one', (
    tester,
  ) async {
    final finder = HeldFinder();
    await tester.pumpWidget(
      DefaultAssetBundle(
        bundle: SampleCities(),
        child: MaterialApp(
          home: CitySearch(
            appearance: AppearanceController(MemoryAppearanceStore()),
            start: (_) async => finder,
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'spr');
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'springfield');
    await tester.pump();
    finder.asked['springfield']!.complete([
      SelectedLocation('Latest answer', 0, 0),
    ]);
    await tester.pump();
    finder.asked['spr']!.complete([SelectedLocation('Stale answer', 0, 0)]);
    await tester.pump();

    expect(find.text('Latest answer'), findsOneWidget);
    expect(find.text('Stale answer'), findsNothing);
  });
}
