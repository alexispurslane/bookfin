---
id: boo-f9xa
status: in_progress
deps: []
links: [boo-0hin, boo-p9s3]
created: 2026-11-12T23:41:01Z
type: bug
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Save the PDF page as the reading place as soon as the page shows

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: confirmed. lib/reader/pdf_viewport.dart:288-337. In the text view, `_publish()` runs only after `book.text(page)` returns. On a scanned page that is full recognition, 3 to 10 seconds, while the original image of the page already shows. A kill in that time leaves the saved place one page behind, and a series of fast turns saves nothing until the text of the last page arrives. Publish the page-level place (`PdfAddress(page, 0)`) when the page shows and refine it when the text resolves. Add a test: turn, kill before recognition ends, reopen.


## Notes

**2026-11-13T03:07:13Z**

Continuation recovered the existing second fixer, task node:delegated-task:command%3Amcp%3Af0e68da9-9404-43ac-a9da-69e376960cf2%3Adelegate-task%3Ae1eccf25-e75a-489c-a2c8-3e497a1bf668, child thread:delegated-task:command%3Amcp%3Af0e68da9-9404-43ac-a9da-69e376960cf2%3Adelegate-task%3Ae1eccf25-e75a-489c-a2c8-3e497a1bf668. It already uses codex/gpt-6-astra reasoningEffort xhigh. No replacement writer was started. Await its completion delivery before integration. boo-0hin now depends on this ticket.
