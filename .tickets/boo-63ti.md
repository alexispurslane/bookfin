---
id: boo-63ti
status: open
deps: []
links: []
created: 2026-11-07T21:36:12Z
type: task
priority: 4
assignee: Alexis Purslane
parent: boo-fs0n
tags: [performance]
---
# Use Playback's edition index in the remaining library scans

From the boo-8dkw report. sourceName, _restorePosition, _selectedEdition and the edition lookup in bind still scan the library; progress(edition) and durationMilliseconds walk an edition's files on each call. Use the edition index and the stored file offsets from boo-8dkw. Off the hot path, so low priority.

