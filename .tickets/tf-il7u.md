---
id: tf-il7u
status: open
deps: []
links: []
created: 2026-11-13T13:23:39Z
type: bug
priority: 3
assignee: Alexis Purslane
---
# Investigate the intermittent idle-layout frame test failure

During boo-hjal verification, test/reader/epub/page_source_frames_test.dart:188 failed: idle layout gives way to each frame that is scheduled, and goes on once no frame is scheduled. Expected far() false, got true, with reason idle steps ran in a row between frames. The same test passed in the preceding reader/crossings suite. Logs: tool/evidence/boo-hjal/08-reader-crossings.txt and 12-full.txt. The test and scheduler implementation were unchanged by boo-hjal. Cause is not established; investigate whether the prepared source can finish idle work before Redraws schedules its first frame.

## Acceptance Criteria

Reproduce the cause with controlled scheduling. Preserve the production scheduling contract. Use a deterministic readiness or work-count assertion, not a larger delay or timing threshold. Run the unchanged relevant behavior and full suite.


## Notes

**2026-11-13T13:25:55Z**

The unchanged targeted frame suite passed all five tests immediately after the full run: tool/evidence/boo-hjal/13-frames-repeat.txt. No production scheduling change or test timing adjustment was made. A full-suite rerun is next.

**2026-11-13T13:31:26Z**

The second unchanged full run passed 3,535 tests with 27 skips: tool/evidence/boo-hjal/14-full-repeat.txt. The earlier intermittent failure remains unresolved as a follow-up; no frame test or scheduling implementation was changed.
