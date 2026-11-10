---
id: tb-t8rh
status: in_progress
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

## Notes

**2026-11-10T14:59:40Z**

Built (2026-11-10). lib/reader/page_analysis.dart: analyzePage (in a hop, reads no text) gives the reflow geometry and PageAnalysis (regions with kinds, region of each word, source word of each word, prose lines, body line height); reflowAttachment maps a text attachment to the reflow words. lib/reader/pdf.dart: PdfBook({hop}), PdfBook.reflowPage(sourcePage) -> ReflowPage (geometry, analysis, bodyLineHeight, attachedText()), the 16-page cache, the book's body line heights for the session, and PdfBook.checkInvariants. Deviations, written in the design doc's 'Tuning on the fixtures': ink relative to the paper's luminance; raised marks split from scanned words (Gibbon's marks 17 to 21 lie inside their layout word boxes); specks below a sixth of the median line height; wide gaps relative to the page's median word gap, lined up by overlap; one raised word per short line; the short-line height limit 1.5; a band rule for hyphens; mid-tones counted with a margin. Tests: test/reader/page_analysis_test.dart.
