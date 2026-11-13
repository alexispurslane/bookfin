import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

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
/// stuck workers it closes itself: every later job fails with
/// [WorkerStopped] at once, and no worker starts.
///
/// Invariants, which [checkInvariants] checks:
/// - The number of jobs in flight and the count of stuck workers are not
///   negative. Reaching the stuck-worker bound closes this owner.
/// - A closed owner retains no worker for new jobs and no idle timer.
///   A worker that is ending accepts no new jobs.
/// - An active idle timer belongs to an open owner with no jobs in flight.
/// - Each current or ending worker has a watch exactly while it has a
///   limit, has waiting jobs, and has not stopped.
/// - A stopped worker has no waiting jobs. No waiting job is complete.
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
  }) : _endState = end {
    if (limit != null && limit! <= Duration.zero) {
      throw ArgumentError.value(limit, 'limit', 'Must be positive.');
    }
  }

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
  /// The watch estimates time spent running. A delayed watch tick counts
  /// at most two seconds instead of the full gap while Android froze the
  /// process.
  /// Null gives every job all the time that it takes. A non-null limit must
  /// be positive, or construction throws [ArgumentError].
  final Duration? limit;

  /// How many stuck workers are abandoned before this worker gives up. A
  /// stuck worker can keep its thread and the memory of its state until the
  /// app stops, so their number needs a bound. One stuck call can be
  /// chance, such as a system service that starts again. After a second
  /// one, a third worker is likely to hang too.
  static const _mostStuck = 2;

  Future<_Running>? _running;
  // Workers running their final end job still belong to this owner.
  final _ending = <Future<_Running>, Future<void>>{};
  Timer? _stop;
  var _busy = 0;
  var _closed = false;

  /// The workers that were abandoned at their limit.
  var _stuck = 0;

  /// Whether this worker refuses every later job, after [close] or after
  /// it gave up on stuck workers.
  bool get closed => _closed;

  /// Whether the worker runs now, keeping its state in memory.
  bool get running => _running != null;

  /// What [job] gives for the worker's state. It throws what [job] throws,
  /// as a [RemoteError] when the error cannot travel back, and
  /// [WorkerStopped] when the worker stops first, is stuck past its
  /// [limit], is closed, or gave up after its stuck workers.
  Future<R> run<R>(FutureOr<R> Function(S state) job) async {
    if (_closed) throw WorkerStopped(name);
    _stop?.cancel();
    _stop = null;
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
    if (_closed) throw WorkerStopped(name);
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
      return _Running(isolate, replies, this);
    } catch (_) {
      replies.close();
      throw WorkerStopped(name);
    }
  }

  void _end() {
    assert(_busy == 0 && !_closed, 'Only an idle, open worker can idle out.');
    final running = _running;
    _running = null;
    _stop = null;
    // The final end job frees native state on its own isolate. It has the
    // same limit as any other job, including when this idle timer starts it.
    if (running != null) unawaited(_retire(running));
  }

  Future<void> _retire(Future<_Running> started) {
    assert(
      !identical(_running, started),
      'An ending worker takes no new jobs.',
    );
    return _ending.putIfAbsent(
      started,
      () => _stopAfterEnd(started).whenComplete(() {
        _ending.remove(started);
      }),
    );
  }

  /// Abandons one stuck isolate. This owner counts it and decides whether
  /// another worker may start. The isolate only owns its jobs and replies.
  void _abandon(_Running running) {
    assert(!running.stopped, 'A worker is abandoned only once.');
    _stuck++;
    running.stop();
    if (_stuck >= _mostStuck && !_closed) {
      unawaited(close());
      debugPrint('$name is off for this run: $_mostStuck workers were stuck.');
    }
  }

  /// Runs [_endState] after the jobs in flight, then stops the isolate.
  Future<void> _stopAfterEnd(Future<_Running> started) async {
    final _Running running;
    try {
      running = await started;
    } on WorkerStopped {
      return;
    }
    try {
      if (_endState case final end?) await running.run<void>(end);
    } on WorkerStopped {
      // The worker stopped already.
    } finally {
      running.stop();
    }
  }

  /// Stops the worker once the jobs in flight end. Later jobs fail.
  Future<void> close() async {
    _closed = true;
    _stop?.cancel();
    _stop = null;
    final running = _running;
    _running = null;
    if (running != null) unawaited(_retire(running));
    await Future.wait(_ending.values);
  }

  /// Throws a [StateError] when an invariant of the class comment does not
  /// hold. It runs on demand, in every build. It waits for isolate creation,
  /// but never for a job or for the worker to make its state.
  Future<void> checkInvariants() async {
    if (_busy < 0 || _stuck < 0 || _stuck >= _mostStuck && !_closed) {
      throw StateError('Job and stuck counts agree with closure.');
    }
    if (_closed && (_running != null || _stop != null)) {
      throw StateError('A closed worker has no current worker or idle timer.');
    }
    if (_running != null && _ending.containsKey(_running)) {
      throw StateError('An ending worker takes no new jobs.');
    }
    if ((_stop?.isActive ?? false) && (_busy != 0 || _closed)) {
      throw StateError('An idle timer belongs to an idle, open worker.');
    }
    final retained = {?_running, ..._ending.keys};
    for (final started in retained) {
      final _Running running;
      try {
        running = await started;
      } on WorkerStopped {
        // A failed spawn has no isolate, waiting jobs, or watch to check.
        continue;
      }
      running.checkInvariants();
    }
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
  _Running(this._isolate, this._replies, this._owner) {
    _replies.listen(_reply);
  }

  final Isolate _isolate;
  final ReceivePort _replies;
  final KeptWorker _owner;
  String get _name => _owner.name;
  Duration? get _limit => _owner.limit;
  final _waiting = <int, Completer<Object?>>{};
  final _jobs = Completer<SendPort>();
  var _next = 0;
  var _stopped = false;

  /// Counts running time after the hand-over of a job to an idle worker,
  /// or after the answer to the job before it.
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
      done.future.ignore();
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
    _watch = null;
    if (limit == null || _waiting.isEmpty || _stopped) return;
    final tick = limit < const Duration(seconds: 1)
        ? limit
        : const Duration(seconds: 1);
    var previous = 0;
    var elapsed = Duration.zero;
    _watch = Timer.periodic(tick, (timer) {
      // Timer.tick counts periods on the timer's monotonic clock. A large
      // gap can mean Android froze this process. Count at most two periods
      // per callback instead of charging the whole gap to this worker.
      elapsed += tick * (timer.tick - previous).clamp(0, 2);
      previous = timer.tick;
      if (elapsed >= limit) {
        _owner._abandon(this);
      }
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

  void checkInvariants() {
    if (!_watchFits()) {
      throw StateError('The watch runs exactly while a limited job waits.');
    }
    if (_stopped && _waiting.isNotEmpty ||
        _waiting.values.any((job) => job.isCompleted)) {
      throw StateError('Only a live worker holds incomplete waiting jobs.');
    }
  }

  /// Stops the isolate, and fails the jobs that wait for it. After it, no
  /// answer of this worker arrives: the port of its replies is closed, and
  /// each worker has a port and waiting jobs of its own. So a late answer
  /// cannot end a job of a later worker.
  ///
  /// NOTE: The kill takes effect only when the isolate runs Dart code
  /// again. A native call that never returns keeps its thread. Every
  /// abandoned speech worker also leaks its model, even if the call later
  /// returns: the kill skips the end job, and the model has no finalizer.
  /// The memory stays until the app stops. Ticket t2-p0cc tracks cleanup.
  /// No other isolate can end the native call.
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
