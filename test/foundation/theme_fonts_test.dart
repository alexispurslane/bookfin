import 'package:bookfin/foundation/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final themes = {
    'day': bookfinTheme(Brightness.light),
    'night': bookfinTheme(Brightness.dark),
    'stage': theaterTheme(bookfinTheme(Brightness.dark)),
  };

  for (final MapEntry(key: name, value: theme) in themes.entries) {
    test('every $name text style draws in an approved typeface', () {
      final text = theme.textTheme;
      final styles = {
        'displaySmall': text.displaySmall,
        'headlineMedium': text.headlineMedium,
        'headlineSmall': text.headlineSmall,
        'titleLarge': text.titleLarge,
        'titleMedium': text.titleMedium,
        'titleSmall': text.titleSmall,
        'bodyLarge': text.bodyLarge,
        'bodyMedium': text.bodyMedium,
        'bodySmall': text.bodySmall,
        'labelLarge': text.labelLarge,
        'labelMedium': text.labelMedium,
        'labelSmall': text.labelSmall,
      };
      for (final MapEntry(key: role, value: style) in styles.entries) {
        expect(
          style?.fontFamily,
          anyOf('Outfit', 'Source Serif 4'),
          reason: '$role falls back to the platform font',
        );
      }
    });
  }

  test('body text keeps the sizes of the approved mockup', () {
    final text = bookfinTheme(Brightness.light).textTheme;
    expect(text.bodyLarge?.fontSize, 16);
    expect(text.bodyMedium?.fontSize, 14);
    expect(text.bodySmall?.fontSize, 12);
    expect(text.labelSmall?.fontSize, 11);
  });
}
