---
id: t6-hwgc
status: open
deps: []
links: []
created: 2026-11-08T21:38:30Z
type: task
priority: 4
assignee: Alexis Purslane
parent: boo-b2ey
---
# Collapse the borders of row groups and columns, and let border-style hidden win

Found in te-orei. collapseBorders in table.dart resolves the collapsed borders of cells, rows and the table by width. CSS 2.1 also collapses the borders of row groups (thead, tbody, tfoot) and columns (col, colgroup), and a hidden border wins over every other border on its edge. css.dart reads hidden as none, and prepare does not keep row group or column styles. Books that rule their thead with a border under border-collapse: collapse draw no rule there.

