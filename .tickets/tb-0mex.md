---
id: tb-0mex
status: open
deps: [tb-t8rh]
links: []
created: 2026-11-10T02:33:41Z
type: feature
priority: 1
assignee: Alexis Purslane
parent: boo-fval
---
# Lay out a reflowed PDF page as lines of word images

W4 of docs/plans/pdf-word-image-reflow.md (Lines and paragraphs, Regions). Write layoutColumn(page, settings) as a pure function in a hop: the scale from text size and body line height, wrapping in reading-text order, gaps, baselines (line, own, raised marks), rotation of sloped lines, line pitch, paragraphs (ocr_par and the geometry rule), indents, centered paragraphs, justification, hyphen pairs, regions placed and scaled to fit, and screens as open decision 2 settles. Do not start before the user settles open decision 2.

## Acceptance Criteria

Behavior tests, red first: words wrap in reading-text order and no line is wider than the column; on the skewed fixture the words of each reflowed line share one baseline within one device pixel; a raised footnote mark stays raised; paragraphs, indents, centered headings and justification follow the source; a hyphen pair on one line draws no hyphen and no gap, across two lines it draws the hyphen; regions fit the column and the screen; a size step changes word height by the size ratio.

