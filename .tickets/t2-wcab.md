---
id: t2-wcab
status: open
deps: []
links: []
created: 2026-11-09T21:19:35Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-b2ey
---
# Measure a table row's column widths in steps of one cell paragraph

Found in tb-3xvr. Before a run lays out a table, it measures one row per unit of work, to find the column widths (`_measureRow` and `_extent` in lib/reader/epub/layout.dart). The measure lays out every paragraph of every cell of the row at an infinite width in one unit. In Plato's Dialogues (Standard Ebooks), section 30 item 1244 has a row of 22 paragraphs. Its measure took 17 to 19 ms on the host (JIT, load 5 to 13), before and after tb-o242 and tb-3xvr. After those two tickets, it is the slowest unit of the corpus, and the only unit over about 9 ms. A row measure can go one cell paragraph at a time, as the row's layout does since tb-i6wg, and keep the partial extents of the row between units.

## Acceptance Criteria

- No row measure of the corpus takes much more than the budget plus one ordinary paragraph, at both corpus page settings, by the corpus step tool (test/reader/epub/corpus_steps_test.dart).
- The column widths of every corpus table are the same as before, so a page dump of the corpus is the same as before.

