---
id: boo-0ot1
status: open
deps: []
links: []
created: 2026-11-07T23:39:21Z
type: task
priority: 3
assignee: Alexis Purslane
parent: boo-fs0n
tags: [accessibility]
---
# Give the Undo pill's buttons full-size touch targets

From boo-7al5. In the 44-point Undo pill (lib/playback/screen.dart, UndoNotice), the Undo button is 32 points high and the dismiss button 40 points, below Android's 48-point touch target guideline. Keep the pill's drawn height at 44 and the tool row fixed, but give each button a 48x48 hit area (for example materialTapTargetSize padded with the slot's vertical padding absorbing it).

## Acceptance Criteria

Undo and Dismiss Undo each meet androidTapTargetGuideline in a widget test; the tool row still does not move when the pill appears or goes.

