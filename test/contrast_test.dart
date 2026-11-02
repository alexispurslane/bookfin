import 'package:bookfin/foundation/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double contrast(Color foreground, Color background) {
  final first = foreground.computeLuminance();
  final second = background.computeLuminance();
  return first > second
      ? (first + 0.05) / (second + 0.05)
      : (second + 0.05) / (first + 0.05);
}

void main() {
  for (final brightness in Brightness.values) {
    test('$brightness text remains readable across every surface', () {
      final scheme = bookfinTheme(brightness).colorScheme;
      for (final surface in [
        scheme.surface,
        scheme.surfaceContainer,
        scheme.surfaceContainerLow,
      ]) {
        expect(contrast(scheme.onSurface, surface), greaterThanOrEqualTo(4.5));
        expect(
          contrast(scheme.onSurfaceVariant, surface),
          greaterThanOrEqualTo(4.5),
        );
        expect(contrast(scheme.primary, surface), greaterThanOrEqualTo(4.5));
        expect(contrast(scheme.outline, surface), greaterThanOrEqualTo(3));
      }
      expect(
        contrast(scheme.onPrimary, scheme.primary),
        greaterThanOrEqualTo(4.5),
      );
    });
  }
}
