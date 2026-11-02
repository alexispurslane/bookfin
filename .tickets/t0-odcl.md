---
id: t0-odcl
status: open
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
