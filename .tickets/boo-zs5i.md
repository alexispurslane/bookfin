---
id: boo-zs5i
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
# Hand typed conflict versions and typed record addresses to the sync screens

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: confirmed. `RecordConflicts` (lib/sync/coordinator.dart:54) passes raw action maps to the widgets. lib/sync/labels.dart:274-314 decodes positions by itself, beside the typed decoders that the store uses. Code parses the record address string with `jsonDecode` in lib/sync/journal.dart:159, lib/playback/store.dart:684-709 and labels.dart. A format change (ta-6ycs and ta-4fhn are queued) must find each decoder, and a missed one fails silently as "preview unavailable". The store hands out typed conflict versions from the decoders that validate actions, and a typed address (domain, collection, id) replaces the string parsing.

