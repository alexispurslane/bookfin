---
id: tb-i6wg
status: in_progress
deps: []
links: []
created: 2026-11-09T07:34:20Z
type: bug
priority: 3
assignee: Alexis Purslane
parent: boo-b2ey
---
# Lay out a tall table row in steps of its cells' paragraphs

Found in t1-um08. A table now lays out one row per unit of work, so a step stops after the row that crosses its budget. But one unit lays out every paragraph of every cell of its row. Roget's Thesaurus (Gutenberg, section 1, table item 39, 797 rows) has rows of about 9,700 characters in 10 to 16 paragraphs (rows 586, 592 and 675). Its slowest row unit takes 121 ms at 360 x 640 at 26 pixels on the host (corpus run, JIT); at 412 x 671 at 20 pixels no row takes more than 10 ms. A row's fragments need the slices of all its cells (rowFragments), so a step that stops inside a row has to keep the laid-out cells of the row until the row is done.

## Acceptance Criteria

- No layout step of Roget's Thesaurus takes much more than the budget plus one paragraph at both corpus page settings, by the corpus slow-item list.
- Runs from every page start still cut the same pages, and split rows keep their fragments (table tests and the corpus run of Roget's Thesaurus).


## Notes

**2026-11-09T14:49:33Z**

Built: a table row lays out its cells one flow item per unit of work, or one segment of a long paragraph (LayoutRun._tableRow, _Rows.cells and _Rows.cell). The row keeps the content of its laid-out cells until the last cell is done, then adds its fragments and slices in that unit, as before; dispose lets go of a row in progress. Warm probe on the host (load 8 to 12): Roget's Thesaurus has no table unit over 6 ms at either setting (7 to 12 ms before); Plato's Dialogues 30, 1244 (22 paragraphs in one row) went from 110 and 212 ms to 6 and 8 ms. Corpus run (cold, once per section): no Roget table unit over 8 ms; Plato's slowest table unit 17 and 18 ms, one hyphenated paragraph of a cell (tb-o242). Both books pass every check with runs from every page start. A page dump of 48 corpus books at both settings is identical before and after (4,886 section layouts). The step benchmark's table of 30 rows of 16 paragraphs: slowest step 8.2 ms before, 4.3 to 5.4 ms after. Found: Roget's index paragraphs without hard breaks (tb-3xvr).
