---
id: t0-qnnu
status: closed
deps: [boo-73yj]
links: [boo-mx5i, boo-suhu]
created: 2026-11-02T12:33:22Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Handle scanned PDFs with unusable pre-existing text layers

The November 2 public corpus Raven 1873 LOC scan has 24 image pages and an existing text layer. Pinned PDFium extracts text, but source page 9 becomes 37 short fragments in the geometry reflow, mixing the poem order. Rendering preserves the readable scan. A nonempty extracted-text result does not establish usable reflow or remove the need for future OCR. Research did not run OCR.

## Design

docs/plans/bookfin.md; docs/research/reader-formats.md; tool/research/readers/corpus-manifest.json. Keep source identity, original-page access, and account-local derived caches under their existing owners. Parent decides OCR policy under boo-suhu.

## Acceptance Criteria

Use the pinned source scan and image-only derivative to distinguish absent text, unusable existing text and usable text per page. Keep original pages accessible without an empty or misleading success claim. Establish when an existing text layer can be retried with the approved future offline OCR path. Do not select an OCR engine or claim recognition quality from text-layer presence alone.


## Notes

**2026-11-02T12:47:58Z**

Precision from independent Poppler layout extraction: the source text layer misses the opening O in ONCE and misreads the decorative title, but much of the verse order survives in Poppler layout output. The research geometry path adds severe fragmentation and reordering. Distinguish those two causes; do not label every existing text layer unusable or attribute all errors to prior OCR. evidence/corpus/raven-page9-poppler-layout.txt preserves the comparison.

**2026-11-02T13:12:05Z**

Production PDF integration boo-mx5i now depends on this safe-handling gate: identify unreliable existing text and preserve an explicit original-page fallback. OCR implementation remains under boo-suhu, downstream of boo-mx5i; completing this gate does not require implementing OCR or selecting its engine.

**2026-11-02T13:15:24Z**

Work alongside t0-odcl under one PDF text-quality decision. Prove safe fallback with real corpus and retain usable simple text. No OCR implementation or engine selection in this follow-up.

**2026-11-02T13:47:06Z**

Shared implementation with t0-odcl distinguishes absent text, independently observed source-layer defects, and extraction-order/fragmentation errors. Raven page 9 falls back with 37 fragments; the nine-fragment library stamp also falls back. The exact historical image-only derivative is retained byte-for-byte and verified against its recorded hash. Source errors are bound only to the independently compared page 9; other source layers remain unchecked. Future offline OCR eligibility remains boo-suhu; no OCR or package selection. Checks: 37 Python, 21 Dart, 5 isolated Flutter widget tests through Nix. Host evidence only; ticket remains in_progress for orchestrator integration.

**2026-11-02T14:13:40Z**

Integrated reviewed ffc771c in fb6b11a. Bounded research acceptance passed independent review; parent boundary/fixture-preservation checks pass (11). No OCR or production Android claim. Full corpus evidence remains builder-run.
