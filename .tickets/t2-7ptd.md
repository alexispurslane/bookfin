---
id: t2-7ptd
status: in_progress
deps: []
links: []
created: 2026-11-08T01:23:12Z
type: task
priority: 3
assignee: Alexis Purslane
parent: boo-bquq
tags: [engine-rules]
---
# Decode recognized PDF page text off the UI isolate

Rule: engine rule 1 (no heavy CPU work on the UI isolate).

Found in tb-jllp. lib/reader/ocr.dart, decodeRecognizedPage runs on the UI isolate. It parses the hOCR XML of a recognized page (up to 8,000,000 characters), runs the row check, builds sourceOffsets one character at a time, and, since tb-jllp, computes the page text digest (pdfTextDigest). It runs after recognition (BundledEnglishText.text) and for each cached page read (_cachedPage).

Target: one off-isolate call for each recognized page decodes the hOCR into the PdfText, digest included, through an injectable hop as in PdfRuntime.open.

## Acceptance Criteria

- Opening a recognized page or a cached recognized page does no per-character work on the UI isolate (a test that runs the decode through the worker).
- Recognized addresses keep the same representation for the same text (test).


## Notes

**2026-11-08T01:38:26Z**

BundledEnglishText decodes each recognized page, new or cached, in one hop through PdfHop (default compute). A cached decode re-checks the request after the hop, so a canceled page delivers no late text. For a page of 7,980,073 hOCR characters, the longest UI-isolate stall fell from 878-1,311 ms to 17-19 ms (one round of 64 ms under load; the idle stall was 1-13 ms).
