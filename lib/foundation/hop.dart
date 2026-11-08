import 'dart:async';

/// Runs [work] on [input] in another isolate and completes with its result.
/// [compute] is the default in the app. Tests inject a hop that runs the work
/// inline or through [Isolate.run], because a hop never completes in the fake
/// time of a widget test.
typedef IsolateHop = Future<R> Function<M, R>(
  FutureOr<R> Function(M) work,
  M input,
);
