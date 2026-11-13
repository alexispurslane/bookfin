---
id: boo-3q1m
status: open
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

