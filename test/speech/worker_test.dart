// A kept worker runs jobs in a long-lived isolate. A worker that stops is
// a failure of the phone, not a bug: its jobs fail with an exception, and
// the next job starts a new worker instead of waiting for the dead one.
// A worker that gives no answer within its limit is stuck, such as in a
// native call that never returns. It counts as stopped too.
import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:bookfin/speech/worker.dart';
import 'package:flutter_test/flutter_test.dart';

import '../real_time.dart';
import 'held_jobs.dart';

int one() => 1;
int add(int state) => state + 1;
Never exit(int state) => Isolate.exit();
Never broken() => throw UnsupportedError('No model on this phone.');

/// A state that names the moment of its start, so that a test can tell one
/// worker from the next.
int stamp() => DateTime.now().microsecondsSinceEpoch;
int same(int state) => state;

/// A start that tells [started] that it runs, and then never gives a state.
Future<int> Function() endless(SendPort started) => () {
  started.send(null);
  return Completer<int>().future;
};

/// A job that tells [started] that it runs, and then gives no answer.
Future<int> Function(int) silent(SendPort started) => (state) {
  started.send(null);
  return Completer<int>().future;
};

/// A job that gives its state once the test lets it go on.
Future<int> Function(int) gated(SendPort ready) => (state) async {
  await held(ready);
  return state;
};

/// A job that blocks its isolate inside one native call, as a codec call
/// that hangs does: it reads from the silent socket at [port] until the
/// test closes it. Then it answers 99. Nothing can stop the isolate during
/// the call.
int Function(int) blocked(SendPort started, int port) => (state) {
  final socket = RawSynchronousSocket.connectSync(
    InternetAddress.loopbackIPv4,
    port,
  );
  started.send(null);
  try {
    socket.readSync(1);
  } on SocketException {
    // The test closed the socket.
  }
  return 99;
};

/// A local server that keeps each connection silent until [close], so that
/// a [blocked] job hangs for exactly as long as the test wants.
class Silence {
  Silence._(this._server) {
    _server.listen(_held.add);
  }

  static Future<Silence> open(WidgetTester tester) async => Silence._(
    (await tester.runAsync(
      () => ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
    ))!,
  );

  final ServerSocket _server;
  final _held = <Socket>[];

  int get port => _server.port;

  /// Ends the hang: every blocked read returns.
  void close() {
    for (final socket in _held) {
      socket.destroy();
    }
    unawaited(_server.close());
  }
}

const limit = Duration(seconds: 60);
const hour = Duration(hours: 1);

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

  // The tests below run on the fake clock of a widget test. `runUntil` and
  // `finish` give the worker isolate real time, and move the fake clock by
  // at most 10 s, so each test keeps more than 10 s away from the limit.
  group('a worker with a limit of 60 s', () {
    late KeptWorker<int> worker;
    late Signal started;

    // NOTE: Each test closes its worker in its body. A tear-down runs
    // outside the fake clock, where the close of a worker that was made
    // inside it never completes.
    KeptWorker<int> limited(FutureOr<int> Function() start) =>
        KeptWorker<int>(start, name: 'test', idle: hour, limit: limit);

    setUp(() {
      started = Signal();
      addTearDown(started.close);
    });

    testWidgets('fails a job that gets no answer within the limit, and not '
        'sooner', (tester) async {
      worker = limited(one);
      final stuck = ending(worker.run(silent(started.send)));
      await runUntil(tester, () => started.got);
      await tester.pump(const Duration(seconds: 40));
      expect(stuck.ended, isFalse, reason: 'the limit did not pass yet');
      await tester.pump(const Duration(seconds: 20));
      expect(stuck.error, isA<WorkerStopped>());
      await finish(tester, worker.close());
    });

    testWidgets('runs the next job on a new worker while the stuck worker '
        'still blocks', (tester) async {
      final silence = await Silence.open(tester);
      addTearDown(silence.close);
      worker = limited(stamp);
      final first = await finish(tester, worker.run(same));
      final stuck = ending(worker.run(blocked(started.send, silence.port)));
      await runUntil(tester, () => started.got);
      await tester.pump(limit);
      expect(stuck.error, isA<WorkerStopped>());
      final second = await finish(tester, worker.run(same));
      expect(second, isNot(first));
      await finish(tester, worker.close());
    });

    testWidgets('a stuck worker whose call returns after the limit changes '
        'nothing', (tester) async {
      final silence = await Silence.open(tester);
      addTearDown(silence.close);
      worker = limited(one);
      final stuck = ending(worker.run(blocked(started.send, silence.port)));
      await runUntil(tester, () => started.got);
      await tester.pump(limit);
      expect(stuck.error, isA<WorkerStopped>());
      final ready = Signal();
      addTearDown(ready.close);
      final next = ending(worker.run(gated(ready.send)));
      await runUntil(tester, () => ready.got);
      // The call of the abandoned worker returns now, during the next job.
      silence.close();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      expect(next.ended, isFalse, reason: 'the late answer ended the next job');
      release(ready);
      await runUntil(tester, () => next.ended);
      expect(next.value, 1);
      await finish(tester, worker.close());
    });

    testWidgets('gives a job that waits behind another the whole limit, '
        'counted from the answer before it', (tester) async {
      worker = limited(one);
      final readyOne = Signal();
      final readyTwo = Signal();
      addTearDown(readyOne.close);
      addTearDown(readyTwo.close);
      final first = ending(worker.run(gated(readyOne.send)));
      final second = ending(worker.run(gated(readyTwo.send)));
      await runUntil(tester, () => readyOne.got);
      await tester.pump(const Duration(seconds: 30));
      release(readyOne);
      await runUntil(tester, () => first.ended && readyTwo.got);
      expect(first.value, 1);
      // More than 60 s after the hand-over of both jobs, and less than 60 s
      // after the answer to the first.
      await tester.pump(const Duration(seconds: 35));
      expect(second.ended, isFalse);
      release(readyTwo);
      await runUntil(tester, () => second.ended);
      expect(second.value, 1);
      await finish(tester, worker.close());
    });

    testWidgets('counts the start of the worker in the limit of its first '
        'job', (tester) async {
      worker = limited(endless(started.send));
      final first = ending(worker.run(add));
      await runUntil(tester, () => started.got);
      await tester.pump(limit);
      expect(first.error, isA<WorkerStopped>());
      await finish(tester, worker.close());
    });

    testWidgets('fails every job at once after two stuck workers, and '
        'starts no third worker', (tester) async {
      worker = limited(one);
      for (var hang = 0; hang < 2; hang++) {
        final again = Signal();
        addTearDown(again.close);
        final stuck = ending(worker.run(silent(again.send)));
        await runUntil(tester, () => again.got);
        await tester.pump(limit);
        expect(stuck.error, isA<WorkerStopped>());
      }
      final refused = ending(worker.run(silent(started.send)));
      await tester.pump();
      expect(refused.error, isA<WorkerStopped>());
      // Real time, in which a third worker would start and take the job.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(started.got, isFalse, reason: 'a third worker ran the job');
      await finish(tester, worker.close());
    });
  });

  testWidgets('a worker without a limit waits for a slow job', (tester) async {
    final worker = KeptWorker<int>(one, name: 'test', idle: hour);
    final ready = Signal();
    addTearDown(ready.close);
    final slow = ending(worker.run(gated(ready.send)));
    await runUntil(tester, () => ready.got);
    await tester.pump(const Duration(hours: 5));
    expect(slow.ended, isFalse);
    release(ready);
    await runUntil(tester, () => slow.ended);
    expect(slow.value, 1);
    await finish(tester, worker.close());
  });
}
