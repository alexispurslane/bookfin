---
id: boo-z3is
status: in_progress
deps: []
links: []
created: 2026-11-11T15:11:08Z
type: epic
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
---
# Go to a place of the other edition inside the open edition

User request 2026-11-11. In the reader, Go to on a listening entry maps that audio time to the matching place in the ebook and jumps there in the reader. In the player, Go to on a reading entry maps that text place to the matching audio time and seeks there. Today Go to on an entry of the other medium switches to the other screen instead. Keep the two histories conceptually separate: two tracks with their own icons, so the person sees when a jump crosses editions and may be approximate. A mapped jump is a move in the open edition's own track, with Undo, and never changes the other edition's place. When no defensible mapping exists, fall back to today's behavior and say so. This is Bookfin's 'read and listen together' feature, like Kindle's. Design: docs/plans/cross-edition-places.md.


## Notes

**2026-11-11T15:11:48Z**

Design agent started (Claude Opus 5.5 xhigh, worktree, design only): clientRequestId opus-xhigh-boo-z3is-cross-edition-design-20261111-1. It measures chapter matching and writes two mapping designs (chapter-proportional, on-device speech alignment) into docs/plans/cross-edition-places.md for the user to choose.
