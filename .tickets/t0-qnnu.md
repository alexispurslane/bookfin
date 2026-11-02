---
id: t0-qnnu
status: open
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
