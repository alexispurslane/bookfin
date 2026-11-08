---
id: ta-tk3b
status: closed
deps: [boo-du96]
links: []
created: 2026-11-08T00:13:00Z
type: task
priority: 3
assignee: Alexis Purslane
parent: boo-bquq
tags: [durability]
---
# Let the user recover records from a damaged record store that was set aside

Found by td-rvpm. A damaged record store is now kept aside: SQLite rows in the set_aside_* tables, a damaged record file as <name>.damaged-<milliseconds> (and its -wal copy), and a damaged preference value under bookfin.damaged-records.v1.<account>.<milliseconds>. The live store gets every record that still decodes, and sync refills what the server has. Records that were only on this phone and that did not decode, and actions that wait for such a lost action, stay only in the kept copy. Nothing reads the kept copies yet. A recovery path (export them, or merge what a later app version can read) is new work, and a user-visible design fork.


## Notes

**2026-11-08T00:26:10Z**

Orchestrator, Nov 7: held for the user. A recovery path for kept copies is a user-visible design fork.

**2026-11-08T01:39:18Z**

User decision, Nov 7: automatic merge, a quiet line, and discard after confirmation. At each launch, while kept copies exist (set_aside_* tables, <name>.damaged-<ms> files, kept preference values), the store tries again to read them with the current code and merges every readable record by time through the normal merge. Older data never replaces newer data. The Sync page's quiet line reports how many records came back, for example '3 damaged records were recovered.' While kept copies exist, the same line offers Discard, which deletes them only after a confirmation. No dialog other than that confirmation. No export. Recorded in docs/plans/bookfin.md, Conformance decisions.

**2026-11-08T02:02:01Z**

Implementation, Nov 7: LocalResumeStore.recoverKept reads the set_aside_* rows, every <name>.damaged-<ms> file (read-only, its -wal too) and the kept preference values in one hop, drops what the record file holds, and merges the rest per account through RecordJournal.receive in one write. Pending marks follow the kept copy; an unknown mark counts as pending. An identity that the live store holds adds nothing, even with other content (ta-tso8). A kept copy whose records all merged stays until Discard, because only an explicit user action deletes records. A kept place that this phone never saw becomes a saved-version choice beside the live place, as a second device's place does. RecordSync.recoverKept runs after the first frame and refreshes Playback and the reader when their records came back. The Sync page's quiet line says 'N damaged records were recovered.' and, while copies exist, 'Bookfin keeps a copy of the damaged records.' with Discard; the page confirms before LocalResumeStore.discardKept.
