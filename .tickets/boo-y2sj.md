---
id: boo-y2sj
status: closed
deps: []
links: []
created: 2026-11-12T23:41:00Z
type: bug
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Queue reading changes while the reading records are not ready

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: confirmed. lib/reader/session.dart:622-624 and 1697-1698. When `store.read` fails inside `bind`, `_recordsReady` stays false. `_save` then returns without a queue entry, and no code retries the read, so every page turn, bookmark and history move is dropped until the app restarts. The message tells the user to restart. Queue the changes in `_pendingWrites`, which already merges and retries, and retry the read on `flush`, `resume` or the next `bind`. The record-level merge of the store keeps the guarantee that unread records are not overwritten. Add a test for a failed read followed by a page turn.


## Notes

**2026-11-13T01:32:25Z**

Fixed. While the records of an account are unread (the first read still runs, or it failed), ReaderSession keeps record changes in `_unreadChanges` and reads the records again at the next change, at `flush`, at `resume` and at the next `bind`. `_readRecords` applies the waiting changes on top of the read records and saves them. It never saves before the read, because a save carries the whole settings and would replace the saved text size with the default. Verification: test/reader/unread_records_test.dart, 4 of 5 tests failed before the change for the missing behavior and all 5 pass after it. 313 reader record and sync tests pass. Limit: records that fail validation at every read still keep new places in memory only, as before. `_binding` has the same queue shape as boo-x1zf: an Error that is not an Exception leaves it failed.
