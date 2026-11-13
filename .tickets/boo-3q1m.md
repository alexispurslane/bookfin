---
id: boo-3q1m
status: closed
deps: []
links: []
created: 2026-11-12T23:41:01Z
type: bug
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Open PDFs larger than 64 MiB

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: confirmed. lib/reader/platform_io.dart:185-203. `_verifiedFile` applies `Publication.maxArchiveBytes` (64 MiB) before the format is known. That limit exists because EPUB bytes enter Dart memory. PDFium reads a PDF from its path, so the limit refuses every large scanned PDF with "missing or exceeds 64 MiB". It also fails `measureDownloadedOutline` and `prepareDownloadedBook` for that edition. Apply the size limit only to EPUB and MOBI. Add a test with a PDF above the limit.


## Notes

**2026-11-13T01:27:38Z**

Fixed. The file guard of the reader now tests only that the download is a regular local file. The 64 MiB limit moved to `_archiveBytes`, the one read of EPUB bytes into memory (lib/reader/platform_io.dart). The MOBI conversion keeps its own limit. Verification: test/reader/large_pdf_test.dart failed with "missing or exceeds 64 MiB" before the change and passes after it (3 tests). It opens a valid 64 MiB PDF through PDFium and reads its text. The neighbor loader tests pass (78 tests).
