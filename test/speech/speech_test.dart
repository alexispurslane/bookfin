// The Linux dev shell has no audio decoder yet (t2-vhnz).
@TestOn('!linux')
library;

import 'dart:async';

import 'package:bookfin/speech/speech.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';

// The fixture holds 16.7 s of narration: "Alice was beginning to get very
// tired of sitting by her sister on the bank, and of having nothing to do.
// Once or twice she had peeped into the book her sister was reading, ..."
const mp3 = 'test/speech/fixtures/alice.mp3';

void main() {
  late Speech speech;
  setUp(() => speech = Speech(locate: findSpeechModel));
  tearDown(() => speech.close());

  test('hears the words of a window of narration', () async {
    final heard = (await speech.hear(mp3, 0, 8000))!;
    expect(heard.words.join(' '), contains('alice was beginning to get very'));
  });

  test('each heard word carries its time from the window start', () async {
    final heard = (await speech.hear(mp3, 0, 8000))!;
    for (var index = 1; index < heard.ms.length; index++) {
      expect(heard.ms[index], greaterThanOrEqualTo(heard.ms[index - 1]));
    }
    expect(heard.ms.last, lessThanOrEqualTo(8000));
    // "tired" is spoken about two seconds in.
    expect(
      heard.ms[heard.words.indexOf('tired')],
      inInclusiveRange(1000, 4000),
    );
  });

  test('a later window hears later words', () async {
    final heard = (await speech.hear(mp3, 8000, 8000))!;
    expect(heard.words, contains('sister'));
    // "beginning" is spoken in the first sentence only.
    expect(heard.words, isNot(contains('beginning')));
  });

  test('a window past the end of the file hears nothing', () async {
    expect(await speech.hear(mp3, 30000, 8000), isNull);
  });

  test('a build without the speech model hears nothing', () async {
    final without = Speech(locate: () async => null);
    addTearDown(without.close);
    expect(await without.hear(mp3, 0, 8000), isNull);
  });

  test('speech that is off gives no words for later windows', () async {
    await speech.close();
    expect(await speech.hear(mp3, 0, 8000), isNull);
  });

  group('a phone that cannot load the speech model', () {
    // The native library gives no model for a file that it cannot open. It
    // gives the same answer on a phone whose CPU lacks an instruction that
    // the speech library needs.
    late Speech unloadable;
    setUp(() {
      unloadable = Speech(
        locate: () async =>
            (path: 'test/speech/fixtures/no_model.ggml', offset: 0, length: 0),
      );
      addTearDown(unloadable.close);
    });

    test('logs the cause once when the model cannot be loaded', () async {
      final messages = <String>[];
      final before = debugPrint;
      debugPrint = (message, {wrapWidth}) => messages.add(message ?? '');
      addTearDown(() => debugPrint = before);
      await Future.wait([
        unloadable.hear(mp3, 0, 8000),
        unloadable.hear(mp3, 8000, 8000),
      ]);
      expect(await unloadable.hear(mp3, 0, 8000), isNull);
      expect(messages, hasLength(1));
      expect(messages.single, contains('model could not be loaded'));
    });

    test('hears nothing, as a build without the speech model', () async {
      expect(await unloadable.hear(mp3, 0, 8000), isNull);
    });

    test('keeps no worker, so it does not load the model again for a later '
        'window', () async {
      expect(await unloadable.hear(mp3, 0, 8000), isNull);
      // Only a start of the worker loads the model.
      expect(unloadable.loaded, isFalse);
      expect(await unloadable.hear(mp3, 8000, 8000), isNull);
      expect(unloadable.loaded, isFalse);
    });
  });

  test('the calling isolate keeps running while a window is heard', () async {
    var ticks = 0;
    final timer = Timer.periodic(
      const Duration(milliseconds: 5),
      (_) => ticks++,
    );
    final watch = Stopwatch()..start();
    await speech.hear(mp3, 0, 8000);
    timer.cancel();
    // A transcription that blocked this isolate would let no tick through.
    expect(ticks, greaterThan(watch.elapsedMilliseconds ~/ 20));
  });

  test('the model leaves memory when the speech worker idles', () async {
    final idle = Speech(
      locate: findSpeechModel,
      idle: const Duration(milliseconds: 50),
    );
    addTearDown(idle.close);
    await idle.hear(mp3, 0, 4000);
    expect(idle.loaded, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(idle.loaded, isFalse);
    expect((await idle.hear(mp3, 0, 4000))!.words, contains('alice'));
  });
}
