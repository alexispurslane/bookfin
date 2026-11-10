---
id: tb-xwlj
status: in_progress
deps: [tb-jidt]
links: []
created: 2026-11-10T02:33:41Z
type: feature
priority: 1
assignee: Alexis Purslane
parent: boo-fval
---
# Give text layer PDF pages word geometry from their character boxes

W2 of docs/plans/pdf-word-image-reflow.md (From the text layer, When the geometry is not usable). preparePdfPage also takes the page width and height and builds PageGeometry from the character boxes: words as runs without white space, boxes in page units with y flipped, own baselines from characters outside the descender set, lines, blocks, and line baselines. A candidate text layer with unusable boxes gives no geometry. Add the born-digital equation fixture, made with Typst in the dev shell from a source file kept beside it.

## Acceptance Criteria

Behavior tests, red first: each word is a run of the text without white space and its box holds its characters' boxes; lines and blocks follow the equation fixture's printed lines; unusable boxes give no geometry; a page whose text layer cannot be put in reading order still takes its words from recognition. Text and digest stay unchanged. Typst is pinned in the flake.


## Notes

**2026-11-10T14:23:05Z**

Built (2026-11-10). preparePdfPage takes the page width and height and returns PreparedPdfPage: the PdfText as before, and TextLayerWords (PageGeometry and attachment) when the text is a candidate and its boxes are usable. pageGeometryFromCharacters in lib/reader/page_geometry.dart builds words, own baselines, lines, line baselines, blocks and hyphen widths. _NativePdfBook caches the prepared page (one hop) and gives geometry and attachedText from it for a candidate page; other pages still go to recognition. Deviations, written in the design doc: words also end after U+0002 (pdfium's line-end hyphen, which joins the halves without a line break); a word starts a new line only when it starts left of the previous word or its height does not overlap its line's height at all, because pdfium puts a line break between a letter and its raised mark. Fixture: test/reader/fixtures/reflow/equation-page.typ and .pdf, made with the flake's Typst 0.15.1. Its display equation has no stacked fraction, because both stacked fractions tried made _outOfOrder reject the text layer. Tests: test/reader/text_layer_geometry_test.dart; the lock of reading text and digests is 'text layer pages keep the reading text and digest that they had before word geometry'.
