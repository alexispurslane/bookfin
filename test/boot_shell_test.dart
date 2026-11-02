import 'package:bookfin/main.dart';
import 'package:bookfin/appearance/preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'appearance/preferences_test.dart' show MemoryAppearanceStore;

void main() {
  testWidgets('Bookfin identifies itself before a library is connected', (
    tester,
  ) async {
    await tester.pumpWidget(
      BookfinApp(appearance: AppearanceController(MemoryAppearanceStore())),
    );

    expect(find.text('BOOKFIN'), findsOneWidget);
    expect(find.text('Your library starts here.'), findsOneWidget);
  });

  testWidgets('the setup shell does not pretend that books are available', (
    tester,
  ) async {
    await tester.pumpWidget(
      BookfinApp(appearance: AppearanceController(MemoryAppearanceStore())),
    );

    expect(
      find.text('Library connection is not available in this setup build.'),
      findsOneWidget,
    );
    expect(find.byType(FloatingActionButton), findsNothing);
  });
}
