---
id: ta-tso8
status: open
deps: []
links: []
created: 2026-11-08T00:13:00Z
type: task
priority: 3
assignee: Alexis Purslane
parent: boo-bquq
tags: [durability, sync]
---
# Report a damaged action whose server copy differs instead of blocking sync

Found by td-rvpm. Salvage keeps each damaged-store action that still decodes under its identity. If damage changed an action's content but left it valid, the next sync receives the server's copy under the same identity, and RecordJournal.receive throws 'An immutable sync action changed.' on every sync. The same holds for undetected damage in a healthy store. Decide whether the server copy wins, and report the difference.

