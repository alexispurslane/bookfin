---
id: boo-y6fb
status: open
deps: []
links: []
created: 2026-11-07T21:36:12Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
tags: [performance, ui-rules]
---
# Give Playback a narrow position signal

UI rule 3. Playback sends one notification for everything, so the whole player stage, the mini player and every Playback listener rebuild on each 200 ms tick. Design from the boo-8dkw report: _accept updates a position ValueListenable that only the slider, the time texts and the mini player's progress bar listen to; the broad notification fires only when the playing state, the open book or edition, or the records change. Check every Playback listener (media session from boo-nxp8, repaint boundaries from boo-jkf7, CoverScope) for what it really needs.

## Acceptance Criteria

A playing tick rebuilds only the widgets that show the position. A test counts rebuilds of the stage and of the slider across ticks. Play, pause, a seek and a book change still reach every listener that shows them.

