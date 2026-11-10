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
# Analyze a PDF page for word reflow: regions, uncovered ink, hyphens and body line height

W3 of docs/plans/pdf-word-image-reflow.md (Page analysis, and the k2pdfopt checklist). Add PdfBook.reflowPage(sourcePage): geometry and page analysis at once, and the text attachment after the reading text arrives, cached for 16 pages, with the book's body line height for the session. The analysis renders the page at 1600 pixels wide and runs in a hop: ink mask at a quarter size, word cover, components, uncovered ink as extra words of its line, regions from picture and table blocks of the layout pass and from joined components, the prose line test with the aligned-gap rule for tables, picture or ink kind, hyphens from pixels on scanned pages, body line height.

## Acceptance Criteria

Behavior tests, red first, on the three fixtures: the display equation and the table each become one region and keep their text in the reading text; a justified line with wide word gaps stays prose; a picture block of the layout pass becomes a picture region; ink that no word covers shows as an extra word of its line; a line-end hyphen on a scanned page is found from pixels with its width; specks are dropped. The analysis reads no text, runs through the injected hop and frees its raster. The cache's checkInvariants holds.
