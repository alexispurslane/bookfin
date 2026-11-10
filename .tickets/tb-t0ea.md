---
id: tb-t0ea
status: open
deps: [boo-pw1d]
links: []
created: 2026-11-10T03:01:07Z
type: feature
priority: 1
assignee: Alexis Purslane
parent: boo-fval
---
# Run Tesseract's layout pass alone on Android through its C API

W0 of docs/plans/pdf-word-image-reflow.md (section The layout pass). tesseract4android 4.9.0's Java TessBaseAPI has no AnalyseLayout, baseline, paragraph or block type call, but its libtesseract.so exports Tesseract's C API (TessBaseAPIAnalyseLayout, TessPageIteratorBoundingBox, Baseline, ParagraphInfo, BlockType, Next, IsAtBeginningOf). Add a small C library, bookfin_ocr, to the existing CMake build beside bookfin_mobi. It links the AAR's libtesseract.so as an imported library and includes capi.h from the pinned Tesseract4Android source tarball (nix/ocr.nix gives both, per ABI). Move TesseractEngine in OcrChannel.kt from the Java TessBaseAPI to one C API handle: init with OEM_LSTM_ONLY and PSM 3 as today, a new channel method layout that sets the page image and returns the layout record (blocks with type, paragraphs with justification and first-line indent, lines with box and baseline, words with box and baseline) as one typed list, and recognize, which recognizes the image that layout kept, or a new image, and returns hOCR. Keep one native worker and one model in memory.

## Acceptance Criteria

Behavior tests, red first (native test runner, tool/reader native tests): the layout of the scanned fixture has its blocks, lines and words in Tesseract's order with boxes in raster pixels; the skewed fixture's line baselines have a slope of 2.5 degrees within 0.2; an image block reports a picture type. hOCR from recognize after layout is byte-identical to hOCR from recognize alone on the scanned, skewed and dense pages, so recognized text and digests do not change. Only one TessBaseAPI handle exists. The pinned AAR and source keep their hashes. Record the native change's size in the ticket.
