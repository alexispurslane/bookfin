---
id: tc-butt
status: closed
deps: []
links: [boo-hyl4, tc-p3j8]
created: 2026-11-11T15:31:25Z
type: bug
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Name the other device on an Opened history entry

Found during boo-hyl4 on 2026-11-11 (docs/plans/history-choice.md, side finding). t9-4vsl and t9-gtps expected the timeline to show 'Opened at the place from A' for a book that opened at another device's place. HistoryEvent.device holds the name, but HistoryTimeline._label returns only 'Opened' for HistoryAction.open. This entry is the one where its before place (this phone's own place) and its after place (the other device's place) matter most.

## Acceptance Criteria

An open move with a device name reads 'Opened at the place from <device>' in the timeline, for listening and for reading. An open move without a device name (the start of a reading visit) still reads 'Opened'. A widget test covers both.


## Notes

**2026-11-11T15:54:14Z**

HistoryTimeline._label reads HistoryEvent.device: an open move with a device reads 'Opened at the place from <device>' for listening and reading; without one it reads 'Opened'. Widget tests in test/playback/timeline_route_test.dart.
