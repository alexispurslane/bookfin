---
id: boo-eisp
status: open
deps: [boo-gnx9]
links: []
created: 2026-11-08T14:56:46Z
type: feature
priority: 3
assignee: Alexis Purslane
parent: boo-fs0n
tags: [platform, ios]
---
# Run Bookfin on iOS

Bookfin targets Android today. Flutter can build the same code for ios. Find what blocks it (playback and background audio, downloads and storage paths, the native reader libraries PDFium and libmobi, Tesseract OCR, the Nix build), then make the app build, run, and keep the same data-safety rules there. Requested by the user on 2026-11-08.

## Acceptance Criteria

A ios build of Bookfin signs in, browses the library, plays a downloaded audiobook, opens an EPUB and a PDF, and syncs personal records; platform-specific gaps are recorded as tickets.

