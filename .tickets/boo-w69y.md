---
id: boo-w69y
status: in_progress
deps: []
links: []
created: 2026-11-12T23:41:02Z
type: bug
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Give a speech job a deadline

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: path confirmed, trigger plausible. lib/speech/heard_windows.dart:292-305 and lib/speech/worker.dart:170. `_running` clears only when the worker replies or its isolate exits. A native call that never returns (a vendor codec stop, a binder call) stops every later window, Go to and fill until the app restarts. Fail the job with `WorkerStopped` at a deadline of about ten times the median window time and abandon that worker, so the next job starts a new one.


## Notes

**2026-11-13T02:10:01Z**

What changed. KeptWorker (lib/speech/worker.dart) has a new property, limit: the longest time that the worker has for one job. The time counts from the answer to the job before, or from the hand-over of the job when the worker had no job, so the first job after a start also holds the start of the worker and the making of its state. A worker that gives no answer within the limit counts as stopped: its jobs fail with WorkerStopped, its isolate gets a kill, the port of its replies closes, and the next job starts a new worker. After two stuck workers the KeptWorker gives up, and every later job fails with WorkerStopped at once. Speech (lib/speech/speech.dart) gives its worker a limit of 100 s. The source is the emulator measurement in docs/plans/cross-edition-places.md (t2-4ci0): 3.1 s at the median in the background, 10.3 s at the median for a tap, 18.2 s for the slowest window, 106 to 253 ms for the model load. The book word search passes no limit and keeps its behavior. HeardWindows has no new state: a hearing that fails was already a failed window, so its invariants did not change. A stuck native call keeps its thread and the model until the app stops. The bound of two stuck workers limits that leak. New ticket t2-mtau records a latent edge that I found and did not change.

Verification, all through nix develop. flutter test test/speech test/crossings: 146 tests passed. dart analyze lib/speech and the four changed test files: no issues. flutter test test/speech/worker_test.dart test/speech/book_search_test.dart three times at a machine load near 30: 16 tests passed each time. Red first: with an inert limit parameter, five worker tests failed at their expectation of WorkerStopped with the actual value null. After the limit worked, the test of the bound of two stuck workers still failed in the same way until the bound was written. Two temporary changes, both reverted, showed that the tests that passed at once can fail: a limit that is not counted anew at an answer fails the test of a job that waits behind another, and a limit of 100 s on the book word search fails the test of a slow first read. The fake clock is the clock of a widget test with test/real_time.dart, so no test waits for real seconds.
