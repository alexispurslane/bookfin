---
id: te-t5oi
status: open
deps: []
links: [boo-0hin]
created: 2026-11-13T03:59:18Z
type: task
priority: 3
assignee: Alexis Purslane
parent: boo-fs0n
tags: [reader, pdf, engine-rules]
---
# Match PDF search text away from the UI isolate

Found while extracting boo-0hin. Static inspection confirms that PdfPager.search (formerly _PdfViewportState.search) runs RegExp.allMatches, builds excerpts and resolves search-hit addresses on the UI isolate for each entire PDF page. PdfBook admits page text up to 2,000,000 code units. No frame-time measurement was run. Preserve the current search result, 200-hit limit, cancellation and failed-page reporting while moving per-page matching into batched worker work. The ownership extraction deliberately preserves this algorithm.

## Acceptance Criteria

Large-page matching runs outside the UI isolate. Existing search results, ordering, cancellation, result limit and failure reporting remain covered by behavior tests.

