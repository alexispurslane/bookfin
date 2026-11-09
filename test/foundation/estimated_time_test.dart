import 'package:bookfin/foundation/time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String shown(Duration time) => estimatedTime(time);

  test('an estimate under half a minute reads "less than 1 min"', () {
    expect(shown(Duration.zero), 'less than 1 min');
    expect(shown(const Duration(seconds: 29)), 'less than 1 min');
  });

  test('an estimate under ten minutes reads in whole minutes', () {
    expect(shown(const Duration(seconds: 31)), '1 min');
    expect(shown(const Duration(minutes: 6, seconds: 20)), '6 min');
    expect(shown(const Duration(minutes: 9, seconds: 20)), '9 min');
  });

  test('an estimate under an hour reads in steps of five minutes', () {
    expect(shown(const Duration(minutes: 12)), '10 min');
    expect(shown(const Duration(minutes: 23)), '25 min');
    expect(shown(const Duration(minutes: 57)), '55 min');
  });

  test('an estimate of an hour or more reads in hours and steps of ten '
      'minutes', () {
    expect(shown(const Duration(minutes: 58)), '1 h');
    expect(shown(const Duration(minutes: 78)), '1 h 20 min');
    expect(shown(const Duration(hours: 2, minutes: 56)), '3 h');
    expect(shown(const Duration(hours: 11, minutes: 4)), '11 h');
  });

  test('a rounded estimate stays as it is when it is rounded again', () {
    for (final minutes in [0, 1, 7, 13, 44, 61, 200]) {
      final once = roundEstimate(Duration(minutes: minutes, seconds: 17));
      expect(roundEstimate(once), once);
    }
  });
}
