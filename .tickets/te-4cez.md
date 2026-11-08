---
id: te-4cez
status: open
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

