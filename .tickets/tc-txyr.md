---
id: tc-txyr
status: in_progress
deps: [tc-nang, tc-nh0b]
links: []
created: 2026-11-08T19:23:13Z
type: feature
priority: 1
assignee: Alexis Purslane
parent: boo-b2ey
---
# Lay out simple tables as grids and other unsupported layout as plain flow

Goal: tables with rows lay out as grids, and flex rows, grids, floats and positioned boxes flow as blocks, so no text is lost.

Design section: "Coverage beyond the trial / Tables and other layout".

Files: lib/reader/epub/table.dart (new), lib/reader/epub/prepare.dart, lib/reader/epub/layout.dart, test/reader/epub/table_test.dart.

Rules:
- prepare: a table with rows or row groups becomes a TableItem: rows of cells, each cell a nested list of flow items, with colspan. A caption becomes a block before the table. A table inside a cell lays out as blocks. rowspan counts as 1.
- table.dart (UI isolate): column widths from each cell's minimum and maximum content widths (paragraph minIntrinsicWidth and maxIntrinsicWidth, plus padding and borders). If the maxima fit, use them. Else give each column its minimum plus a share of the rest in proportion to (maximum minus minimum). Lay out each cell. A row's height is its tallest cell.
- layout.dart: each row is one strip slice, so pages break between rows. A row taller than a page gets a page of its own and is cut at the page edge. Places in cells map through each cell paragraph's text map.
- Flex rows, grid, floats and absolute or fixed boxes with offsets that are not negative flow as blocks. A box moved off the page by a negative offset stays out, as in the trial.
- Keep the LayoutRun, LaidPage, lineStart and drawPage signatures from tc-nang.

## Design

docs/plans/native-epub-reader.md (epic boo-b2ey). Read the sections named in the description. The design decides the owners, interfaces and order. Ask the orchestrator before changing them.

## Acceptance Criteria

- A Project Gutenberg contents table fixture lays out as a grid, and its text and links have places.
- A fixture shaped like Moby-Dick's Etymology table lays out. colspan spans columns.
- Pages break only between rows. E3's property (a run from any true page start cuts the same pages) holds with tables.
- A flex row and a grid show their children as blocks in order, with no text lost.


## Notes

**2026-11-08T20:49:55Z**

Interfaces as built. prepare: TableItem(rows, width) and TableCell(flow, colspan, padding, border, align). The table's own box is a BlockStart before the TableItem and a BlockEnd after it; without a set width it is shrink-to-fit to the grid's widest content. A cell's flow is its content only; the table draws the cell's box as tall as its row. BoxPlacement no longer stores x and width: place(x, width, [fit]) and available(width) take the containing block, and layout places every block in the content box of the block that holds it (the page for the main run, the column for a cell). ImageItem now carries sizing, marginLeft and centered, and layout sizes and places it the same way. table.dart: columnWidths, gridMaxContent, cellBoxes and cellSpacing (2 px, Chromium's default border-spacing). layout: Slice.rowPieces holds the paragraphs of a row slice; LaidPage.pieces yields them; PageStart(item, row) starts a page at a row; a cell lays out in a private LayoutRun._cell. css: Style.left, Style.top, Style.movedOffPage, Style.flexOrGrid; flex and grid items, floats and positioned boxes are blocks; VerticalAlign gains top, middle and bottom for cells. Beyond the ticket: cells follow vertical-align (top, middle by default, bottom), because Moby-Dick chapter 101 asks for top. Limits: percentages in cells resolve against the table's width; thead and tfoot stay in document order; children of a table other than captions and rows are left out. New tickets: te-4cez (a row taller than a page loses the text past the page edge), te-orei (border-collapse and border-spacing).
