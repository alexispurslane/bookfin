import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bookfin/speech/native.dart';
import 'package:flutter_test/flutter_test.dart';

// The fixtures hold 16.7 s of the first sentences of "Alice's Adventures
// in Wonderland", spoken by macOS's `say` and encoded with ffmpeg as mono
// 22.05 kHz MP3 and AAC at 32 kb/s.
const mp3 = 'test/speech/fixtures/alice.mp3';
const m4a = 'test/speech/fixtures/alice.m4a';

double rms(Float32List samples) {
  var sum = 0.0;
  for (final sample in samples) {
    sum += sample * sample;
  }
  return math.sqrt(sum / samples.length);
}

void main() {
  final library = SpeechLibrary.open();

  test('decodes a window of an MP3 audiobook file to 16 kHz mono speech', () {
    final samples = library!.decode(mp3, 2000, 3000)!;
    expect(samples.length, closeTo(48000, 480));
    expect(rms(samples), greaterThan(0.01));
    expect(samples.every((sample) => sample.abs() <= 1), isTrue);
  });

  test('decodes a window of an M4A audiobook file', () {
    final samples = library!.decode(m4a, 2000, 3000)!;
    expect(samples.length, closeTo(48000, 480));
    expect(rms(samples), greaterThan(0.01));
  });

  test('a window starts at its time, not at the file start', () {
    final long = library!.decode(mp3, 1000, 2000)!;
    final late = library.decode(mp3, 2000, 1000)!;
    // The second second of the long window is the late window.
    final tail = Float32List.sublistView(long, 16000, 16000 + late.length);
    var difference = 0.0;
    for (var index = 0; index < late.length; index++) {
      difference += (tail[index] - late[index]).abs();
    }
    final shifted = Float32List.sublistView(long, 0, late.length);
    var unrelated = 0.0;
    for (var index = 0; index < late.length; index++) {
      unrelated += (shifted[index] - late[index]).abs();
    }
    expect(difference, lessThan(unrelated * 0.2));
  });

  test('a window past the end of the file ends with the file', () {
    final samples = library!.decode(mp3, 15000, 8000)!;
    // The file lasts about 16.7 s.
    expect(samples.length, inInclusiveRange(16000, 40000));
  });

  test('a file that cannot be read decodes to nothing', () {
    expect(
      library!.decode('test/speech/fixtures/missing.mp3', 0, 1000),
      isNull,
    );
  });
}
