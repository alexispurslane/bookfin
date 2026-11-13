---
id: boo-esnm
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
# Write heard windows without a rewrite of the whole edition store for each window

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: confirmed, low severity. lib/speech/heard_windows.dart:142 and 380-391. Each new window starts an isolate through `compute`, encodes every window of the edition and rewrites the whole file, so a fill of W windows writes on the order of W squared bytes. Combine the writes, at most one for each edition every few seconds, or store the windows of each file separately.

