---
id: te-orei
status: in_progress
deps: []
links: []
created: 2026-11-08T20:49:47Z
type: feature
priority: 3
assignee: Alexis Purslane
parent: boo-b2ey
---
# Read border-collapse and border-spacing for tables

Found in tc-txyr. Table layout uses Chromium's default border-spacing of 2 pixels for every table and draws each cell's own borders (separate borders). A book that sets border-collapse: collapse or another border-spacing draws double rules and other gaps than Chromium. Parse both properties in css.dart and use them in table.dart and LayoutRun._table.


## Notes

**2026-11-08T21:40:25Z**

Interfaces as built. css.dart: Style.borderSpacing (across, down) in pixels and Style.collapseBorders, both inherited; a border-spacing that is not valid (negative, a percentage, more than two lengths) or a border-collapse other than collapse or separate drops its declaration, so the earlier one stays, as in Chromium. The user agent sheet gives table border-spacing: 2px and border-collapse: separate. prepare.dart: TableItem(rows, width, spacing); a collapsed table has spacing (0, 0) and no padding, and its cells and its own box take the widths of collapseBorders. table.dart: collapseBorders(rows, table) (CSS 2.1 17.6.2 for widths: each edge takes the widest of the cell, row and table borders that meet there, and each side takes half; the table takes half of the widest top and bottom edges of its first and last rows, and half of its first row's outer side edges). The cellSpacing constant became a spacing argument of columnWidths, gridMaxContent and cellBoxes. A headless Chromium check matched: a 6 px edge between two cells gives each 3 px, a 5 px row border gives each cell 2.5 px, and a collapsed table with a 4 px border and padding has its first cell 2 px inside it. Limits: row group and column borders and border-style hidden do not take part (t6-hwgc). Found: t6-9o4o (a box that closes at a section's end loses its bottom border on the last page).
