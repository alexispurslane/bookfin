// Core Audio is the host decoder whose blocked open this test exercises.
@TestOn('mac-os')
library;

import 'dart:io';

import 'package:bookfin/speech/speech.dart';
import 'package:bookfin/speech/worker.dart';
import 'package:flutter_test/flutter_test.dart';

import '../real_time.dart';
import 'held_jobs.dart';

void main() {
  testWidgets(
    'a native audio hang reaches the speech limit, then giving up hears nothing',
    (tester) async {
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('bookfin-speech-pipe-'),
      ))!;
      final pipe = '${directory.path}/audio.mp3';
      final made = (await tester.runAsync(
        () => Process.run('mkfifo', [pipe]),
      ))!;
      expect(made.exitCode, 0, reason: '${made.stderr}');
      final speech = Speech(
        locate: findSpeechModel,
        idle: const Duration(hours: 1),
        limit: const Duration(seconds: 3),
      );
      try {
        // Load the real model before testing the native decoder. No words
        // lie after the end of this short fixture.
        await finish(
          tester,
          speech.hear('test/speech/fixtures/alice.mp3', 30000, 8000),
        );
        expect(speech.loaded, isTrue);
        final stuck = ending(speech.hear(pipe, 0, 8000));
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
        await tester.pump();
        expect(stuck.ended, isFalse, reason: 'the native open must still wait');
        await tester.pump(const Duration(seconds: 3));
        expect(stuck.error, isA<WorkerStopped>());
        // A single stuck window permits a new worker with a fresh model.
        await finish(
          tester,
          speech.hear('test/speech/fixtures/alice.mp3', 30000, 8000),
        );
        expect(speech.loaded, isTrue);
        final last = ending(speech.hear(pipe, 0, 8000));
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
        await tester.pump();
        expect(last.ended, isFalse);
        await tester.pump(const Duration(seconds: 3));
        expect(last.ended, isTrue);
        expect(last.error, isNull);
        expect(last.value, isNull);
        expect(speech.loaded, isFalse);
        final later = ending(speech.hear(pipe, 0, 8000));
        await tester.pump();
        expect(later.ended, isTrue);
        expect(later.error, isNull);
        expect(later.value, isNull);
        expect(speech.loaded, isFalse);
      } finally {
        // Opening both ends cannot block, even if a failing test never sent
        // a reader. It releases the native open before deleting the pipe.
        await tester.runAsync(
          () => Process.run('python3', [
            '-c',
            'import os, sys; fd = os.open(sys.argv[1], os.O_RDWR | os.O_NONBLOCK); os.close(fd)',
            pipe,
          ]),
        );
        await tester.pump(const Duration(seconds: 100));
        await finish(tester, speech.close());
        await tester.runAsync(() => directory.delete(recursive: true));
      }
    },
  );
}
