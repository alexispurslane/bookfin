---
id: t5-rplx
status: open
deps: []
links: []
created: 2026-11-13T03:25:09Z
type: bug
priority: 3
assignee: Alexis Purslane
parent: boo-fs0n
tags: [testing]
---
# Investigate the intermittent unread-record recovery test failure

During boo-jld0 verification on base 8caf18ebcfcaa02df67c49767cdee11d5109f2eb, the full Flutter suite at concurrency 4 reported 3130 passed, 25 skipped and one failure in test/reader/unread_records_test.dart: the next place after a failed read opens the records again without a flush. At line 97, the saved resumes list was empty instead of containing one entry. The test waits with pumpEventQueue after accepting the visible place. Reader and record-store production code were unchanged by boo-jld0. A wait for real storage completion may be missing, but that cause is not yet established. Related completed behavior ticket: boo-y2sj.

## Acceptance Criteria

Establish whether the failure is a storage race or an insufficient test wait. Preserve the requirement that the next reading place retries storage without an explicit flush. Demonstrate a meaningful failing test for any production defect, then pass the focused tests and the full suite at concurrency at most 4.

## Notes

**2026-11-13T03:25:58Z**

The immediate isolated retry, nix develop --command flutter test --concurrency=1 test/reader/unread_records_test.dart --reporter expanded, passed all 5 tests. This confirms an intermittent failure in the full run, not its cause. No reader or record-store fix was attempted in boo-jld0.

**2026-11-13T03:38:43Z**

Two later full-suite runs at concurrency 2 passed: 3131 passed and 25 skipped before the final catalog access-recovery fix, then 3132 passed and 25 skipped after that fix and its regression test. The reader recovery test passed in both. The original concurrency-4 failure remains recorded for investigation.
