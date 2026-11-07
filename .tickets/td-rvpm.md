---
id: td-rvpm
status: open
deps: [boo-4bof]
links: []
created: 2026-11-07T23:04:52Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-bquq
tags: [durability, engine-rules]
---
# Set an unreadable record store aside and keep saving new places

Found by boo-l5x3. Today a record store that cannot be read blocks its account: LocalResumeStore._readAccount throws FormatException on each read and write, the data stays in place, and Playback and the reader keep new places only in memory. A kill then loses every place and history event since the store broke. Playback reports this as 'Personal records could not be saved. Free storage and try again.', which names the wrong cause. A SQLite file that cannot be opened (RecordDatabase.open fails) blocks every account the same way.

AGENTS.md engine rule 3 says: if a store cannot be read, keep the file aside and report it, and do not replace it with an empty store.

User-visible fork, two designs:
A. Set aside and start fresh. The store copies the unreadable value or rows, or the whole SQLite file, to a set-aside place, then starts the account with a new installation identity. The next sync downloads every synced record from the server again, so only unsynced records stay only in the set-aside copy. The store publishes a narrow signal of set-aside accounts. Playback and the reader show it in place of the save error. Cost: the shelf and history look empty until the sync finishes or forever when offline, and a recovery path for the set-aside copy is new work.
B. Keep blocking, but save new records beside the store. The store keeps the unreadable data in place and writes new places to a second store for the account until the user acts. Cost: two stores for one account, and a merge on recovery.

Files: lib/playback/store.dart, lib/playback/database.dart (set-aside table or file move, schema version 3), lib/playback/playback.dart and lib/reader/session.dart (the report and the message), and the tests that assert the blocking behavior: test/reader/persistence_test.dart ('malformed outer storage preserves data', 'damaged reading records are guarded'), and the Playback restore-failure tests.

## Acceptance Criteria

A test for each: a damaged preference value, damaged SQLite rows and a SQLite file that cannot be opened keep the damaged data intact, report it to the user, and let new places survive a kill. Each test fails when its protection is removed.


## Notes

**2026-11-07T23:11:07Z**

Decided by the user on November 7, 2026: Design A with salvage. When the record store cannot be read, the damaged data is renamed and kept (never deleted), a new store starts at once so new places survive a kill, and every record that still parses is copied from the damaged data into the new store, so most history and places show at once, even offline. The next sync refills the rest. The message names the real cause (a damaged store, not free storage). Tests: a damaged store keeps its file, salvages readable records, skips broken ones, saves new places that survive a restart, and syncs without duplicates.
