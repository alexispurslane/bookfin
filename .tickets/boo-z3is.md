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

**2026-11-11T15:40:09Z**

Design written in docs/plans/cross-edition-places.md: two designs. A pairs audio chapters with ebook contents and places a jump proportionally inside the matched chapter. B adds an on-device speech stage that transcribes one 30 s window and finds its words in the text. B keeps A unchanged as its first stage, so A comes first.

Measured on public data (155 LibriVox recordings against 39 corpus EPUB editions, 206 pairings): 175 pairings anchor at least 90% of their sections, and 8 have too few anchors, so A refuses them. For one-reader pairings, A misses a hidden chapter start by 0.36 pages (18 s) at the median. At the 90th percentile, it misses by 1.39 pages (69 s). A whole-book share gives 5.2 and 22.4 pages. A whisper.cpp tiny.en probe found all 12 test windows in the right place, at 0.7 to 0.9 s per window on the Mac CPU.

Open questions for the user: placement in the reader, placement in the player, and books whose chapters do not match. New ticket t3-a4fi measures the real library, which needs a sign-in. The design does not depend on boo-hyl4's choice buttons: the timeline gets one input, landingOf(place).
