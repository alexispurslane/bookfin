---
id: t9-hkx5
status: open
deps: []
links: []
created: 2026-11-08T00:30:49Z
type: task
priority: 3
assignee: Alexis Purslane
parent: boo-bquq
tags: [ui-rules]
---
# The recently listened list follows a library refresh

Found in tc-qdk7. RecentListeningList in lib/playback/recent.dart follows Playback.recordsNotifier and selectionNotifier. Its rows come from Playback.recent and Playback.progress, which read the bound library. A library refresh of the same account, while no book is open, changes neither signal, so the list keeps the old books and times until the next records change. tc-qdk7 added Playback.libraryNotifier, which notifies on each bind. Merge it into the list's listenable.

## Acceptance Criteria

With no book open, a library refresh that changes the length of a listened edition updates the time left in its recent row. A playing tick still rebuilds no recent row.

