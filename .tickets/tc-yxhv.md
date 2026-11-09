---
id: tc-yxhv
status: open
deps: []
links: []
created: 2026-11-09T19:25:15Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-b2ey
---
# Let a frame wait for at most one urgent layout step

Found in t7-bbv1. On an Android emulator, Flutter's task queue ran about five layout steps in a row before a requested frame, so the frame waited 20 to 44 ms. t7-bbv1 made idle steps wait while a frame is scheduled, and then no frame waited for an idle step. Urgent steps still run while a frame is scheduled, because the shown page and its neighbors must come during an animation. So a frame that is requested while urgent work runs still waits for several urgent steps. In the open benchmark's stay (a frame requested every 50 ms), every late frame that remained waited for urgent steps only: 16 to 45 ms in total per run, in Hamlet, Keats and Ulysses, where the shown page's previous page needs the main run to reach a page in the middle of a large section. A drag over the scrub deck also asks for urgent pages. Options: let an urgent step run only once between two frames while a frame is scheduled, or give each urgent run of steps a share of the frame interval.

## Acceptance Criteria

In the open benchmark's stay on the emulator, no frame waits for more than one layout step, urgent or idle, and the shown page, a turn and a deck preview take no longer than today.

