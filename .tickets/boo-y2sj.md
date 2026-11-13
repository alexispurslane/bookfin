---
id: boo-y2sj
status: open
deps: []
links: []
created: 2026-11-12T23:41:00Z
type: bug
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Queue reading changes while the reading records are not ready

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: confirmed. lib/reader/session.dart:622-624 and 1697-1698. When `store.read` fails inside `bind`, `_recordsReady` stays false. `_save` then returns without a queue entry, and no code retries the read, so every page turn, bookmark and history move is dropped until the app restarts. The message tells the user to restart. Queue the changes in `_pendingWrites`, which already merges and retries, and retry the read on `flush`, `resume` or the next `bind`. The record-level merge of the store keeps the guarantee that unread records are not overwritten. Add a test for a failed read followed by a page turn.

