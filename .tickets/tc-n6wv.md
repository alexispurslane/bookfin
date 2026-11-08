---
id: tc-n6wv
status: in_progress
deps: [tc-txyr]
links: []
created: 2026-11-08T19:23:13Z
type: feature
priority: 2
assignee: Alexis Purslane
parent: boo-b2ey
---
# Place lines at fractional positions

Goal: lines sit at their exact CSS positions, as in Chromium, at every text size. Flutter rounds each line's height to a whole pixel.

Design section: "Coverage beyond the trial / Fractional line positions".

Files: lib/reader/epub/layout.dart, lib/reader/epub/paint.dart, test/reader/epub/line_position_test.dart.

Rules:
- Each strip slice records its exact top and bottom from the unrounded CSS line heights. A line that holds taller inline content (an image, a raised run) uses Flutter's own height for that line.
- Paint draws each line of a piece at its exact top, clipped to that line.
- Page cuts use the exact positions with the trial's 0.01 pixel tolerance.
- Keep the signatures from tc-nang.

## Design

docs/plans/native-epub-reader.md (epic boo-b2ey). Read the sections named in the description. The design decides the owners, interfaces and order. Ask the orchestrator before changing them.

## Acceptance Criteria

- At 23 pixels, a body paragraph's line tops step by 37.95 pixels, not 38.
- A two-line heading at 30 pixels is 99 pixels high, as Chromium makes it (the trial's Keats case).
- The on-demand fidelity test on tc-pshi's committed Chromium data agrees on page starts at 23 pixels at least as well as at 20, and line start agreement does not drop.
- E3's properties still hold.


## Notes

**2026-11-08T22:19:05Z**

An exact line's height is Flutter's own height before it rounds (ascent + descent): the CSS line height, or the height of a line's taller inline content. Lines of line-height: normal keep Flutter's rounded height, because Chromium rounds font metrics there. Paint draws each line at its exact baseline, clipped to it, and draws neighboring lines with the same shift together. Fidelity on chromium-layout.json: body text page starts 1,460 to 1,461 of 1,482 at 20 px and 2,024 of 2,048 at 23 px (unchanged), line starts unchanged; A Christmas Carol page starts 117 to 162 of 267 at 20 px and 104 to 207 of 351 at 23 px. Keats' other differences come from elsewhere (see the report). Needed t5-ynlj.
