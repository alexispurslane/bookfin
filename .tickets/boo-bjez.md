---
id: boo-bjez
status: open
deps: []
links: []
created: 2026-11-12T23:41:01Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Build the PDF contents and book map from the outline that crossings measure

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: confirmed. lib/reader/pdf_viewport.dart:339-342 lists one "Source page N" entry for each page, and `BookMap.pages` (lib/reader/book_map.dart:104) has no chapters. `measurePdfOutline` (lib/reader/pdf_outline.dart) already reads the PDFium bookmarks and the characters of each page, but only for cross-edition landings. A 500-page PDF shows 500 contents rows, the chapter arrows turn single pages, and the scrub bar has no chapter marks. Build the contents and the BookMap from the same outline. Related: te-hzt6 (time left only).

