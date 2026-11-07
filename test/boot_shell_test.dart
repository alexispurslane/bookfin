import 'package:bookfin/main.dart';
import 'package:bookfin/appearance/preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'appearance/preferences_test.dart' show MemoryAppearanceStore;
import 'catalog/controller_test.dart'
    show MemoryCatalogStore, MemoryCredentials;

import 'package:bookfin/catalog/controller.dart';

void main() {
  testWidgets('Bookfin identifies itself before a library is connected', (
    tester,
  ) async {
    await tester.pumpWidget(
      BookfinApp(
        appearance: AppearanceController(MemoryAppearanceStore()),
        catalog: CatalogController(
          credentials: MemoryCredentials(),
          store: MemoryCatalogStore(),
        ),
      ),
    );

    expect(find.text('Bookfin'), findsOneWidget);
    expect(find.text('Your library starts here.'), findsOneWidget);
  });

  testWidgets('the setup shell does not pretend that books are available', (
    tester,
  ) async {
    await tester.pumpWidget(
      BookfinApp(
        appearance: AppearanceController(MemoryAppearanceStore()),
        catalog: CatalogController(
          credentials: MemoryCredentials(),
          store: MemoryCatalogStore(),
        ),
      ),
    );

    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
  });
}
