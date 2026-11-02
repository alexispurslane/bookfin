---
id: boo-73yj
status: in_progress
deps: [boo-gxm8]
links: []
created: 2026-11-01T21:37:34Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Prove Android MOBI and PDF reflow support

Evaluate offline reader and conversion candidates against representative EPUB, MOBI, HTML, Markdown, text PDF, multi-column PDF, and scanned PDF inputs. Check licenses and Android packaging.

## Design

docs/plans/bookfin.md

## Acceptance Criteria

Record supported variants and known limits. Demonstrate true PDF text reflow and original-page fallback. Decide OCR scope separately. No package selected only from marketing claims.


## Notes

**2026-11-01T23:57:55Z**

Research completed in t3/research-reader-formats from a6bfc1cc82b1ce8dc1705fee5408d868a9dfb6a1. See docs/research/reader-formats.md and tool/research/readers/evidence/. Sixteen host checks pass (9 Python, 3 Dart PDF/Markdown, 4 Dart EPUB/conversions). Meaningful initial red failures and a separate crop-versus-scale regression are captured. Generated MOBI6 plain/PalmDOC plus versioned public-domain Alice standalone KF8 convert to EPUB with text/images read back by Dart. PDF text reflows at 360/720 PDF-point widths (10/8 lines at fixed 18-point body text), with source-page character anchors. A table sample demonstrably loses row relationships. A raster-only scan renders but has no extracted text; no OCR added. Android ARM64 libmobi source build (161152 bytes), pinned PDFium (6598376 bytes), and joint native link probe pass. An isolated pdfrx Flutter debug APK builds and passes 16-KiB ZIP alignment, but was not installed or launched. No device interaction or user corpus validation occurred. Research-only SDK platforms 35/36 avoid changing the shared flake. Follow-up t9-26f6 tracks shared SDK 35 requirement. EPUBX/pdfrx dependency conflict is reproduced. Pending gates: user corpus, EPUB navigator integration, libmobi maintenance/LGPL redistribution review, PDF image-in-reflow choice if scope requires it, Android runtime and later orchestrated hardening. Ticket remains in progress for parent review/integration.
