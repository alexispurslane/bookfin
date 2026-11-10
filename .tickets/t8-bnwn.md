---
id: t8-bnwn
status: open
deps: [tb-22fu]
links: []
created: 2026-11-10T17:04:28Z
type: feature
priority: 2
assignee: Alexis Purslane
parent: boo-fval
---
# Render the next source page's first screen ahead at a page's last screen

PdfWordPages (lib/reader/word_pages.dart) renders ahead only the next screen inside the shown source page. On a page's last screen, a forward turn to the next source page waits for its reflow page, its column and its bands. Render the first screen of the next source page ahead (and the last screen of the previous page on a backward turn), within the same bound of two screens of images. Found in tb-xjfi.

## Acceptance Criteria

A forward turn from a page's last screen shows the next page's first screen from images rendered ahead. Live band images still never hold more than 4 times the screen's pixels.

