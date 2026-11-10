---
id: t5-s1vy
status: closed
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


## Notes (2026-11-09, implementation)

- Format 4 of the page map keeps each section's measures (`SectionMeasures` in layout.dart): for each table item of the section's flow, the narrowest and widest content width of each cell, as exact 64-bit floats. Maps of format 3 read as absent, and the next write removes them.
- `measuresOf` reads what runs of a prepared section measured. `reuseMeasures` gives kept measures to a new prepared section, and refuses measures that do not fit its tables. `forgetMeasures` takes them back.
- The page source keeps a section's measures from its main run's end or from the kept map, and gives them to each prepared section of it. So a section that was let go and prepared again does not measure its tables again either.
- The check on use: a run measures each kept table row that it lays out again, once per prepared section (`LayoutRun.contradicted`). A row that disagrees forgets the map, as a page that disagrees does. A row costs about what its layout costs.
- On the host, a jump into the middle of the largest section with a map (page_map_jump_test, load 9 to 12): Roget's Thesaurus 967 ms before, 24 ms after, measuring 4 of the table's 1,187 cells. Standard Ebooks' Ulysses 140 ms before, 5 ms after: its largest section (section 18, Circe) is a play laid out as tables of 2,760 cells, so its cost was the table measure and not long paragraphs.
