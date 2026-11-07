import 'package:bookfin/foundation/theme.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// The fill colors drawn by [finder] and the widgets below it.
  Set<Color?> fills(WidgetTester tester, Finder finder) {
    final below = find.descendant(
      of: finder,
      matching: find.byWidgetPredicate((_) => true),
    );
    return {
      for (final element in [...finder.evaluate(), ...below.evaluate()])
        switch (element.widget) {
          Material(:final color, :final type)
              when type != MaterialType.transparency =>
            color,
          Container(:final BoxDecoration decoration) => decoration.color,
          _ => null,
        },
    }..remove(null);
  }

  testWidgets('a settings group on the night stage is theater paper', (
    tester,
  ) async {
    final theater = theaterTheme(bookfinTheme(Brightness.dark));
    await tester.pumpWidget(
      MaterialApp(
        theme: theater,
        home: const Scaffold(
          body: SettingsGroup(children: [Text('Sleep timer')]),
        ),
      ),
    );
    expect(fills(tester, find.byType(SettingsGroup)), {
      theater.colorScheme.surfaceContainerLowest,
    });
  });
}
