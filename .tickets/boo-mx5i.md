---
id: boo-mx5i
status: open
deps: [boo-9wgg]
links: []
created: 2026-11-01T21:37:34Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Add supported MOBI and PDF reflow reading

Integrate the validated MOBI path and PDF original-page/reflow views. Preserve source-page links and describe unsupported document cases.

## Design

docs/plans/bookfin.md

## Acceptance Criteria

Supported sample corpus passes on Android. Reflow wraps extracted text to width. Scanned and complex documents use an explicit fallback or the separately agreed OCR path.

