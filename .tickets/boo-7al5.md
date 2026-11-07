---
id: boo-7al5
status: in_progress
deps: [t9-xj41]
links: []
created: 2026-11-07T18:34:07Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Make the player's Undo notice compact

Found on the Pixel 8 on 2026-11-07. After a jump, the Undo panel is a large bordered box that pushes the Chapters/Bookmark/Speed/Sleep row below the screen edge. Make it a compact line or pill under the transport that does not move the tool row.


## Notes

**2026-11-07T23:22:49Z**

Orchestrator choice, November 7, 2026: a one-line pill under the transport controls that reserves no layout space (an overlay or a fixed-height slot), so the Chapters/Bookmark/Speed/Sleep/History row never moves when Undo appears or disappears. t9-xj41 made UndoNotice a pure leaf (onUndo, onDismiss) and MiniPlayerCard has a notice slot; restyle the leaf, keep its callbacks.
