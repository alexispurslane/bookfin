---
id: boo-w69y
status: closed
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

**2026-11-13T02:44:16Z**

Second implementation change after review. Cherry-picked 0440c8b2 onto this worktree as 5b82ddbb09a27f156afd35fb27795f1f60e8d1c0. Only the two documentation comments in speech.dart conflicted. The merge kept both class paragraphs, the main branch record-typed _hearing and hear body, and the 100-second worker limit. Later changes below replace _unloadable as requested.

B1: the watch now ticks once per second while jobs wait, or at the limit when it is less than one second. It uses Timer.tick to count elapsed timer periods and adds at most two periods per callback. A long frozen-process gap cannot consume the whole limit in one callback. Each answer still restarts the watch for the next queued job. No periodic timer exists without a waiting job. The capped tick is a cheap estimate of running time. It does not measure CPU time.

C1: zero and negative KeptWorker limits throw ArgumentError in every build. The class documents its invariants. Public checkInvariants checks them on demand in every build, including the watches and waiting jobs of current workers and workers running their final cleanup job. It waits for isolate creation, never for a job or state creation. Tests call it after starts, stops, queued work, recovery, cleanup and closure. Internal transition assertions compile out of release builds. A cleanup contract failure now reaches the caller instead of being swallowed.

S1: KeptWorker.closed is the one query for permanent worker closure. The owner increments its stuck count directly in _abandon and closes itself at the existing threshold. The callback that only incremented the counter is gone. Speech no longer stores _unloadable. It closes the worker after a failed model load and returns null for a missing model or a closed worker. A first stuck window still throws WorkerStopped. The window that makes the worker give up, and every later window, gives null. HeardWindows already treats both results as an unheard window. Its behavior is unchanged. Speech documentation refers to the worker rule instead of repeating the threshold.

L1: Flutter debugPrint records the cause once when a failed model load closes speech, or when stuck workers close their owner. Tests cover concurrent failed-load windows and later refused jobs. No interface was added. The search of lib found FlutterError.reportError but no direct debugPrint or dart:developer logger. This change uses the Flutter debugPrint function that Flutter error reporting also uses, without reporting an expected refusal as an application error.

M1: done.future.ignore() consumes the unused answer when waiting for the first job port fails. A real-isolate test delays that first port through its Dart zone, then triggers the limit. It reproduced the uncaught WorkerStopped before the fix. The test now verifies one handled caller failure and no uncaught error. Added the fix and evidence to t2-mtau.

Comments and cleanup: every abandoned speech model can leak because killing the isolate skips its end job and there is no native finalizer. A limit that is too short can therefore close speech under the give-up rule and leak each abandoned model. The idle-stop comment now says the final end job has the same limit. Cleanup jobs remain owned until they finish, so close also waits for a cleanup job already started by the idle timer. A hanging cleanup still reaches the limit and counts toward giving up. Contract failures are not caught as ordinary worker stops.

T1: the macOS named-pipe audio path reliably blocks the real Core Audio open. Speech accepts a limit with the same constructor pattern as idle. Its default remains 100 seconds. The native integration test uses three seconds on the fake clock, after loading the real model. It checks the first failed window, a replacement worker, the null result at the second hang and immediate null results afterward. A temporary deletion of limit: limit from the KeptWorker construction failed this test with no WorkerStopped at the deadline. Restoring it passed. Removing the null conversion after permanent closure also failed the test. No native source was changed. Pipe cleanup releases the abandoned calls. The native model leak remains the follow-up below.

Red evidence: both nonpositive-limit tests returned a worker instead of throwing. The eight-hour thaw test ended the job before its answer. The worker shutdown query stayed false after two hangs, including hangs in the final end job. Both log tests captured zero messages. Speech after close threw WorkerStopped instead of giving null. close returned immediately during an idle cleanup job. The startup test recorded one uncaught WorkerStopped. A failed end-job contract was swallowed. The explicit-close hanging-end test already passed the builder code, so a temporary change that removed the end job limit proved its sensitivity by leaving close pending after the limit. All temporary changes were removed. The 12 added tests now pass. The existing give-up test also checks closed after its second hang. Existing boo-737n tests were kept intact.

Exact final verification, all on macOS through the project Nix shell:
- nix develop --command flutter test test/speech --reporter expanded: 113 passed, 0 failed.
- nix develop --command flutter test test/crossings --reporter expanded: 57 passed, 0 failed.
- nix develop --command flutter test test/speech/worker_test.dart test/speech/speech_limit_test.dart --reporter expanded: 19 passed, 0 failed after the final analyzer cleanup. This also repeats the real native pipe test.
- nix develop --command dart analyze lib/speech/worker.dart lib/speech/speech.dart lib/speech/book_search.dart lib/speech/heard_windows.dart test/speech/worker_test.dart test/speech/speech_test.dart test/speech/speech_limit_test.dart test/speech/held_jobs.dart test/speech/book_search_test.dart test/speech/heard_windows_test.dart: no issues.
- git diff --check: clean.
The shell printed that the iphoneos and iphonesimulator SDKs are absent. Host speech and crossings tests still passed. No device, emulator, full suite, coverage job or mutation campaign was run. No unrelated test failure occurred in the requested folder runs.

Created t2-p0cc for native model cleanup with NativeFinalizer, and t2-dd9v for retrying a transient speech landing failure instead of keeping null until downloads change. Both remain open. No required finding was rejected. The two-worker threshold, the 100-second default and equal limits for a tap and background work are unchanged. No user decision is needed to integrate this change. The orchestrator owns integration and ticket closure.

**2026-11-13T02:58:42Z**

Orchestrator continuation on Astra. The final review passed the production paths and required two corrections. Removed the new Speech.limit option, because production never supplies it. Speech again owns its 100-second policy directly.

Replaced the timing-dependent Core Audio FIFO test with test/speech/native_hang_test.dart and its native C fixture. The fixture counts entry inside the blocking FFI call. The test advances fake time only after observing native entry, proves that another isolate answers while the original call still blocks, and proves that two abandoned workers stop further work. Teardown permanently releases current and late native calls, joins owned work, and verifies native completion. Temporary directory cleanup is registered before compilation. This supersedes the earlier claim that a 200 ms delay proved Core Audio entry or that a brief FIFO writer guaranteed cleanup. The new test exercises the actual worker and a controlled native condition-variable hang, not a vendor decoder hang or an Android device.

Regression proof: temporarily removing _owner._abandon(this) made the native test fail with expected WorkerStopped but actual null; teardown completed and the original production file was restored. With the production deadline restored, the test passed. nix develop --command dart analyze lib/speech test/speech found no issues. nix develop --command flutter test test/speech test/crossings --no-pub --reporter expanded passed 170 tests. Full-suite integration check follows. Both final review findings are resolved without another fixer delegate.

**2026-11-13T03:09:08Z**

Orchestrator integration verified on main with source changes through 11266d7e. nix develop --command flutter test --no-pub --concurrency=4 --reporter expanded: 3114 passed, 25 skipped, 0 failed in 3m23s, exit 0. Log: /tmp/bookfin-astra-full-suite-fixed.log. The earlier full run exposed boo-9zgy; its deterministic test fix is integrated. No new device acceptance or coverage/mutation campaign is claimed. Integrated and closed by the orchestrator.
