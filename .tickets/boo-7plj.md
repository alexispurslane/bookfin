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

**2026-11-10T19:25:28Z**

Build complete in /Users/alexispurslane/.t3/worktrees/bookfin/t3-9caa5df1, branch t3/fix-survey-session-flake. Review base: 9bf71644c0639f5fc201b756fb938eb1137b75be. The checkout started clean at that commit.

Cause: surveyed(pdf) waits for in-memory crops, not the survey file. BookSurvey._run notifies crop listeners before its unawaited save finishes. BookSurvey.close already waits for the running page and all queued writes. ReaderSession already orders reopening after document disposal. This is a test wait error, not a demonstrated production race.

The test now finishes page 1, holds page 2, closes the first book, and awaits disposal. Reading the real SurveyFiles store proves that page 1 was kept without a frozen profile. Reopening holds real SurveyFiles.write calls. The test waits for BookSurvey.close, releases the held writes, then reads the file and requires all eight pages and the frozen profile. The existing exactly-once layout expectation remains. No timeout increased, no expectation weakened, no production code changed. Failure cleanup releases the held write.

Red evidence: the original focused test passed once at baseline. Its old missing-file assertion then failed (Expected: true, Actual: false). That first attempted delay used the OCR hop rather than the survey-store hop, so it is an observed failure, not controlled-delay evidence. The deterministic reproduction gates the real SurveyFiles.write: with all crops known, the saved file still held [1] instead of [1,2,3,4,5,6,7,8]. After the close-and-save wait, it holds every page and the profile. An intermediate diagnostic counter used the OCR-only hop to count page analyses and failed 0 versus 8. It was removed as invalid instrumentation, not counted as behavior-red evidence.

Checks, all through nix develop and one heavy command at a time:
- flutter test test/reader/survey_session_test.dart --reporter expanded: PASS, 5 tests.
- dart format --output=none --set-exit-if-changed lib test tool integration_test: PASS, 389 files, 0 changes.
- flutter analyze lib test integration_test: PASS, no issues. The first run found use_super_parameters in the test helper constructor. That was fixed before the passing run.
- flutter test --concurrency=2 --reporter expanded: PASS, 2498 passed, 21 skipped, 3 minutes 30 seconds. This ran the whole suite, with two workers to avoid host saturation. No intermittent failure appeared in this run.

Logs: /tmp/bookfin-boo-7plj/{baseline,red-missing-file-observed,red-stale-survey,focused-green,format,analyze,final-static-checks,full-test}.log. Flutter reported missing iphoneos/iphonesimulator SDKs and newer incompatible package versions without failing the final checks. No native changes, so the native OCR worker script is not required. No device, coverage, or mutation work ran.

Inspected crop commit b4ec646ad8c1d560f8341f46e98e6eb2c4ed9b50. It adds a separate test before the existing survey tests and changes book_survey.dart/session.dart for crop behavior. Those production files are untouched here. Its added test is separate from this fix. No new work or product fork found. Ticket stays in progress for parent integration and closure. Fresh review follows.

**2026-11-10T19:35:15Z**

Fresh review complete for code commit dcb9f927edcde5ebdf1659233ad38800fe8c6623 against base 9bf71644c0639f5fc201b756fb938eb1137b75be. Reviewer: codex / gpt-6.1-sol / reasoningEffort=xhigh, shared checkout, read-only. The reviewer edited nothing, ran no builds or tests, and started no agents or devices.

Review thread: <t3-thread://v2/38d3e8fa-8572-4c2a-8a3b-2eb7c344dfce/thread:delegated-task:command%3Amcp%3A21475963-ffcf-45a8-84be-20b1a420b463%3Adelegate-task%3Aboo-7plj-fresh-review-dcb9f92-20261110>

Correctness: PASS. Static inspection confirms that crop readiness precedes queued storage writes. The existing close contract drains them. Real file reads, the controlled writer delay, idempotent PDF disposal, and failure cleanup support the correction. No findings or material gaps.

Fulfillment: PASS. The reviewer inspected the deterministic stale-[1] red log and the passing focused/full/static-check logs. No timeout increased, the saved partial and completed survey expectations are stronger, and the exactly-once layout expectation remains. No findings or material gaps. The reviewer did not independently execute the logged commands.

Design: PASS. The test uses the existing survey-close operation and real SurveyFiles reads/writes. It adds no production abstraction, second persistence path, copied serialization, or private scheduling dependency. No findings or material gaps.

Crop commit b4ec646 remains separate. The parent must verify the combined tree after recovery/integration. No coverage or mutation work ran here. No fixes were required after review. This note is the only change after the reviewed code commit. Ready for parent integration. Ticket remains in progress until the parent integrates and closes it.
