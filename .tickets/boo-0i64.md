---
id: boo-0i64
status: open
deps: [boo-gnx9, boo-2sev]
links: []
created: 2026-11-08T14:56:46Z
type: feature
priority: 3
assignee: Alexis Purslane
parent: boo-fs0n
tags: [platform, linux]
---
# Run Bookfin as a Linux desktop app

Bookfin targets Android today. Flutter can build the same code for linux. Find what blocks it (playback and background audio, downloads and storage paths, the native reader libraries PDFium and libmobi, Tesseract OCR, the Nix build), then make the app build, run, and keep the same data-safety rules there. Requested by the user on 2026-11-08.

## Acceptance Criteria

A linux build of Bookfin signs in, browses the library, plays a downloaded audiobook, opens an EPUB and a PDF, and syncs personal records; platform-specific gaps are recorded as tickets.


## Notes

**2026-11-08T19:23:53Z**

Note from epic boo-b2ey (2026-11-08). EPUB and MOBI on this platform come from the native Flutter reader (tc-1yif), not from a flutter_inappwebview plugin. Do not port the WebView reader. The acceptance step 'opens an EPUB' needs tc-1yif. Building libmobi in the runner stays this ticket's job.
