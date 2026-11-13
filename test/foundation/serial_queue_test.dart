import 'dart:async';

import 'package:bookfin/foundation/serial_queue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late SerialQueue queue;
  setUp(() => queue = SerialQueue());

  test('starts a run only after the run before it ended', () async {
    final log = <String>[];
    final firstCanEnd = Completer<void>();
    final first = queue.run(() async {
      log.add('first starts');
      await firstCanEnd.future;
      log.add('first ends');
    });
    final second = queue.run(() async => log.add('second starts'));

    await pumpEventQueue();
    expect(log, ['first starts']);

    firstCanEnd.complete();
    await Future.wait([first, second]);
    expect(log, ['first starts', 'first ends', 'second starts']);
  });

  test('gives the caller of a run the failure of its work', () async {
    await expectLater(
      queue.run(() async => throw StateError('A bug in the work.')),
      throwsStateError,
    );
    await expectLater(
      queue.run(() async => throw const FormatException('Bad data.')),
      throwsFormatException,
    );
  });

  test('runs the work that was queued after a failed run', () async {
    final failed = queue.run(
      () async => throw StateError('A bug in the work.'),
    );
    var ran = false;
    final later = queue.run(() async {
      ran = true;
    });

    await expectLater(failed, throwsStateError);
    await later;
    expect(ran, isTrue);
  });

  test('completes a later call without the earlier failure', () async {
    await expectLater(
      queue.run(() async => throw StateError('A bug in the work.')),
      throwsStateError,
    );

    await expectLater(queue.run(() async {}), completes);
  });

  group('idle', () {
    test('completes when every run queued so far has ended', () async {
      final canEnd = Completer<void>();
      var ended = 0;
      for (var index = 0; index < 2; index++) {
        unawaited(
          queue.run(() async {
            await canEnd.future;
            ended++;
          }),
        );
      }
      var idle = false;
      unawaited(queue.idle.then((_) => idle = true));

      await pumpEventQueue();
      expect(idle, isFalse);

      canEnd.complete();
      await queue.idle;
      expect(ended, 2);
    });

    test('completes normally after a run that failed', () async {
      final failed = queue.run(
        () async => throw StateError('A bug in the work.'),
      );

      await queue.idle;

      await expectLater(failed, throwsStateError);
    });

    test('does not wait for a run that was queued after it was read', () async {
      final idle = queue.idle;
      final neverEnds = Completer<void>();
      unawaited(queue.run(() => neverEnds.future));

      await idle.timeout(const Duration(seconds: 5));
    });
  });

  test(
    'reports the failure of a run that nothing awaits once, to the zone',
    () async {
      final uncaught = <Object>[];
      final done = Completer<void>();
      runZonedGuarded(() async {
        final queue = SerialQueue();
        try {
          unawaited(
            queue.run(() async => throw StateError('A bug in the work.')),
          );
          await queue.run(() async {});
          await queue.idle;
          await pumpEventQueue();
        } finally {
          done.complete();
        }
      }, (error, stack) => uncaught.add(error));
      await done.future;

      expect(uncaught, [isStateError]);
    },
  );
}
