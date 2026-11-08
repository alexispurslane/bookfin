---
id: boo-0wnc
status: open
deps: []
links: []
created: 2026-11-08T14:56:46Z
type: feature
priority: 3
assignee: Alexis Purslane
parent: boo-fs0n
tags: [platform, windows]
---
# Run Bookfin as a Windows desktop app

Bookfin targets Android today. Flutter can build the same code for windows. Find what blocks it (playback and background audio, downloads and storage paths, the native reader libraries PDFium and libmobi, Tesseract OCR, the Nix build), then make the app build, run, and keep the same data-safety rules there. Requested by the user on 2026-11-08.

## Acceptance Criteria

A windows build of Bookfin signs in, browses the library, plays a downloaded audiobook, opens an EPUB and a PDF, and syncs personal records; platform-specific gaps are recorded as tickets.

