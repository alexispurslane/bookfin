---
id: tb-valc
status: in_progress
deps: [tb-lnak]
links: []
created: 2026-11-10T12:53:21Z
type: feature
priority: 1
assignee: Alexis Purslane
parent: boo-fval
---
# Trim the margins, running header and folio of the PDF Original view

T3 of docs/plans/pdf-word-image-reflow.md (Trimmed margins: The Original view). PdfViewport's original page shows the page's crop: it renders the page at the screen width divided by the crop's share of the page width (within the existing render limits) and draws only the crop, fitted to the screen. A page never changes its crop while it shows: a crop that becomes known later applies from the next page the reader shows. A page whose crop is not known waits up to 300 ms for it before its first draw, then shows uncropped. When a page shows, the next page in the reading direction gets its analysis first in the survey. Pinch zoom and pan work on the cropped page as today, up to 6 times. The scrub deck cards use a known crop and never wait for one.

## Acceptance Criteria

Behavior tests, red first: a body page shows only its content, without margins, header and folio; two body pages of one side show their text at the same size and place; a wide-table page shows all of its table; a page shows uncropped until its crop is known and keeps its look until the next turn; a page whose crop is ready within 300 ms shows cropped from its first frame; the next page's crop is ready before a turn in the normal case; pinch zoom and pan still work, and a swipe on a zoomed page moves it; the deck shows cropped cards when crops are known. No crop work runs on the UI isolate.

