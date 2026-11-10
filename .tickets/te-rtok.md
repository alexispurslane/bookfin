---
id: te-rtok
status: open
deps: []
links: [tb-9mcf]
created: 2026-11-03T18:02:59Z
type: bug
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Use the approved Source Serif 4 font for PDF reflow

Normal Android source 71af2886e722b7366d4d335622e55e18a151a3e0 displays recognized PDF body text in a sans-serif typeface. The approved reading typeface is Source Serif 4. Cream/sepia surfaces and long-text controls remain readable and reachable. Evidence: tool/evidence/reader/integrated/20261103/android/01-offline-english-reflow.png and 06-long-recognized-place.png, compared with docs/plans/bookfin.md and docs/mockups/bookfin.html. No production edit or fix belongs to this acceptance lane.

## Acceptance Criteria

Show recognized PDF reflow using the approved reading typeface on Android without changing source addresses, text measurement, bookmarks, or original-page access. Preserve ordinary long-text scrolling and controls.
