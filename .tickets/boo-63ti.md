---
id: boo-63ti
status: in_progress
deps: [boo-petv]
links: []
created: 2026-11-07T21:36:12Z
type: task
priority: 4
assignee: Alexis Purslane
parent: boo-bquq
tags: [performance, engine-rules]
---
# Use Playback's edition index in the remaining library scans

From the boo-8dkw report. sourceName, _restorePosition, _selectedEdition and the edition lookup in bind still scan the library; progress(edition) and durationMilliseconds walk an edition's files on each call. Use the edition index and the stored file offsets from boo-8dkw. Off the hot path, so low priority.

Rules: engine rule 1 (modest CPU work on the UI isolate).

Owned files: lib/playback/playback.dart and its tests. Order: after boo-petv, which changes _currentEdition in the same file.

## Acceptance Criteria

Each listed lookup uses the edition index. A test with a large fixture library shows that no call scans the whole library.
