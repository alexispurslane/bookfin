---
id: tb-i6wg
status: open
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

