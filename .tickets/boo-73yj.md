---
id: boo-73yj
status: in_progress
deps: [boo-gxm8]
links: [boo-mx5i, t3-ipk1]
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

## Parent review and partial integration

Independent review of b5d02cc80cbb4e37d7cf5573936216ca7e05b179 permits partial research integration, not ticket closure. F1 corrected by documenting a final report command after APK creation that requires the APK and checks both packaged engine hashes. F2 corrected by adding t9-26f6 as a prerequisite of boo-mx5i. Source-anchor wording now distinguishes source resolution from reader resume. User accepted the sample reflow and approved future OCR in boo-suhu; OCR is not implemented. Android runtime, representative corpus and production package approval remain unverified.

Parent verification: executed the documented final report against the builder's existing artifacts through the research Nix shell. Initial attempt exposed missing PDFIUM_LIBRARY; corrected the command to supply the extracted pinned library path. Final command passed and both engine_provenance matches were confirmed true. No Android runtime or full suite rerun is claimed. Dependency-cycle and whitespace checks passed.

**2026-11-02T11:14:09Z**

2026-11-02 continuation from main e8fe9c7: bounded runtime proof now runs on local/emulator-5554, Android API 36 ARM64, in separate com.example.reader_packaging_probe. Original PDF pages and raster-only scan render; real extracted text uses fixed 18-logical-pixel body size and shows 6/4 rendered lines at widths 200/360 in the retained screenshots (the original independent painter incorrectly labeled the wide paragraph as 3). Page-2 source link returns to original page 2; source hash, ASCII character index 39 and rectangle are recorded, not persisted resume/highlighting. All three original MOBI assets convert natively on Android and are parsed in that same process as PDFium. Plain/PalmDOC PNG previews work; KF8 text works but its first SVG fails in the raster-image preview. t3-9r9u tracks MIME-aware reader handling. Patched, source-hash-pinned EPUBX 4.0.0 is a concrete compatible parser candidate, not approved production selection. The final APK requests no INTERNET permission and all three packaged native engine/bridge hashes match the pinned proof. 27 host behavior checks pass. Native license texts are bundled byte-for-byte; a Latin-1 notice-view error was reproduced and fixed test-first. LGPL release/relink/install compliance remains t3-ipk1. Evidence and exact limits are in docs/research/reader-formats.md and tool/research/readers/evidence/android-runtime/. No private corpus exists and none is claimed; that does not block this finite generated-corpus proof. No production reader, OCR, Jellyfin access, browser, children, coverage/mutation or PR. Parent reviews/integrates and alone closes tickets.

**2026-11-02T11:45:10Z**

Parent corrected review F1-F3: displayed reflow measurement now uses the same effective text span/constraints as rendering, with a meaningful failing widget regression. Removed independent loading-report painter. Historical screenshots show6/4 lines; old6/3 standalone counts are explicitly distinguished without altering raw logs/screenshots. Corrected widget is host-tested, not newly observed on Android. Added SVG dependency before boo-9wgg and redistribution dependency before boo-gk92; no cycle. run --keep-fixtures preserves committed inputs; explicit regeneration remains separate, with a red-green runner regression. All30 host checks and research APK build pass; complete preserved-fixture run leaves every input hash unchanged. Evidence parent-review-corrections.json. Review/integration pending, no package approval or closure.
