---
id: boo-h2sk
status: open
deps: []
links: []
created: 2026-11-08T19:38:21Z
type: feature
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Retire the Listening tab in favor of the mini player, and grow the player out of it

User request (2026-11-08): try to make the Listening tab obsolete, so that the mini player chip at the bottom of every tab is always the way into listening. And when the user taps the playing chip, the glass player pane should expand out of the chip itself (the chip's shape, cover and glass grow into the pane, and shrink back into it on close), instead of appearing on its own.

Today the Listening tab holds the player stage and the list of recently listened books (see docs/screenshots/listening.png and player-night.png), and the player also opens as a pane from the mini player.

Open design questions, to settle with the user before building:
- Where the Listening tab's other content goes, mainly the recently listened list and the history timeline: inside the expanded player pane, in the Library (for example a Recently listened row or filter), or both.
- What the chip shows when nothing has been played yet, and how a first-time listener finds listening at all without the tab.
- The bottom bar with three tabs (Library, Downloads, Settings), and whether anything else moves.
- The expand animation: a shared-element (hero-like) transition from the chip's rect to the pane, the glass blur and cover tint staying continuous, drag down on the pane to shrink it back into the chip, and reduced motion skipping the animation.

Keep one player component (AGENTS.md UI rule 2): the chip, the pane and the reader dock's round cover button all read the same Playback signals.

