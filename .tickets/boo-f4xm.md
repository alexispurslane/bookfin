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


## Notes

**2026-11-13T02:57:00Z**

Astra-only continuation: lead node:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-boo-f4xm-astra-20261112-1; child thread:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-boo-f4xm-astra-20261112-1; clientRequestId bookfin-boo-f4xm-astra-20261112-1. Lead uses codex/gpt-6-astra reasoningEffort xhigh; fresh reviewer uses the same model with high. Base d5b1686db9b09c30770a0a39a091164be551434c. Required checks and integration remain pending.
