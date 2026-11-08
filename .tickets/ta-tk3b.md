---
id: ta-tk3b
status: open
deps: []
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

