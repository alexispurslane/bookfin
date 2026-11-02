---
id: t0-ebxa
status: open
deps: [boo-73yj]
links: [boo-mx5i]
created: 2026-11-02T12:38:42Z
type: bug
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Prove PDFium callback ownership across Dart isolates

The November 2 host public-corpus run added a second PDF test file. Running both with the Dart default file concurrency aborts with exit 134: Cannot invoke native callback from a different isolate. The stack includes CFX_ExternalFontInfo::MapFont and FPDF_LoadPage. Individual suites pass. Research records the raw abort and serializes PDF test files; this does not establish safe concurrent production PDFium initialization.

## Design

docs/plans/bookfin.md; docs/research/reader-public-corpus.md; tool/research/readers/evidence/corpus/pdf-concurrent-abort.txt. Retain one coherent owner for native initialization, font callbacks and engine lifetime. No production engine redesign is selected by the research workaround.

## Acceptance Criteria

Reproduce the pinned callback-ownership failure in an isolated host process and establish the supported engine/worker ownership model. Prove safe document work through that model, including close/reopen and multiple callers, before parallel extraction or rendering is claimed. Preserve a nonzero crash report; do not catch native failures as ordinary parser rejection. Verify Android separately rather than generalizing a macOS observation.


## Notes

**2026-11-02T12:51:26Z**

Serial PDF test-file execution passes all eight PDF/Markdown checks together on the host. This is a research-runner remedy only, not evidence of safe concurrent production initialization or Android callback ownership.
