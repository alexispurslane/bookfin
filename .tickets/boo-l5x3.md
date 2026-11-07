---
id: boo-l5x3
status: open
deps: []
links: []
created: 2026-11-07T21:30:01Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
tags: [durability]
---
# Prove that no listening history or book position can be lost

AGENTS.md engine rule 3. Audit every write path for positions, listening history and bookmarks (Playback, reader progress, the record store, RecordSync, Jellyfin progress sync). For each, check: local write before sync; atomic temp-then-rename writes; save on pause, seek, chapter change, book change and app background; older data never overwrites newer; a store that cannot be read is kept aside, not replaced with an empty one. Fix gaps and record larger ones as tickets.

## Acceptance Criteria

A test exists for each loss path: kill mid-write, failed sync, a conflicting device, a corrupt store file, and the app going to the background mid-playback. Each test fails if the protection is removed.


## Notes

**2026-11-07T21:40:02Z**

From boo-xifx: when an account with unsaved changes binds again, Playback now reads the store and lays its pending changes on top; a failed read fails the restore but keeps the pending changes for flush (test: 'unsaved changes survive an account switch whose restore read fails'). After a resolved bookmark conflict, the bookmark can show in a different list position until restart.
