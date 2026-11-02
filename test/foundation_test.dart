import 'package:bookfin/appearance/appearance.dart';
import 'package:bookfin/appearance/preferences.dart';
import 'package:bookfin/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'appearance/preferences_test.dart' show MemoryAppearanceStore;
import 'contrast_test.dart' show contrast;

Brightness brightness(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(Scaffold).first)).brightness;

void main() {
  testWidgets(
    'an open appearance sheet updates its polar explanation after the date changes',
    (tester) async {
      var now = DateTime.utc(2026, 11, 1);
      final controller = AppearanceController(MemoryAppearanceStore());
      await controller.selectLocation(
        SelectedLocation('Tromsø', 69.6492, 18.9553),
      );
      await tester.pumpWidget(
        BookfinApp(appearance: controller, clock: () => now),
      );
      await tester.tap(find.byTooltip('Appearance'));
      await tester.pumpAndSettle();
      expect(find.text('After sunset · Tromsø').hitTestable(), findsOneWidget);
      now = DateTime.utc(2026, 12, 21, 12);
      await tester.pump(const Duration(seconds: 31));
      await tester.pumpAndSettle();
      expect(find.text('Polar night · Tromsø').hitTestable(), findsOneWidget);
    },
  );

  testWidgets(
    'appearance controls and sheet text stay readable during selection',
    (tester) async {
      final controller = AppearanceController(MemoryAppearanceStore());
      await controller.selectMode(AppearanceMode.day);
      await tester.pumpWidget(
        BookfinApp(appearance: controller, gallery: true),
      );
      await tester.tap(find.byTooltip('Appearance'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Night'));
      await tester.pump();
      for (var frame = 0; frame < 38; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        final description = find.text(
          'Automatic uses sunrise and sunset at your selected location. Without a location, it follows Android system appearance.',
        );
        final paragraph = tester.renderObject<RenderParagraph>(description);
        final surface = Theme.of(tester.element(description))
            .colorScheme
            .surfaceContainerLow;
        expect(
          contrast(paragraph.text.style!.color!, surface),
          greaterThanOrEqualTo(4.5),
        );
        final choice = find.widgetWithText(ChoiceChip, 'Night');
        final ink = tester.widget<Ink>(
          find.descendant(of: choice, matching: find.byType(Ink)),
        );
        final label = tester.renderObject<RenderParagraph>(find.text('Night'));
        expect(
          contrast(
            label.text.style!.color!,
            (ink.decoration! as ShapeDecoration).color!,
          ),
          greaterThanOrEqualTo(4.5),
        );
      }
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'text stays readable during both directions of a palette change',
    (tester) async {
      final controller = AppearanceController(MemoryAppearanceStore());
      await controller.selectMode(AppearanceMode.day);
      await tester.pumpWidget(BookfinApp(appearance: controller));
      for (final mode in [AppearanceMode.night, AppearanceMode.day]) {
        await controller.selectMode(mode);
        await tester.pump();
        for (var frame = 0; frame < 6; frame++) {
          await tester.pump(const Duration(milliseconds: 100));
          final theme = Theme.of(tester.element(find.byType(Scaffold).first));
          final scheme = theme.colorScheme;
          final paragraph = tester.renderObject<RenderParagraph>(
            find.text(
              'Library connection is not available in this setup build.',
            ),
          );
          expect(
            contrast(paragraph.text.style!.color!, scheme.surface),
            greaterThanOrEqualTo(4.5),
          );
          for (final surface in [
            scheme.surface,
            scheme.surfaceContainer,
            scheme.surfaceContainerLow,
          ]) {
            expect(
              contrast(scheme.onSurface, surface),
              greaterThanOrEqualTo(4.5),
            );
            expect(
              contrast(scheme.onSurfaceVariant, surface),
              greaterThanOrEqualTo(4.5),
            );
            expect(
              contrast(scheme.primary, surface),
              greaterThanOrEqualTo(4.5),
            );
          }
          expect(
            contrast(scheme.onPrimary, scheme.primary),
            greaterThanOrEqualTo(4.5),
          );
        }
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets(
    'manual appearance changes the screen without losing its filter',
    (tester) async {
      final controller = AppearanceController(MemoryAppearanceStore());
      await tester.pumpWidget(
        BookfinApp(appearance: controller, gallery: true),
      );
      await tester.tap(find.text('Downloaded'));
      await tester.pumpAndSettle();
      expect(find.text('The Lost World').hitTestable(), findsNothing);
      await controller.selectMode(AppearanceMode.night);
      await tester.pumpAndSettle();
      expect(brightness(tester), Brightness.dark);
      expect(find.text('The Lost World').hitTestable(), findsNothing);
      await controller.selectMode(AppearanceMode.day);
      await tester.pumpAndSettle();
      expect(brightness(tester), Brightness.light);
      expect(find.text('The Lost World').hitTestable(), findsNothing);
    },
  );

  testWidgets(
    'reading size and scroll survive navigation and a palette change',
    (tester) async {
      final controller = AppearanceController(MemoryAppearanceStore());
      await tester.pumpWidget(
        BookfinApp(appearance: controller, gallery: true),
      );
      await tester.tap(find.text('Reader'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('A+'), 300);
      await tester.tap(find.text('A+'));
      await tester.pumpAndSettle();
      final paragraph = find.textContaining('The Time Traveller (for so');
      expect(tester.widget<Text>(paragraph).style?.fontSize, 21);
      final readerScroll = find.descendant(
        of: find.byKey(const PageStorageKey('gallery-reader')),
        matching: find.byType(Scrollable),
      );
      final savedOffset = tester
          .state<ScrollableState>(readerScroll)
          .position
          .pixels;
      expect(savedOffset, greaterThan(0));
      await controller.selectMode(AppearanceMode.night);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Library').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reader'));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(paragraph).style?.fontSize, 21);
      expect(
        tester.state<ScrollableState>(readerScroll).position.pixels,
        savedOffset,
      );
    },
  );

  testWidgets(
    'automatic appearance recalculates after resume and location changes',
    (tester) async {
      var now = DateTime.utc(2026, 3, 20, 16);
      final controller = AppearanceController(MemoryAppearanceStore());
      await controller.selectLocation(
        SelectedLocation('New York', 40.7128, -74.0060),
      );
      await tester.pumpWidget(
        BookfinApp(appearance: controller, clock: () => now),
      );
      await tester.pumpAndSettle();
      expect(brightness(tester), Brightness.light);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      now = DateTime.utc(2026, 3, 21, 2);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(brightness(tester), Brightness.dark);
      await controller.selectLocation(
        SelectedLocation('Tokyo', 35.6762, 139.6503),
      );
      await tester.pumpAndSettle();
      expect(brightness(tester), Brightness.light);
    },
  );

  testWidgets('automatic appearance changes while the app remains open', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 3, 20, 22, 55);
    final controller = AppearanceController(MemoryAppearanceStore());
    await controller.selectLocation(
      SelectedLocation('New York', 40.7128, -74.0060),
    );
    await tester.pumpWidget(
      BookfinApp(appearance: controller, clock: () => now),
    );
    await tester.pumpAndSettle();
    expect(brightness(tester), Brightness.light);
    now = DateTime.utc(2026, 3, 20, 23, 20);
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();
    expect(brightness(tester), Brightness.dark);
  });

  testWidgets(
    'without a location Android system appearance changes are honored',
    (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpWidget(
        BookfinApp(appearance: AppearanceController(MemoryAppearanceStore())),
      );
      expect(brightness(tester), Brightness.light);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();
      expect(brightness(tester), Brightness.dark);
      expect(find.textContaining('System appearance'), findsOneWidget);
    },
  );

  testWidgets('reduced motion applies palette and screen changes immediately', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final controller = AppearanceController(MemoryAppearanceStore());
    await tester.pumpWidget(BookfinApp(appearance: controller, gallery: true));
    await controller.selectMode(AppearanceMode.night);
    await tester.pump();
    expect(brightness(tester), Brightness.dark);
    await tester.tap(find.text('Reader'));
    await tester.pump();
    expect(find.text('The Time Traveller').hitTestable(), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('large text fits the gallery and appearance controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      BookfinApp(
        appearance: AppearanceController(MemoryAppearanceStore()),
        gallery: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Appearance'));
    await tester.pumpAndSettle();
    expect(find.text('Automatic'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
