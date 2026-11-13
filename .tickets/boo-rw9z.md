---
id: boo-rw9z
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
# Make Playback.flush wait only for record writes

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: confirmed. `flush()` (lib/playback/playback.dart:1756-1770) awaits the whole command queue and `reports.idle`, the chain of Jellyfin progress reports with 20-second timeouts. `SyncCoordinator` awaits `flush()` before each sync (lib/sync/coordinator.dart:225, 294). A slow network delays a sync that the user started, and a command that never returns blocks every later sync. `flush` saves the current place and awaits only the record writes. A caller that also needs the reports drained asks for that separately.

