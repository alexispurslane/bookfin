---
id: tb-t0ea
status: closed
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

## Notes

**2026-11-10T13:18:29Z**

Built (2026-11-10). Native change size: native/ocr/bookfin_ocr.c 177 lines of C, native/ocr/CMakeLists.txt 16 lines, native/CMakeLists.txt 7 lines (new CMake root that adds mobi/ and ocr/), nix/ocr.nix +18 lines (androidNative: the AAR's jni/<abi> libraries and capi.h with export.h), OcrChannel.kt rewritten around one C API handle (TesseractC and TesseractEngine), OcrWorker.java +46 lines (layout and recognizeKept on the one admission path). The pinned AAR and source keep their hashes. Device tests: integration_test/ocr_layout_test.dart, run with tool/reader/ocr_layout_device_test.py <your emulator>. Emulator times (own AVD, android-36 google_apis arm64-v8a, debug build, one run; layout / recognition after layout / recognition alone, ms): scanned 116/88/226, skewed 115/95/211, nist-cloud p3 111/501/619, nist-cloud p6 192/1321/1510, census-notice p1 342/2581/2876, census-notice p2 347/2588/2813, raven-1873 p12 137/713/855, raven-1873 p13 131/219/360. hOCR after layout is byte-identical to hOCR alone on 35 of 35 pages (all pages of the 3 corpus PDFs and both fixtures), and equals the Java engine's hOCR on the 8 golden pages. Evidence: tool/evidence/reader/layout-pass/20261110/.
