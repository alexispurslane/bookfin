import 'package:bookfin/appearance/appearance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final newYork = SelectedLocation('New York', 40.7128, -74.0060);
  final tromso = SelectedLocation('Tromsø', 69.6492, 18.9553);

  test(
    'automatic appearance follows the system without a selected location',
    () {
      final result = resolveAppearance(
        const AppearanceSettings(),
        DateTime.utc(2026, 3, 20, 12),
        Brightness.light,
      );
      expect(result.brightness, Brightness.light);
      expect(result.description, contains('System appearance'));
      expect(result.description, contains('no location'));
    },
  );

  test('manual day overrides darkness and retains the selected location', () {
    final settings = AppearanceSettings(
      mode: AppearanceMode.day,
      location: newYork,
    );
    expect(
      resolveAppearance(
        settings,
        DateTime.utc(2026, 3, 20, 4),
        Brightness.dark,
      ).brightness,
      Brightness.light,
    );
    expect(settings.location, same(newYork));
  });

  test('manual night overrides daylight', () {
    expect(
      resolveAppearance(
        AppearanceSettings(mode: AppearanceMode.night, location: newYork),
        DateTime.utc(2026, 3, 20, 16),
        Brightness.light,
      ).brightness,
      Brightness.dark,
    );
  });

  test('New York changes from night to day around the March sunrise', () {
    expect(
      solarPeriod(DateTime.utc(2026, 3, 20, 10, 50), newYork),
      SolarPeriod.night,
    );
    expect(
      solarPeriod(DateTime.utc(2026, 3, 20, 11, 10), newYork),
      SolarPeriod.day,
    );
  });

  test('New York changes from day to night around the March sunset', () {
    expect(
      solarPeriod(DateTime.utc(2026, 3, 20, 22, 55), newYork),
      SolarPeriod.day,
    );
    expect(
      solarPeriod(DateTime.utc(2026, 3, 20, 23, 20), newYork),
      SolarPeriod.night,
    );
  });

  test(
    'the same instant has the same appearance across time zones and DST',
    () {
      final settings = AppearanceSettings(location: newYork);
      final utc = DateTime.parse('2026-11-01T11:40:00Z');
      final offset = DateTime.parse('2026-11-01T06:40:00-05:00');
      expect(
        resolveAppearance(settings, utc, Brightness.dark).brightness,
        Brightness.light,
      );
      expect(
        resolveAppearance(settings, offset, Brightness.dark).brightness,
        Brightness.light,
      );
    },
  );

  test('a selected location uses its sunlight rather than the device date', () {
    final tokyo = SelectedLocation('Tokyo', 35.6762, 139.6503);
    expect(
      solarPeriod(DateTime.utc(2026, 3, 19, 21, 30), tokyo),
      SolarPeriod.day,
    );
    expect(
      solarPeriod(DateTime.utc(2026, 3, 20, 12), tokyo),
      SolarPeriod.night,
    );
  });

  test(
    'a new date and a leap day are calculated from the supplied instant',
    () {
      expect(
        solarPeriod(DateTime.utc(2024, 2, 29, 12), newYork),
        SolarPeriod.day,
      );
      expect(
        solarPeriod(DateTime.utc(2026, 6, 21, 10), newYork),
        SolarPeriod.day,
      );
      expect(
        solarPeriod(DateTime.utc(2026, 12, 21, 10), newYork),
        SolarPeriod.night,
      );
    },
  );

  test('polar summer remains day and polar winter remains night', () {
    expect(
      solarPeriod(DateTime.utc(2026, 6, 21), tromso),
      SolarPeriod.polarDay,
    );
    expect(
      solarPeriod(DateTime.utc(2026, 12, 21, 12), tromso),
      SolarPeriod.polarNight,
    );
    expect(
      resolveAppearance(
        AppearanceSettings(location: tromso),
        DateTime.utc(2026, 6, 21),
        Brightness.dark,
      ).description,
      contains('Polar day'),
    );
  });

  test('southern polar seasons are the reverse of northern seasons', () {
    final southPole = SelectedLocation('South Pole', -90, 0);
    expect(
      solarPeriod(DateTime.utc(2026, 6, 21, 12), southPole),
      SolarPeriod.polarNight,
    );
    expect(
      solarPeriod(DateTime.utc(2026, 12, 21), southPole),
      SolarPeriod.polarDay,
    );
  });

  test('invalid selected locations cannot enter appearance policy', () {
    expect(() => SelectedLocation('', 0, 0), throwsArgumentError);
    expect(
      () => SelectedLocation('Invalid', double.nan, 0),
      throwsArgumentError,
    );
    expect(() => SelectedLocation('Invalid', 91, 0), throwsArgumentError);
    expect(() => SelectedLocation('Invalid', 0, -181), throwsArgumentError);
  });
}
