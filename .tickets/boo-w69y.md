---
id: boo-w69y
status: open
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

