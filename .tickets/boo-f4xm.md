---
id: boo-f4xm
status: in_progress
deps: []
links: [boo-s11s, boo-n7no]
created: 2026-11-12T23:41:00Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Move the sync transport out of the playback store and let writers register with the store

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: confirmed. lib/playback/store.dart (2,109 lines) owns durable storage, damage set-aside, the plugin wire protocol (451-637), writer baselines, and the value formats of each domain. lib/sync/coordinator.dart:166-168, 225-235 and 294-299 repeat the sequence "flush each writer by name, sync, refresh each stale writer" in three places. A missed flush already caused finding F2 of boo-3oq0. Move the transport into lib/sync as a module that calls named store operations: pending uploads, acknowledge, receive a page with its cursor, take server copies. The store exposes "this domain is behind" as a listenable, and each writer registers its flush once. Move the address and value codec of each domain next to HistoryEvent and Bookmark.

