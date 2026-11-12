---
id: boo-sy2d
status: in_progress
deps: [boo-yjq6]
links: []
created: 2026-11-11T20:09:32Z
type: feature
priority: 2
assignee: Alexis Purslane
parent: boo-tam0
---
# Open books faster: design A, admit at download and show the kept last page

Design A of docs/plans/faster-book-open.md, chosen by the user 2026-11-11.


## Notes

**2026-11-11T23:22:22Z**

User 2026-11-11: do the MOBI to EPUB conversion when the download completes. Design A's download-time admission must include the libmobi conversion and keep the converted EPUB, so a MOBI's first open takes the cached path like an EPUB (measured: conversion 253 ms of the MOBI's 508 ms first open after the quick wins).

**2026-11-12T00:26:47Z**

Step 1 (admission at download): Downloads takes a prepare hook (LocalDownloads.prepare). It prepares each saved file of a text edition once its download completes and again after each restoration at launch, one at a time, under a hold of the download. prepareDownloadedBook (lib/reader/platform_io.dart) admits an EPUB and keeps its admitted record; for a MOBI, prepareMobi converts it with libmobi, keeps the converted EPUB, and keeps the admitted record. A PDF needs no preparation. A load that starts during a preparation waits for it and reads the record (AdmittedBooks.written). A preparation whose record is current reads only the key line and does nothing more. A failed preparation leaves the download whole and shows nothing.
