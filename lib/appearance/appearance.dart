import 'dart:math' as math;

import 'package:flutter/material.dart';

enum AppearanceMode { automatic, day, night }

enum SolarPeriod { day, night, polarDay, polarNight }

class SelectedLocation {
  SelectedLocation(this.name, this.latitude, this.longitude) {
    if (name.trim().isEmpty ||
        !latitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        !longitude.isFinite ||
        longitude < -180 ||
        longitude > 180) {
      throw ArgumentError('A location needs a name and valid coordinates.');
    }
  }

  final String name;
  final double latitude;
  final double longitude;
}

class AppearanceSettings {
  const AppearanceSettings({
    this.mode = AppearanceMode.automatic,
    this.location,
  });

  final AppearanceMode mode;
  final SelectedLocation? location;
}

class AppearanceDecision {
  const AppearanceDecision(this.brightness, this.description);

  final Brightness brightness;
  final String description;
}

SolarPeriod solarPeriod(DateTime instant, SelectedLocation location) {
  final utc = instant.toUtc();
  final julianDay = utc.millisecondsSinceEpoch / 86400000 + 2440587.5;
  final centuries = (julianDay - 2451545) / 36525;
  final meanLongitude =
      (280.46646 + centuries * (36000.76983 + centuries * 0.0003032)) % 360;
  final meanAnomaly =
      357.52911 + centuries * (35999.05029 - 0.0001537 * centuries);
  final eccentricity =
      0.016708634 - centuries * (0.000042037 + 0.0000001267 * centuries);
  final equationOfCenter =
      math.sin(_radians(meanAnomaly)) *
          (1.914602 - centuries * (0.004817 + 0.000014 * centuries)) +
      math.sin(_radians(2 * meanAnomaly)) * (0.019993 - 0.000101 * centuries) +
      math.sin(_radians(3 * meanAnomaly)) * 0.000289;
  final apparentLongitude =
      meanLongitude +
      equationOfCenter -
      0.00569 -
      0.00478 * math.sin(_radians(125.04 - 1934.136 * centuries));
  final meanObliquity =
      23 +
      (26 +
              (21.448 -
                      centuries *
                          (46.815 +
                              centuries * (0.00059 - centuries * 0.001813))) /
                  60) /
          60;
  final obliquity =
      meanObliquity +
      0.00256 * math.cos(_radians(125.04 - 1934.136 * centuries));
  final declination = math.asin(
    math.sin(_radians(obliquity)) * math.sin(_radians(apparentLongitude)),
  );
  final tangent = math.tan(_radians(obliquity / 2));
  final obliquityFactor = tangent * tangent;
  final equationOfTime =
      4 *
      180 /
      math.pi *
      (obliquityFactor * math.sin(2 * _radians(meanLongitude)) -
          2 * eccentricity * math.sin(_radians(meanAnomaly)) +
          4 *
              eccentricity *
              obliquityFactor *
              math.sin(_radians(meanAnomaly)) *
              math.cos(2 * _radians(meanLongitude)) -
          0.5 *
              obliquityFactor *
              obliquityFactor *
              math.sin(4 * _radians(meanLongitude)) -
          1.25 *
              eccentricity *
              eccentricity *
              math.sin(2 * _radians(meanAnomaly)));
  final latitude = _radians(location.latitude);
  final horizon = math.sin(_radians(-0.833));
  final altitudeCenter = math.sin(latitude) * math.sin(declination);
  final altitudeRange = math.cos(latitude) * math.cos(declination);
  if (altitudeCenter - altitudeRange >= horizon) return SolarPeriod.polarDay;
  if (altitudeCenter + altitudeRange < horizon) return SolarPeriod.polarNight;
  final utcMinutes =
      utc.hour * 60 + utc.minute + utc.second / 60 + utc.millisecond / 60000;
  final solarMinutes =
      (utcMinutes + equationOfTime + 4 * location.longitude) % 1440;
  final hourAngle = _radians(solarMinutes / 4 - 180);
  final altitude = altitudeCenter + altitudeRange * math.cos(hourAngle);
  return altitude >= horizon ? SolarPeriod.day : SolarPeriod.night;
}

double _radians(double degrees) => degrees * math.pi / 180;

AppearanceDecision resolveAppearance(
  AppearanceSettings settings,
  DateTime instant,
  Brightness systemBrightness,
) {
  if (settings.mode == AppearanceMode.day) {
    return const AppearanceDecision(Brightness.light, 'Day · manual override');
  }
  if (settings.mode == AppearanceMode.night) {
    return const AppearanceDecision(Brightness.dark, 'Night · manual override');
  }
  final location = settings.location;
  if (location == null) {
    return AppearanceDecision(
      systemBrightness,
      'System appearance · no location selected',
    );
  }
  return switch (solarPeriod(instant, location)) {
    SolarPeriod.day => AppearanceDecision(
      Brightness.light,
      'Daylight · ${location.name}',
    ),
    SolarPeriod.night => AppearanceDecision(
      Brightness.dark,
      'After sunset · ${location.name}',
    ),
    SolarPeriod.polarDay => AppearanceDecision(
      Brightness.light,
      'Polar day · ${location.name}',
    ),
    SolarPeriod.polarNight => AppearanceDecision(
      Brightness.dark,
      'Polar night · ${location.name}',
    ),
  };
}
