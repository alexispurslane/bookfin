---
id: boo-fval
status: open
deps: [boo-pw1d]
links: []
created: 2026-11-10T02:21:26Z
type: epic
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
---
# Reflow PDFs as the page's own word images, as KOReader does

User request (2026-11-09): reflow a PDF by cutting the page image into words with word boxes, and wrapping those word images to the screen, so the reader sees the real printed words and keeps the formatting. KOReader does this with k2pdfopt, which finds words from white gaps in the page bitmap; Bookfin uses Tesseract's hOCR word, line and paragraph boxes (already in the recognition cache) or the text layer's character boxes.

User decisions:
- Design 2: every PDF reflows as word images. Word geometry comes from the PDF's text layer when it is usable, and from Tesseract otherwise.
- Keep a switch that shows the page's recognized or extracted text in the reader's font instead.

Shared parts: word images cut from the page raster at a resolution that matches the text size; the recognized or extracted text kept under the images for search, selection, copy, read-aloud and places (PdfAddress unchanged); paragraph breaks; rejoined line-end hyphens; baseline alignment per line; figures, tables and equations kept whole and scaled to fit; theme tinting (sepia, dark). boo-pw1d lands first, unchanged.

Design: docs/plans/pdf-word-image-reflow.md (to be written).


## Notes

**2026-11-10T02:55:19Z**

User decision (2026-11-09): Tesseract layout first, not k2pdfopt. k2pdfopt (KOReader's reflow library) finds words from image gaps without OCR, but libk2pdfopt bundles modified Tesseract, Leptonica and MuPDF, which duplicate what Bookfin ships, and it is GPLv3. A scanned page runs Tesseract's layout-only analysis first and shows word images at once; full recognition fills the hidden text in the background. k2pdfopt's documented options serve as the checklist of layout rules: -j -1, -hy, -f2p, -jfc, -col/-cg, -as.

**2026-11-10T12:50:56Z**

User decisions (2026-11-10): (1) Original view crops margins, running headers and folios too. The book owns one content box per page from the shared page analysis; headers and footers are found by repetition across pages; footnotes and figures stay. One crop for the whole book (left-hand and right-hand boxes), grown for a page whose content reaches outside it. A 'Trim margins' switch in Reading settings, on by default. (2) The three-view switch is one row: Original, Page words, Text. (3) Reflowed pages turn in screens of whole lines, and the Text view does too.
