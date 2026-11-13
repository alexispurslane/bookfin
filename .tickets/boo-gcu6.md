---
id: boo-gcu6
status: open
deps: []
links: []
created: 2026-11-12T23:41:00Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Write the settings of each record domain only when they change

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: confirmed. lib/playback/store.dart:900-913, 1216-1225 and 1444-1458. The listening settings and the reading settings share one account row. After the user changes the view setting of one PDF, `_smallSettings` returns false. From then on, every listening save (about one for each media-second) and every sync acknowledgment starts an isolate through `compute`, then encodes and rewrites the reading settings again. Store the settings of each domain separately and write them only when they change. Related closed ticket: boo-lj72.

