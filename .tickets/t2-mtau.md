---
id: t2-mtau
status: open
deps: []
links: []
created: 2026-11-13T02:09:42Z
type: bug
priority: 3
assignee: Alexis Purslane
parent: boo-fs0n
---
# Keep the failure of a worker that sent no first message out of the uncaught errors

Found while reading lib/speech/worker.dart for boo-w69y. Nothing was run for this finding. Status: path read, trigger not seen and unlikely. In `_Running.run`, a job is put in `_waiting` before the worker sent its first message, the port for jobs. If the worker fails in that time (it exits, or it reaches its limit), `_fail` completes the answer of the job with an error. But `run` still waits for the port for jobs, so it throws from there and never listens to the answer. The error of the answer then has no listener and goes to the zone as an uncaught error. The job itself fails correctly with `WorkerStopped`. A test cannot reach the case with a real isolate, because the first message arrives together with the end of the spawn. A fix: ignore the answer of the job in the catch of `run`, or put the job in `_waiting` only after the port for jobs arrived and count the limit for the start in another way.


## Notes

**2026-11-13T02:44:16Z**

Fixed in the second boo-w69y change. _Running.run now calls done.future.ignore() before rethrowing a failure received while waiting for the worker job port. The caller still receives WorkerStopped. The unused answer future no longer sends a second error to the zone, which is the Dart context that receives uncaught asynchronous errors.

Reached the case with a real isolate and the existing held-job helpers. The test delays delivery of the first SendPort through a zone callback, then advances the fake clock to the limit. Without the ignore line, the new test named "a stop before the first worker message has no uncaught job error" failed because the zone received one WorkerStopped. With the line restored, it passes and the caller still receives WorkerStopped. This is deterministic message delivery control, not a new production option.

Verification through Nix: flutter test test/speech passed 113 tests. The final flutter test test/speech/worker_test.dart test/speech/speech_limit_test.dart passed 19 tests. The changed Dart files have no analyzer issues. Ticket remains open for the orchestrator to close after integration.
