// A kept worker runs jobs in a long-lived isolate. A worker that stops is
// a failure of the phone, not a bug: its jobs fail with an exception, and
// the next job starts a new worker instead of waiting for the dead one.
import 'dart:isolate';

import 'package:bookfin/speech/worker.dart';
import 'package:flutter_test/flutter_test.dart';

int one() => 1;
int add(int state) => state + 1;
Never exit(int state) => Isolate.exit();
Never broken() => throw UnsupportedError('No model on this phone.');

void main() {
  test('a worker that stops during a job fails the job with an exception, '
      'and the next job starts a new worker', () async {
    final worker = KeptWorker<int>(
      one,
      name: 'test',
      idle: const Duration(seconds: 1),
    );
    addTearDown(worker.close);
    await expectLater(worker.run(exit), throwsA(isA<WorkerStopped>()));
    expect(await worker.run(add).timeout(const Duration(seconds: 5)), 2);
  });

  test('a worker that cannot make its state fails every job with an '
      'exception', () async {
    final worker = KeptWorker<int>(
      broken,
      name: 'test',
      idle: const Duration(seconds: 1),
    );
    addTearDown(worker.close);
    for (var job = 0; job < 2; job++) {
      await expectLater(
        worker.run(add).timeout(const Duration(seconds: 5)),
        throwsA(isA<WorkerStopped>()),
      );
    }
  });
}
