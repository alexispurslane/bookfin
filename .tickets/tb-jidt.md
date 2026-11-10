---
id: tb-jidt
status: open
deps: [tb-t0ea]
links: []
created: 2026-11-10T02:33:40Z
type: feature
priority: 1
assignee: Alexis Purslane
parent: boo-fval
---
# Give scanned PDF pages word geometry from Tesseract's layout pass, and attach their recognized text

W1 of docs/plans/pdf-word-image-reflow.md (sections Word geometry, The layout pass, Text attachment, Fixtures). After tb-t0ea, add PageGeometry and TextAttachment. BundledEnglishText runs the layout pass for a page without a usable text layer, turns the layout record into PageGeometry in page units (boxes, own baselines from Tesseract's word baselines, line baselines and slopes, blocks with kinds, paragraph starts with justification and indent), and keeps the record in the recognition cache on disk under its own key. The shown page's layout pass goes to the front of the queue, and its recognition follows. When the hOCR arrives, decodeRecognizedPage builds the same source and digest as today plus each hOCR word's range and box, and attachText joins them to layout words by box overlap. BundledEnglishText.version does not change. Add the scanned and skewed fixtures with layout records and hOCR recorded on an emulator, with a README of sources and licenses.

## Acceptance Criteria

Behavior tests, red first: a scanned page's geometry is ready before its text; a saved layout record opens the page with no layout pass; a recognized page gives the same reading text and digest as before (a place saved before still resolves); each layout word attaches to the characters of the hOCR words that overlap it, in increasing order, and unmatched hOCR words still attach to a word on their line; the skewed page's line slopes match its 2.5 degree turn; the shown page's layout pass runs before other waiting recognition. PageGeometry.checkInvariants holds on both fixtures. Decode and attachment run in a hop.
