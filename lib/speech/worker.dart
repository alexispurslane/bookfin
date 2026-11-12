import 'dart:async';
import 'dart:isolate';

/// One long-lived worker isolate that keeps a state of type [S] and runs
/// jobs on it, one at a time, in the order that they arrive. It starts at
/// the first job and stops after [idle] without one, so that the memory of
/// its state goes back to the phone. The next job starts it again, with a
/// new state.
///
/// A job is a closure that the worker runs. It travels to the worker, so it
/// must capture only data that isolates can send: no data source, no
/// widget, no native handle. Its result travels back the same way.
///
/// A worker can stop by itself: it exits, it fails outside a job, or it
/// cannot make its state. Its jobs then fail with [WorkerStopped], and the
/// next job starts a new worker.
class KeptWorker<S> {
  /// [start] makes the state in the worker, at each start. [end] lets the
  /// state go before the worker stops, such as native memory, which the end
  /// of an isolate does not free. Both run in the worker, so they obey the
  /// rule of a job.
  KeptWorker(
    this._start, {
    required this.name,
    required this.idle,
    FutureOr<void> Function(S state)? end,
  }) : _endState = end;

  final FutureOr<S> Function() _start;
  final FutureOr<void> Function(S state)? _endState;

  /// The name of the worker isolate, for debuggers and profiles.
  final String name;

  /// How long the worker stays without a job before it stops.
  final Duration idle;

  Future<_Running>? _running;
  Timer? _stop;
  var _busy = 0;
  var _closed = false;

  /// Whether the worker runs now, keeping its state in memory.
  bool get running => _running != null;

  /// What [job] gives for the worker's state. It throws what [job] throws,
  /// as a [RemoteError] when the error cannot travel back, and
  /// [WorkerStopped] when the worker stops first or is closed.
  Future<R> run<R>(FutureOr<R> Function(S state) job) async {
    if (_closed) throw WorkerStopped(name);
    _stop?.cancel();
    _busy++;
    try {
      return await (await _started()).run(job);
    } finally {
      if (--_busy == 0 && !_closed) {
        _stop = Timer(idle, _end);
      }
    }
  }

  /// The worker that runs now, else a new one. A worker that stopped, or
  /// that could not start, is forgotten, so that this job starts a new one.
  Future<_Running> _started() async {
    if (_running case final started?) {
      try {
        final running = await started;
        if (!running.stopped) return running;
      } on WorkerStopped {
        // It could not start.
      }
      if (identical(_running, started)) _running = null;
    }
    return _running ??= _spawn();
  }

  Future<_Running> _spawn() async {
    final replies = ReceivePort();
    final start = _start;
    try {
      final isolate = await Isolate.spawn<(SendPort, FutureOr<S> Function())>(
        _serve<S>,
        (replies.sendPort, start),
        debugName: name,
        onError: replies.sendPort,
        onExit: replies.sendPort,
      );
      return _Running(isolate, replies, name);
    } catch (_) {
      replies.close();
      throw WorkerStopped(name);
    }
  }

  void _end() {
    final running = _running;
    _running = null;
    _stop = null;
    if (running != null) unawaited(_stopAfterEnd(running));
  }

  /// Runs [_endState] after the jobs in flight, then stops the isolate.
  Future<void> _stopAfterEnd(Future<_Running> started) async {
    final _Running running;
    try {
      running = await started;
    } catch (_) {
      return;
    }
    if (_endState case final end?) {
      try {
        await running.run<void>(end);
      } catch (_) {
        // The worker stopped already.
      }
    }
    running.stop();
  }

  /// Stops the worker once the jobs in flight end. Later jobs fail.
  Future<void> close() async {
    _closed = true;
    _stop?.cancel();
    final running = _running;
    _running = null;
    if (running != null) await _stopAfterEnd(running);
  }
}

/// The worker isolate stopped before a job ended: it exited, it failed
/// outside a job, or it could not start or make its state. The next job
/// starts a new worker.
class WorkerStopped implements Exception {
  const WorkerStopped(this.name);

  /// The name of the worker.
  final String name;

  @override
  String toString() => 'WorkerStopped: the worker $name stopped.';
}

/// A started worker: its isolate, and the replies of its jobs.
class _Running {
  _Running(this._isolate, this._replies, this._name) {
    _replies.listen(_reply);
  }

  final Isolate _isolate;
  final ReceivePort _replies;
  final String _name;
  final _waiting = <int, Completer<Object?>>{};
  final _jobs = Completer<SendPort>();
  var _next = 0;
  var _stopped = false;

  /// Whether the isolate stopped, so that no job runs on it again.
  bool get stopped => _stopped;

  Future<R> run<R>(Function job) async {
    if (_stopped) throw WorkerStopped(_name);
    final id = _next++;
    final done = _waiting[id] = Completer<Object?>();
    try {
      (await _jobs.future).send((id, job));
    } catch (_) {
      _waiting.remove(id);
      rethrow;
    }
    return await done.future as R;
  }

  void _reply(Object? message) {
    switch (message) {
      case final SendPort jobs:
        _jobs.complete(jobs);
      case (final int id, true, final Object? result):
        _waiting.remove(id)?.complete(result);
      case (final int id, false, final Object error, final String stack):
        _waiting.remove(id)?.completeError(error, StackTrace.fromString(stack));
      case null || [_, _]:
        // The isolate exited, or failed outside a job.
        _fail();
    }
  }

  void _fail() {
    if (_stopped) return;
    _stopped = true;
    final error = WorkerStopped(_name);
    if (!_jobs.isCompleted) _jobs.completeError(error);
    for (final waiting in _waiting.values) {
      waiting.completeError(error);
    }
    _waiting.clear();
    _replies.close();
  }

  void stop() {
    _isolate.kill(priority: Isolate.immediate);
    _fail();
  }
}

/// The worker's loop: it makes the state, then runs each job on it in turn
/// and sends back its result or its error.
Future<void> _serve<S>((SendPort, FutureOr<S> Function()) setup) async {
  final (replies, start) = setup;
  final jobs = ReceivePort();
  replies.send(jobs.sendPort);
  final state = await start();
  await for (final message in jobs) {
    final (id, job) = message as (int, Function);
    try {
      final result = await (job as FutureOr<Object?> Function(S))(state);
      replies.send((id, true, result));
    } catch (error, stack) {
      Object sent = error;
      try {
        replies.send((id, false, error, stack.toString()));
        continue;
      } on ArgumentError {
        sent = RemoteError(error.toString(), stack.toString());
      }
      replies.send((id, false, sent, stack.toString()));
    }
  }
}
