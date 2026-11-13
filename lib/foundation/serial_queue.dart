import 'dart:async';

/// Runs pieces of asynchronous work one at a time, in the order of the
/// calls to [run].
///
/// A failed run never stops a later run. The failure of a run goes only to
/// the future of that run. The queue itself never fails, so no code that
/// waits for the queue can receive the failure of work that it did not
/// start.
final class SerialQueue {
  // Completes when the latest queued run has ended. It never fails.
  Future<void> _last = Future.value();

  /// Starts [work] after every run that was queued before it has ended.
  ///
  /// The returned future completes as [work] completed: normally, or
  /// with its failure. A failure of any type goes only there. It reaches
  /// the caller, or the zone when the caller drops the future. It does not
  /// reach [idle] or a later run.
  ///
  /// Work that queues another run on this queue and awaits it never
  /// completes. The new run waits for the current run to end, so the
  /// current run waits for itself. Waiting for [idle] inside work has the
  /// same problem.
  Future<void> run(Future<void> Function() work) {
    final result = Completer<void>();
    _last = _last.then((_) async {
      try {
        await work();
        result.complete();
      } catch (error, stack) {
        // This hands the failure to the caller of this run. It does not
        // recover from it.
        result.completeError(error, stack);
      }
    });
    return result.future;
  }

  /// Completes when every run that was queued before this read has ended.
  /// It never fails, and it does not wait for a run that is queued later.
  Future<void> get idle => _last;
}
