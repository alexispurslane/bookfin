---
id: boo-5ivg
status: open
deps: []
links: []
created: 2026-11-12T23:41:02Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Decode the admitted EPUB record off the UI isolate at reopen

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: confirmed on the UI isolate, size estimated. lib/reader/epub/publication.dart:243-268, called from lib/reader/admitted_books.dart:280. Each reopen decodes the JSON header of the record (the text of every style sheet, the contents list, the image sizes) and copies every text file, 2 to 10 MB, on the UI isolate while the kept page already accepts taps. Do the decode and the split in the worker hop that reads the record, and return the bytes through `Isolate.exit`. Related: t6-0yez (measurement), t0-r8ii.

