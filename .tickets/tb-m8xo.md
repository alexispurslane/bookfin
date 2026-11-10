---
id: tb-m8xo
status: open
deps: [tb-lnak, tb-0mex]
links: []
created: 2026-11-10T12:53:21Z
type: feature
priority: 1
assignee: Alexis Purslane
parent: boo-fval
---
# Leave running headers and folios out of the PDF word view

T5 of docs/plans/pdf-word-image-reflow.md (Trimmed margins: Page words). layoutColumn skips the lines that the page analysis marks as header or folio. Their text stays in the reading text, so search still finds it. A place inside a skipped line resolves to the first shown piece after it.

## Acceptance Criteria

Behavior tests, red first: the word view of the fixture book shows no running header and no folio; footnotes and figures still show; search for a header word opens the page's first screen; a place inside a header opens the screen of the next shown word; the screens of a page do not change when its text arrives.

