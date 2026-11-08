---
id: te-4cez
status: closed
deps: []
links: []
created: 2026-11-08T20:49:47Z
type: feature
priority: 3
assignee: Alexis Purslane
parent: boo-b2ey
---
# Keep the text of a table row that is taller than a page

Found in tc-txyr. The design (Coverage beyond the trial / Tables and other layout) gives a table row taller than a page a page of its own and cuts it at the page edge, so the text below the edge does not show. tc-txyr built that rule. The epic's goal for tables is that no text is lost. A cell with long prose, such as a Gutenberg notes table, can lose lines. Decide whether such a row splits between the lines of its cells, and build it if so. A split row must keep the property that a run from any page start cuts the same pages.


## Notes

**2026-11-08T21:04:54Z**

Decision (orchestrator, 2026-11-08): split such a row between the lines of its cells, because the epic's goal is that no text is lost. Keep the property that a run from any page start cuts the same pages.

**2026-11-08T21:24:41Z**

Interfaces as built. table.dart: rowFragments(cells, pageHeight) cuts a row into RowFragment records (height, and a CellFragment per cell: slices [from, to), offset of the box top below the fragment top, and the band [top, bottom) of the box that it shows); FragmentCell is its input; fitTolerance (0.01 px) is the page fit slack that LayoutRun._cut uses too. A row that fits a page is one fragment, as before. A taller row: each fragment but the last is one page tall, each cell goes on from its first slice that did not fit, a slice taller than a page goes alone when nothing fits, and a split cell starts at the top (vertical-align is not applied). layout.dart: Slice.rowPieces became Slice.cellSlices (the cells' line, image and rule slices that a row slice shows), so endPlace, pieces and lineStart see each cell line. PageStart(item, n) for a table names its n-th slice (a row, or a fragment). Piece moved copies share their paragraphs and holder count (_Paragraphs), so one paragraph shows on several pages. Piece.shown also clips a cell's lines at the next fragment. lineStart and ChapterLayout.pageAt pick the line with the last start at or before the place in document order, because a split row puts later cells' lines on earlier pages. Page visible ranges of a split row can overlap when a cell before the last continues (startVisible stays increasing; endVisible is the last character that the page shows). Limits: a split row starts on a new page instead of filling the space left on the page before it, as the old page-of-its-own rule did; Chromium fills that space, but that fill depends on the page top, which a run from a fragment cannot know.
