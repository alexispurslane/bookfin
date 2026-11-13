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

