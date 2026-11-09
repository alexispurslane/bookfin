---
id: t5-s1vy
status: open
deps: [t5-4l4d]
links: []
created: 2026-11-09T18:18:38Z
type: task
priority: 3
assignee: Alexis Purslane
parent: boo-b2ey
---
# Keep table cell widths in the page map

Found in boo-ystu (docs/research/epub-layout-cache.md). A run or a line search in a table measures the narrowest and widest content width of every cell of the table first (LayoutRun._measured). The result lives in an Expando on the table item, so it is lost when the page source evicts the prepared section. Keep the widths of each table item in the page map as exact 64-bit floats (16 bytes a cell). The corpus has 39,726 cells in 52 of 93 books, at most 21,820 in one book (Plato's Dialogues, 349 KB).

## Acceptance Criteria

A test shows that a run from a kept start inside a table cuts the same pages with kept widths as with measured ones. A jump into the table of Roget's Thesaurus with a page map measures no row.

