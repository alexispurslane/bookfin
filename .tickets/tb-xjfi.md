---
id: tb-xjfi
status: open
deps: [tb-0mex]
links: []
created: 2026-11-10T02:33:41Z
type: feature
priority: 1
assignee: Alexis Purslane
parent: boo-fval
---
# Draw reflowed PDF screens from rendered bands with tints and a memory bound

W5 of docs/plans/pdf-word-image-reflow.md (Rendering). Add PdfBook.renderPart(sourcePage, pixelsPerPageUnit, area) over pdfium's crop render, and PdfWordPages: plans the bands of a screen, renders them at scale times device pixel ratio (at most 4096 by 4096 each), uploads them without a Dart copy, keeps band images only for the shown screen and the next screen in the direction of the last turn, and draws each band with one drawAtlas. Duotone tint for words and ink regions, color-keeping tint for picture regions.

## Acceptance Criteria

Behavior tests, red first: a word image draws at one band pixel for one device pixel; a black pixel draws in the theme's text color and a white pixel in its paper, in cream and night; picture regions keep their colors; live band images never hold more than 4 times the screen's pixels; a change of page, size or width disposes the images that the new screens do not use. PdfWordPages.checkInvariants holds.

