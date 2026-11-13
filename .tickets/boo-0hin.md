---
id: boo-0hin
status: open
deps: [boo-f9xa]
links: [boo-f9xa, boo-p9s3]
created: 2026-11-12T23:41:01Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Give the PDF a pager that the reader session owns

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: confirmed. `_PdfViewportState` (lib/reader/pdf_viewport.dart:94) implements `DocumentNavigator`. The widget State loads pages, requests text and OCR, runs the whole-book search, draws previews and keeps the place, and the shown place has three copies. The EPUB has an `EpubPager` that the session owns. The session branches on the format in about 12 places. `onReady` runs 2 to 3 times for each page turn. Each call builds `pageCount` contents entries and fires `documentChanges`, which rebuilds the viewport, the scrub bar and the dock (pdf_viewport.dart:277, 309, 335, lib/reader/session.dart:206-218). Create a `PdfPager` that the session builds at open, attach the navigator and the contents once, and let `PdfViewport` only draw and report gestures. Closed ticket t9-3n2m set this target.

