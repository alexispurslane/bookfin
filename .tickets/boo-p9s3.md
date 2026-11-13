---
id: boo-p9s3
status: open
deps: []
links: [boo-f9xa, boo-0hin]
created: 2026-11-12T23:41:01Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Keep the shown PDF page until the next page is drawn, and draw neighbor pages ahead

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: confirmed. lib/reader/pdf_viewport.dart:242-252 disposes `_image` before the new page is drawn, so each turn in the Original view shows a spinner for the whole PDFium render. No code draws the neighbor pages ahead. Each turn copies the page twice on the UI isolate (lib/reader/pdf.dart:1039-1044, pdf_viewport.dart:776-799). `renderPart` already decodes straight from the PDFium buffer. Keep the shown image until its replacement is ready, draw the next and previous page ahead within a limit of 1 or 2 images, and remove the intermediate copy. boo-wfg1 fixed the same flash for the word view only.

