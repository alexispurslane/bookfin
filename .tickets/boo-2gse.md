---
id: boo-2gse
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
# Start the catalog restore before the other data sources open

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: confirmed, size of the delay not measured. lib/main.dart:71-87 awaits `openSources` (appearance, Downloads, Playback with `AudioService.init`, covers) before `runApp`. `CatalogController` is built inside the widget tree (main.dart:260-269), so `restore()` starts only after that. The time to the saved library is the sum of the two, not the larger of the two. Build the controller in `runBookfin` with the other sources and start `restore()` before `await openSources`. Related: tf-mo5q, boo-8v53.

