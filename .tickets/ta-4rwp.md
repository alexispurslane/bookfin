---
id: ta-4rwp
status: open
deps: []
links: []
created: 2026-11-08T00:13:00Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-bquq
tags: [durability, engine-rules]
---
# Set the record file aside when SQLite reports corrupt pages after it opened

Found by td-rvpm. RecordDatabase.open sets a file aside only when the open itself reports SQLITE_CORRUPT or SQLITE_NOTADB. A file that opens but whose pages are corrupt makes RecordDatabase.rows throw a DatabaseException (code 11) on each read, and a row with a non-text value makes it throw a TypeError. Both still block the account: the read fails, Playback and the reader report 'Cannot restore' or 'could not be opened', and nothing is set aside. The fix sets the whole file aside, as open does, which needs the store to close and reopen its shared database.

## Acceptance Criteria

A test for each: a record file with a corrupt page after open, and a record row with a blob in a text column, keep the damaged data, report it, and let new places survive a kill.


## Notes

**2026-11-08T00:26:10Z**

Orchestrator, Nov 7: group C (one agent for tf-0nvi, boo-7ua0, ta-4rwp, ta-tso8) does this, because all four change the record store and sync.
