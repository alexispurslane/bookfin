---
id: boo-suhu
status: open
deps: [boo-mx5i]
links: [t0-qnnu]
created: 2026-11-02T00:07:18Z
type: feature
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Add bundled offline OCR for scanned PDF reading

User approved OCR for the ultimate feature set. Recognize text in scanned PDF pages locally to support reflow and search. Prefer a fast, simple engine bundled with Android; no cloud service or required first-use model download. Preserve original pages.

## Design

docs/plans/bookfin.md. Engine selection remains open; measure Android speed, memory, app size and recognition quality before choosing. Identify bundled language coverage and any optional language downloads explicitly.

## Acceptance Criteria

Demonstrate offline recognition after a fresh install on Android, reflow and search from recognized text, source-page positions, cached results, cancellable work and original-page fallback on recognition failure. Record representative scan accuracy, per-page latency, peak memory and packaged size. Document engine/model licenses and language coverage. Do not claim OCR fixes arbitrary reading order or tables.

