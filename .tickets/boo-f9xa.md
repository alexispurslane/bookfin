---
id: boo-f9xa
status: open
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

