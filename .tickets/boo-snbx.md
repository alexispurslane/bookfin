---
id: boo-snbx
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
# Draw each scanned PDF page once for analysis and recognition

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: two renders confirmed, the third plausible. lib/reader/pdf.dart:316-342 renders a page at 1600 px for analysis. `book.geometry` then runs the OCR layout pass, which renders the same page again (lib/reader/ocr.dart:219-225), and `_recognize` renders a third time when the layout of another page ran in between (ocr.dart:653). Each render copies 13 to 25 MB into the Dart heap. More copies follow into the `compute` isolate and through the method channel as BGRA, although Tesseract needs 8-bit gray. The background survey renders every scanned page twice. Give the analysis raster of each page one owner that feeds both jobs, and send gray pixels to the platform.

