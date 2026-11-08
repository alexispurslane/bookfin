import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

/// Runs real and fake time in turns until [done] holds. A widget test runs
/// in fake time, in which an isolate hop never completes, so work that hops,
/// such as a catalog build, needs real time too. Each turn gives real time
/// until [done] holds or 5 ms pass, then pumps 10 ms of fake time, so timers
/// and frames run too. Fails the test when [done] does not hold after 1000
/// turns.
Future<void> runUntil(WidgetTester tester, bool Function() done) async {
  for (var turn = 0; !done() && turn < 1000; turn++) {
    await tester.runAsync(() async {
      final watch = Stopwatch()..start();
      while (!done() && watch.elapsedMilliseconds < 5) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    });
    if (done()) break;
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(done(), isTrue, reason: 'the work did not end in real time');
}

/// Runs real and fake time until [work] ends (see [runUntil]), and
/// completes like [work]. It notes the end in the root zone, so work that
/// ends in real time ends the wait without a pump of fake time.
Future<T> finish<T>(WidgetTester tester, Future<T> work) async {
  var ended = false;
  Zone.root.run(
    () => unawaited(
      work.then<void>((_) {}, onError: (Object _) {}).whenComplete(() {
        ended = true;
      }),
    ),
  );
  await runUntil(tester, () => ended);
  return work;
}
