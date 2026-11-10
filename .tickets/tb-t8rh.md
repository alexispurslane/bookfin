---
id: tb-t8rh
status: open
deps: [tb-xwlj]
links: []
created: 2026-11-10T02:33:41Z
type: feature
priority: 1
assignee: Alexis Purslane
parent: boo-fval
---
# Analyze a PDF page for word reflow: regions, missed ink, hyphen widths and body line height

W3 of docs/plans/pdf-word-image-reflow.md (Page analysis). Add PdfBook.reflowPage(sourcePage): reading text, geometry and page analysis, cached for 16 pages beside the page texts, with the book's body line height for the session. The analysis renders the page at 1600 pixels wide and runs in a hop: ink mask at a quarter size, word cover, components, missed words, regions with absorbed words, the prose line test, picture or ink kind, hyphen widths, body line height.

## Acceptance Criteria

Behavior tests, red first, on the three fixtures: the display equation and the table each become one region and keep their text in the reading text; a word removed from the hOCR still shows as an unread word of its line; a line-end hyphen gets its width; a figure becomes a picture region; specks are dropped. The analysis runs through the injected hop and frees its raster. The cache's checkInvariants holds.

