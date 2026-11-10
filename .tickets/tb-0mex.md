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

W4 of docs/plans/pdf-word-image-reflow.md (Lines and paragraphs, Regions). Write layoutColumn(page, settings) as a pure function in a hop. It reads the geometry and the analysis, never the text. The scale from text size and body line height, wrapping in reading order, gaps, baselines (line, own, raised marks), rotation of sloped lines, line pitch, paragraphs (layout pass starts and justification, and the geometry rule), indents, centered paragraphs, justification, hyphen pairs, regions placed and scaled to fit, captions kept with their figures (keep-with-next), and screens of whole lines through a new shared pure function cutScreens(lineTops, lineBottoms, keepWithNext, screenHeight), which the text view also uses (tb-zx7r). The user settled decision 2 on 2026-11-10: design A, whole-line screens.

## Acceptance Criteria

Behavior tests, red first: words wrap in reading order and no line is wider than the column; on the skewed fixture the words of each reflowed line share one baseline within one device pixel; a raised footnote mark stays raised; paragraphs, indents, centered headings and justification follow the source; a hyphen pair on one line draws no hyphen and no gap, across two lines it draws the hyphen; regions fit the column and the screen; a figure's caption shows on its figure's screen; a size step changes word height by the size ratio; no screen cuts a line or starts with a paragraph gap; a region taller than the screen fits on one screen; a region and its caption share a screen when both fit; the column is the same with and without the text attachment.
