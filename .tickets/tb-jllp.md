---
id: tb-jllp
status: in_progress
deps: []
links: []
created: 2026-11-08T01:06:35Z
type: task
priority: 3
assignee: Alexis Purslane
parent: boo-bquq
tags: [engine-rules]
---
# Prepare PDF page text off the UI isolate

Rule: engine rule 1 (no heavy CPU work on the UI isolate).

Found in t9-3n2m. lib/reader/pdf.dart, _NativePdfBook._extractedText: after page.loadText(), the loop that collapses whitespace and builds sourceOffsets runs on the UI isolate. It calls substring and a RegExp for each character, and a page can hold up to 2,000,000 characters. The text warning check (_textWarning) also runs there.

t9-3n2m made PdfBook.addressFor compute the page text digest once for each page text, inline, because addressFor answers at once. A page that is near the size limit still hashes on the UI isolate once.

Target: one off-isolate call for each page builds the PdfText from the raw text and its character boxes, and it also computes the digest. addressFor then reads the digest that came with the text.

## Acceptance Criteria

- Opening a large text page does no per-character work on the UI isolate (a test that runs the preparation through the worker).
- Addresses keep the same representation as before for the same text (test).

