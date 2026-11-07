---
id: boo-l5x3
status: in_progress
deps: []
links: []
created: 2026-11-07T21:30:01Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-bquq
tags: [durability, engine-rules]
---
# Prove that no listening history or book position can be lost

AGENTS.md engine rule 3. Audit every write path for positions, listening history and bookmarks (Playback, reader progress, the record store, RecordSync, Jellyfin progress sync). For each, check: local write before sync; atomic temp-then-rename writes; save on pause, seek, chapter change, book change and app background; older data never overwrites newer; a store that cannot be read is kept aside, not replaced with an empty one. Fix gaps and record larger ones as tickets.

Audit additions from boo-bquq at f388307. Make sure of each one:
- lib/playback/store.dart, _readAccount: a corrupt or mismatched store throws FormatException, and each later write fails in the same way. The file stays, but it is not moved aside, and the message says that records could not be saved, not that the store could not be read.
- lib/playback/store.dart, _persist without a database (platforms other than Android): the whole account is one SharedPreferences value. Its atomicity depends on the platform plugin. Prove it, or write the value with temp-then-rename.
- lib/main.dart, didChangeAppLifecycleState: flushes Playback and the reader on each state other than resumed. Prove that a kill right after the app is hidden keeps the last position.
- lib/reader/session.dart, acceptAddress: saves on each address change. Prove that the reader also saves on a chapter change, a book change and the app background.

Owned files: lib/playback/store.dart, lib/playback/database.dart, lib/sync/journal.dart, and new durability tests under test/durability/. If a fix needs lib/playback/playback.dart, lib/reader/session.dart, lib/sync/coordinator.dart or lib/main.dart, record a new priority 1 ticket under boo-bquq instead, because other tickets own those files in this wave.

## Acceptance Criteria

A test exists for each loss path: kill mid-write, failed sync, a conflicting device, a corrupt store file, and the app going to the background mid-playback. Each test fails if the protection is removed.

## Notes

**2026-11-07T21:40:02Z**

From boo-xifx: when an account with unsaved changes binds again, Playback now reads the store and lays its pending changes on top; a failed read fails the restore but keeps the pending changes for flush (test: 'unsaved changes survive an account switch whose restore read fails'). After a resolved bookmark conflict, the bookmark can show in a different list position until restart.
