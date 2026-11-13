---
id: boo-yzvv
status: open
deps: []
links: []
created: 2026-11-12T23:41:01Z
type: task
priority: 3
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Limit how much text the PDF text view lays out at once

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: plausible, not observed. lib/reader/pdf_text_view.dart:18-32 lays out the whole page text with one TextPainter inside build, and lib/reader/pdf.dart:87-89 accepts a page text of up to 2,000,000 code units. A page with a very large text layer stops the UI isolate for seconds. Lower the limit to a page-sized value, or lay out one screen-sized slice at a time.

