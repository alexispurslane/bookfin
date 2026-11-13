// Helpers for tests of a kept worker on a fake clock. The worker isolate is
// real, so a test holds a job with a port, not with time: no test waits
// for real seconds, and a busy machine changes no result.
import 'dart:async';
import 'dart:isolate';

/// A port of the test that notes the first message that a job sends.
class Signal {
  Signal() {
    _port.listen((message) {
      this.message = message;
      got = true;
    });
  }

  final _port = ReceivePort();

  /// Whether a message arrived, and the message.
  var got = false;
  Object? message;

  SendPort get send => _port.sendPort;

  void close() => _port.close();
}

/// What a job ended with: its value or its error. Both are null until it
/// ends.
class Ended<T> {
  T? value;
  Object? error;
  var ended = false;
}

/// Notes what [work] ends with, so that a test can read it after a pump.
Ended<T> ending<T>(Future<T> work) {
  final ended = Ended<T>();
  unawaited(
    work.then<void>(
      (value) {
        ended.value = value;
        ended.ended = true;
      },
      onError: (Object error) {
        ended.error = error;
        ended.ended = true;
      },
    ),
  );
  return ended;
}

/// Runs in the worker: sends [ready] the port that lets the job go on, and
/// completes at the first message to that port.
Future<void> held(SendPort ready) async {
  final release = ReceivePort();
  ready.send(release.sendPort);
  await release.first;
}

/// Lets the job go on that sent its port to [ready].
void release(Signal ready) => (ready.message! as SendPort).send(null);
