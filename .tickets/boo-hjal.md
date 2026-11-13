---
id: boo-hjal
status: open
deps: []
links: []
created: 2026-11-12T23:41:02Z
type: task
priority: 3
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Send each EPUB section prepare only the style sheets that the section uses

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: plausible. This is worker time, not UI time. lib/reader/epub/page_source.dart:1524-1535 and lib/reader/epub/prepare.dart:1142-1220. Each section prepare copies the text of every style sheet and every image size into a new isolate and parses the linked sheets again. A book with 300 sections and 300 KB of CSS copies about 90 MB and parses the same sheets 300 times for each page settings value. Record the sheets of each section at admission, as `sectionFaces` already does. Measure before a long-lived worker caches parsed sheets.

