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
///
/// A worker with a [limit] that gives no answer for that long is stuck,
/// such as inside a native call that never returns. It counts as stopped:
/// its jobs fail with [WorkerStopped], it is abandoned, and the next job
/// starts a new worker, which does not wait for the stuck one. After two
/// stuck workers it gives up: every later job fails with [WorkerStopped] at
/// once, and no worker starts.
class KeptWorker<S> {
  /// [start] makes the state in the worker, at each start. [end] lets the
  /// state go before the worker stops, such as native memory, which the end
  /// of an isolate does not free. Both run in the worker, so they obey the
  /// rule of a job.
  KeptWorker(
    this._start, {
    required this.name,
    required this.idle,
    this.limit,
    FutureOr<void> Function(S state)? end,
  }) : _endState = end;

  final FutureOr<S> Function() _start;
  final FutureOr<void> Function(S state)? _endState;

  /// The name of the worker isolate, for debuggers and profiles.
  final String name;

  /// How long the worker stays without a job before it stops.
  final Duration idle;

  /// The longest time that the worker has for one job. The time counts from
  /// the answer to the job before it, or from the hand-over of the job when
  /// the worker has no other job. So the limit of the first job after a
  /// start also holds the start of the worker and the making of its state.
  /// Null gives every job all the time that it takes.
  final Duration? limit;

  /// How many stuck workers are abandoned before this worker gives up. A
  /// stuck worker can keep its thread and the memory of its state until the
  /// app stops, so their number needs a bound. One stuck call can be
  /// chance, such as a system service that starts again. After a second
  /// one, a third worker is likely to hang too.
  static const _mostStuck = 2;

  Future<_Running>? _running;
  Timer? _stop;
  var _busy = 0;
  var _closed = false;

  /// The workers that were abandoned at their limit.
  var _stuck = 0;

  /// Whether the worker runs now, keeping its state in memory.
  bool get running => _running != null;

  /// What [job] gives for the worker's state. It throws what [job] throws,
  /// as a [RemoteError] when the error cannot travel back, and
  /// [WorkerStopped] when the worker stops first, is stuck past its
  /// [limit], is closed, or gave up after its stuck workers.
  Future<R> run<R>(FutureOr<R> Function(S state) job) async {
    if (_closed || _stuck >= _mostStuck) throw WorkerStopped(name);
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
      return _Running(isolate, replies, name, limit, () => _stuck++);
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
/// outside a job, it could not start or make its state, or it gave no
/// answer within its limit. The next job starts a new worker, unless the
/// worker is closed or gave up after its stuck workers.
class WorkerStopped implements Exception {
  const WorkerStopped(this.name);

  /// The name of the worker.
  final String name;

  @override
  String toString() => 'WorkerStopped: the worker $name stopped.';
}

/// A started worker: its isolate, and the replies of its jobs.
///
/// Invariant: [_watch] runs exactly while the worker has a limit, has a job
/// that waits, and did not stop.
class _Running {
  _Running(
    this._isolate,
    this._replies,
    this._name,
    this._limit,
    this._onStuck,
  ) {
    _replies.listen(_reply);
  }

  final Isolate _isolate;
  final ReceivePort _replies;
  final String _name;
  final Duration? _limit;

  /// Tells the owner that this worker is abandoned at its limit.
  final void Function() _onStuck;
  final _waiting = <int, Completer<Object?>>{};
  final _jobs = Completer<SendPort>();
  var _next = 0;
  var _stopped = false;

  /// Ends at [_limit] after the last sign of work: the hand-over of a job
  /// to a worker without one, or the answer to the job before.
  Timer? _watch;

  /// Whether the isolate stopped, so that no job runs on it again.
  bool get stopped => _stopped;

  Future<R> run<R>(Function job) async {
    if (_stopped) throw WorkerStopped(_name);
    final id = _next++;
    final done = _waiting[id] = Completer<Object?>();
    // A job behind another one waits for the answer before it.
    if (_waiting.length == 1) _watchAgain();
    assert(_watchFits(), 'The watch runs exactly while a job waits.');
    try {
      (await _jobs.future).send((id, job));
    } catch (_) {
      if (_waiting.remove(id) != null && _waiting.isEmpty) _watchAgain();
      rethrow;
    }
    return await done.future as R;
  }

  void _reply(Object? message) {
    switch (message) {
      case final SendPort jobs:
        _jobs.complete(jobs);
      case (final int id, true, final Object? result):
        _answered(id)?.complete(result);
      case (final int id, false, final Object error, final String stack):
        _answered(id)?.completeError(error, StackTrace.fromString(stack));
      case null || [_, _]:
        // The isolate exited, or failed outside a job.
        _fail();
    }
    assert(_watchFits(), 'The watch runs exactly while a job waits.');
  }

  /// The job [id] that waited for the answer that arrived. The worker is
  /// at work, so the limit counts anew for the job behind it.
  Completer<Object?>? _answered(int id) {
    final done = _waiting.remove(id);
    _watchAgain();
    return done;
  }

  /// Counts the limit from now when a job waits, and not at all otherwise.
  void _watchAgain() {
    _watch?.cancel();
    final limit = _limit;
    _watch = limit == null || _waiting.isEmpty || _stopped
        ? null
        : Timer(limit, () {
            _onStuck();
            stop();
          });
  }

  void _fail() {
    if (_stopped) return;
    _stopped = true;
    _watchAgain();
    final error = WorkerStopped(_name);
    if (!_jobs.isCompleted) _jobs.completeError(error);
    for (final waiting in _waiting.values) {
      waiting.completeError(error);
    }
    _waiting.clear();
    _replies.close();
    assert(_watchFits(), 'A stopped worker has no watch.');
  }

  /// Whether the invariant of the class comment holds.
  bool _watchFits() =>
      (_watch?.isActive ?? false) ==
      (_limit != null && _waiting.isNotEmpty && !_stopped);

  /// Stops the isolate, and fails the jobs that wait for it. After it, no
  /// answer of this worker arrives: the port of its replies is closed, and
  /// each worker has a port and waiting jobs of its own. So a late answer
  /// cannot end a job of a later worker.
  ///
  /// NOTE: The kill takes effect only when the isolate runs Dart code
  /// again. An isolate that is stuck inside a native call that never
  /// returns keeps its thread and the memory of its state until the app
  /// stops. That leak is accepted, because a stuck call is rare, and no
  /// other isolate can end a native call.
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
