---
id: boo-hd47
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
# Compute the contents entries of each EPUB section once, not at each page turn

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: path confirmed, cost estimated. lib/reader/epub/pager.dart:761-777 and lib/reader/epub/places.dart:237-276. Each reported page turn resolves the URL of every contents entry in the book, walks the section DOM for a heading, and scans all text nodes with `indexOf`. A book with thousands of contents entries (a Bible, collected works) spends an estimated 2 to 10 ms for each turn on the UI isolate. lib/reader/epub/search.dart:232-253 already filters entries by section. Compute the entries and the heading once for each prepared section.

