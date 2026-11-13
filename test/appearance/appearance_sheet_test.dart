import 'package:bookfin/appearance/appearance.dart';
import 'package:bookfin/appearance/preferences.dart';
import 'package:bookfin/foundation/theme.dart';
import 'package:bookfin/appearance/sheet.dart';
import 'package:bookfin/development/appearance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'preferences_test.dart' show MemoryAppearanceStore;

/// An appearance controller that a leaf may read but must not act on.
class _ReadOnlyAppearance extends AppearanceController {
  _ReadOnlyAppearance(this._shown) : super(MemoryAppearanceStore());
  final AppearanceSettings _shown;

  @override
  AppearanceSettings get settings => _shown;
  @override
  Future<void> selectMode(AppearanceMode mode) =>
      throw StateError('The sheet changed the mode itself.');
  @override
  Future<void> selectLocation(SelectedLocation? location) =>
      throw StateError('The sheet changed the location itself.');
}

void main() {
  testWidgets('Done remains reachable above scrolling appearance choices', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 600);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final appearance = AppearanceController(MemoryAppearanceStore());
    addTearDown(appearance.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: bookfinTheme(Brightness.light),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showAppearance(context, appearance),
              child: const Text('Open appearance'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open appearance'));
    await tester.pumpAndSettle();
    expect(find.text('Done').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.byType(AppearanceSheet), findsNothing);
    expect(find.text('Open appearance').hitTestable(), findsOneWidget);
  });

  final tokyo = SelectedLocation('Tokyo', 35.6762, 139.6503);
  late List<Object?> reports;

  Future<void> show(
    WidgetTester tester,
    AppearanceSettings settings, {
    bool gallery = false,
  }) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    reports = [];
    await tester.pumpWidget(
      MaterialApp(
        theme: bookfinTheme(Brightness.light),
        home: Scaffold(
          body: AppearanceSheet(
            appearance: _ReadOnlyAppearance(settings),
            child: gallery ? AppearanceFixtures(onLocation: reports.add) : null,
            onMode: (mode) => reports.add(mode),
            onChooseCity: () => reports.add('choose city'),
            onRemoveLocation: () => reports.add('no location'),
          ),
        ),
      ),
    );
  }

  testWidgets('choosing a mode reports the mode', (tester) async {
    await show(tester, const AppearanceSettings());
    await tester.tap(find.text('Night'));
    await tester.pump();
    expect(reports, [AppearanceMode.night]);
  });

  testWidgets('choosing a city reports the wish to choose one', (tester) async {
    await show(tester, const AppearanceSettings());
    await tester.tap(find.text('Choose city'));
    await tester.pump();
    expect(reports, ['choose city']);
    expect(find.text('Choose city'), findsOneWidget);
  });

  testWidgets('removing the location reports no location', (tester) async {
    await show(tester, AppearanceSettings(location: tokyo));
    expect(find.text('Tokyo'), findsOneWidget);
    await tester.tap(find.text('Remove selected location'));
    await tester.pump();
    expect(reports, ['no location']);
  });

  testWidgets('a development location fixture reports its location', (
    tester,
  ) async {
    await show(tester, const AppearanceSettings(), gallery: true);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Tokyo'));
    await tester.pump();
    expect(reports.single, isA<SelectedLocation>());
    expect((reports.single! as SelectedLocation).name, 'Tokyo');
  });
}
