// A place in a recording reads as a clock reads it, as the approved mockup
// shows it: no leading zero, and hours only from an hour on.
import 'package:bookfin/foundation/time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a place under an hour reads without a leading zero', () {
    expect(audioTime(30000), '0:30');
    expect(audioTime(60000), '1:00');
    expect(audioTime(760000), '12:40');
  });

  test('a place from an hour on reads with its hours', () {
    expect(audioTime(3600000), '1:00:00');
    expect(audioTime(3735000), '1:02:15');
  });

  test('a place before the start reads as the start', () {
    expect(audioTime(-5000), '0:00');
  });
}
