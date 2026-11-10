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

**2026-11-10T19:47:50Z**

Recurred in tb-22fu replacement checkout full run: required-tests-final.log finished with 2518 passed, 21 skipped, one failure at survey_session_test.dart:262 (saved survey file not yet present). The same test immediately passed alone in survey-rerun.log. No survey implementation/test changes made here; full rerun underway.

**2026-11-10T19:50:32Z**

The immediate focused rerun passed, followed by a clean full rerun in tb-22fu: 2519 passed, 21 skipped, zero failed (2m37s), full-rerun.log. Intermittent failure retained honestly; no out-of-scope fix attempted.
