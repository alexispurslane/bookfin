---
id: tb-jidt
status: open
deps: [boo-pw1d]
links: []
created: 2026-11-10T02:33:40Z
type: feature
priority: 1
assignee: Alexis Purslane
parent: boo-fval
---
# Give recognized PDF pages word geometry from their hOCR

W1 of docs/plans/pdf-word-image-reflow.md (sections Word geometry, From hOCR, Fixtures). Add PageGeometry to PdfText and build it in decodeRecognizedPage from the cached hOCR: word ranges in source, word boxes in page units (divided by the ocr_page width), line baselines, slopes, heights and descender depths, blocks (ocr_carea), paragraph starts (ocr_par) and each word's own baseline. The source string and digest stay byte-identical, and BundledEnglishText.version does not change. Add the scanned and skewed fixtures with hOCR recorded from Bookfin's Tesseract on an emulator, with a README of sources and licenses.

## Acceptance Criteria

Behavior tests, red first: a recognized page gives the same reading text and digest as before (a place saved before still resolves); each word names the characters of its hOCR word; the skewed page's line slopes match its 2.5 degree turn. PageGeometry.checkInvariants holds on both fixtures. The decode stays in the hop. Fixtures README records each source.

