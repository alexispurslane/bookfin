---
id: tb-jidt
status: closed
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

## Notes

**2026-11-10T13:18:29Z**

From tb-t0ea: the layout record is an Int32List of 9-number entries (kind, left, top, right, bottom, a, b, c, d) in raster pixels, defined in native/ocr/bookfin_ocr.c. A picture, rule or noise block has no lines or words, as in hOCR. 'recognize' without arguments recognizes the page that the last 'layout' kept, so the queue must not run another page's layout between a page's layout and its recognition, or that recognition reads the wrong page. Without a kept page it fails with code 'recognition', and the worker then closes the engine (the model reloads on the next page).

**2026-11-10T14:01:51Z**

Built (2026-11-10). PageGeometry, RecognizedWords, pageGeometryFromLayout and attachText in lib/reader/page_geometry.dart; PdfBook.geometry and PdfBook.attachedText; PdfTextSupply.geometry and attachedText; the queue in EnglishRecognition has layout jobs (front) and recognition jobs (right behind the page's layout pass). Kept-image hazard: the queue alone calls the channel, runs one job at a time, and records the page whose image the engine keeps (_kept: set by a successful layout, cleared by every other native call and by close). Recognition sends 'recognize' without a page only when _kept is its page; otherwise it renders and sends the page. Tests: test/reader/ocr_layout_queue_test.dart ('a page's recognition never reads the image that another page's layout pass kept', 'after the native worker closes, recognition of a page laid out before sends that page again'). Layout records are cached as JSON {key, layout (base64 of little-endian int32), sha256} under sha256('bookfin-layout-1/<version>/<digest>/<page>'). Deviations from the design doc, now written in it: PageGeometry has blockBoxes (a picture block has no lines); the attachment invariant is 'no range starts or ends with white space', because rule 2 can join two hOCR words. Fixtures: test/reader/fixtures/reflow (layout records and hOCR, recorded on the emulator; PDFs not copied). New tickets: t2-jfg1, t2-k2o3.
