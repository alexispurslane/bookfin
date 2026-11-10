---
id: boo-7plj
status: in_progress
deps: []
links: []
created: 2026-11-10T16:34:17Z
type: bug
priority: 2
assignee: Alexis Purslane
parent: boo-fval
---
# Make the survey resume test pass under a full test run

test/reader/survey_session_test.dart 'a reopened book goes on with the survey that it kept beside the download' failed once in a full flutter test run on main after merging t1-6pf5 (2026-11-10, Mac load about 8). It passed alone three times and in the next full run at load 30. Find the timing assumption (a fixed pause, or a wait on work that a loaded host runs later) and wait on the event instead.


## Notes

**2026-11-10T17:12:25Z**

Failed again in a full run on 2026-11-10 at load 23, after merging tb-xjfi; passed alone. Second failure in about four full runs.

**2026-11-10T19:09:25Z**

Resumed with GPT 6.1 Sol xhigh. taskId: node:delegated-task:command%3Amcp%3Ae6a3d378-c450-4501-a47c-77e7994db5fb%3Adelegate-task%3Asol-xhigh-resume-20261110-boo-7plj-1; childThreadId: thread:delegated-task:command%3Amcp%3Ae6a3d378-c450-4501-a47c-77e7994db5fb%3Adelegate-task%3Asol-xhigh-resume-20261110-boo-7plj-1; clientRequestId: sol-xhigh-resume-20261110-boo-7plj-1. Separate T3 worktree; build/recovery, fresh Sol xhigh review, then fixes. Parent integrates and closes.

**2026-11-10T19:51:00Z**

Recurrence in tb-nkz5 full flutter test on branch t3/pdf-trim-margins, ce7ddc2, 2026-11-10. Exact failing test: survey_session_test.dart / a reopened book goes on with the survey that it kept beside the download. This run follows the fix of seven settings-scroll selector assumptions in unrelated viewport test harnesses; those 23 focused tests pass. Evidence /tmp/tb-nkz5-full-final.log; full run still finishing. No production changes to the survey were made by tb-nkz5.
