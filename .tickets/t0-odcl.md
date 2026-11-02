---
id: t0-odcl
status: in_progress
deps: [boo-73yj]
links: [boo-mx5i]
created: 2026-11-02T12:30:43Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Prevent misleading reflow order for real three-column PDFs

The pinned November 2 public corpus includes Federal Register notice 2023-28812, two three-column pages. The existing two-column geometry proof combines unrelated left/middle/right text in individual blocks, including USDA and Census text. A successful PDF parse and source anchor do not mean the reflow is readable. Preserve original-page access and establish how the reader handles uncertain three-column order before promising support.

## Design

docs/plans/bookfin.md; docs/research/reader-formats.md; tool/research/readers/corpus-manifest.json. This is follow-up work, not a production layout solver selected by research.

## Acceptance Criteria

Use the hash-pinned real notice to demonstrate readable column order or an explicit uncertain-reflow fallback. Keep the complete original page accessible. Measure paragraphs, headers, footers and cross-page continuations. Do not claim universal PDF reflow or treat count/phrase checks as fidelity acceptance.


## Notes

**2026-11-02T12:51:26Z**

The sampled first page retains 5,748 nonspace characters at both host reflow widths, yet mixes columns. Character retention against extracted source text therefore cannot be the fidelity acceptance criterion. Source and reflow previews and the independent Poppler layout output are retained.

**2026-11-02T13:15:24Z**

Start shared PDF text-quality follow-up with t0-qnnu. Approved existing policy permits explicit original-page fallback when reflow is unreliable. Do not silently present mixed-column text as successful reading.

**2026-11-02T13:47:06Z**

Implementation follow-up from 5815233: shared page-local text-quality policy now rejects both pinned Census pages for mixed source ranges and parallel text groups before reading-PDF generation. Raw extraction and anchors remain unchanged. NIST page 5 retains useful paragraph reflow, headings/footer order and anchors at two widths. Evidence and exact reproduction: docs/research/reader-public-corpus.md, evidence/text-quality/. Final checks: 37 Python, 21 Dart, 5 isolated Flutter widget tests through Nix; no Android verification, universal layout claim, OCR, coverage/mutations or closure. Ready for parent review/integration.
