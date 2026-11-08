---
id: ta-tso8
status: in_progress
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


## Notes

**2026-11-08T00:26:10Z**

Orchestrator, Nov 7: group C does this. Decision: the server copy wins, because an action is immutable and the server holds the copy that was uploaded before any local damage. The differing local copy is kept aside like other damaged data (never deleted), and sync continues. Report it on the Sync page's quiet status line (the t9-pols decision), with no dialog.
