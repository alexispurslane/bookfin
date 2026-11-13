@TestOn('mac-os || linux')
library;

import 'dart:ffi';
import 'dart:io';

import 'package:bookfin/speech/worker.dart';
import 'package:flutter_test/flutter_test.dart';

import '../real_time.dart';
import 'held_jobs.dart';

int block(String library) =>
    DynamicLibrary.open(library)
        .lookupFunction<Int32 Function(), int Function()>('hang')();

String Function() keepPath(String path) =>
    () => path;

void main() {
  testWidgets('a worker stuck inside native code is replaced, then further '
      'native hangs stop new work', (tester) async {
    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('bookfin-native-hang-'),
    ))!;
    // Register cleanup before compilation, which can fail too.
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/hang.${Platform.isMacOS ? 'dylib' : 'so'}';
    final built = (await tester.runAsync(
      () => Process.run('cc', [
        '-std=c11',
        '-pthread',
        if (Platform.isMacOS) '-dynamiclib' else ...['-shared', '-fPIC'],
        'test/speech/native_hang.c',
        '-o',
        path,
      ]),
    ))!;
    expect(built.exitCode, 0, reason: '${built.stderr}');
    final library = DynamicLibrary.open(path);
    final entries = library.lookupFunction<Int32 Function(), int Function()>(
      'entries',
    );
    final exits = library.lookupFunction<Int32 Function(), int Function()>(
      'exits',
    );
    final release = library.lookupFunction<Void Function(), void Function()>(
      'release',
    );
    final worker = KeptWorker<String>(
      keepPath(path),
      name: 'native speech fixture',
      idle: const Duration(hours: 1),
      limit: const Duration(seconds: 100),
    );
    try {
      final stuck = ending(worker.run(block));
      await runUntil(tester, () => entries() == 1);
      expect(stuck.ended, isFalse);
      expect(exits(), 0);
      await tester.pump(const Duration(seconds: 100));
      expect(stuck.error, isA<WorkerStopped>());
      // The old call is still in native code. A new isolate can answer.
      expect(exits(), 0);
      expect(await finish(tester, worker.run((_) => 42)), 42);
      final last = ending(worker.run(block));
      await runUntil(tester, () => entries() == 2);
      await tester.pump(const Duration(seconds: 100));
      expect(last.error, isA<WorkerStopped>());
      expect(worker.closed, isTrue);
      final later = ending(worker.run(block));
      await tester.pump();
      expect(later.error, isA<WorkerStopped>());
      expect(entries(), 2);
      expect(exits(), 0);
    } finally {
      // Release is permanent, including for a call scheduled late after a
      // failed assertion. Close joins owned work before checking native exit.
      release();
      await finish(tester, worker.close());
      await runUntil(tester, () => exits() == entries());
    }
  });
}
