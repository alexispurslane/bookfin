---
id: td-1vfz
status: open
deps: []
links: [boo-x1zf]
created: 2026-11-13T01:42:34Z
type: bug
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Stop a failed save from poisoning the write chain of Playback

Found during boo-x1zf. Nothing was run for this finding. Status: mechanism confirmed by reading, trigger plausible. `_save` and `flush` in lib/playback/playback.dart chain each save on `_writes` with `_writes = _writes.then((_) => _persistChanges(accountKey, value))`. `_persistChanges` catches only Exception. An Error that is not an Exception from `store.save` (a TypeError, a StateError, a failed assert) leaves `_writes` as a failed future. Every later save then skips its write, and every command that awaits `_writes` (pause, stop, seek, a bookmark change, `refreshPersonalRecords`) and `flush()` fail with the same Error until the app is killed. The place and the history are no longer saved, which engine rule 3 counts as data loss. This is the bug class that boo-x1zf fixed for the command queue `_operations`: a rejected future as the head of a serial chain. boo-x1zf did not change `_writes`. Keep the Error visible to the caller of that save, and never let the head of the chain be a rejected future. The reader has a chain of the same shape at lib/reader/session.dart:1801, so look at it too. boo-n7no (one record writer for Playback and the reader) can absorb this.


## Notes

**2026-11-13T02:08:53Z**

Fixed by the second change of boo-x1zf. The orchestrator closes this ticket. What changed. The new lib/foundation/serial_queue.dart holds SerialQueue, a queue that runs work one piece at a time. Each run has its own future, which carries the value or the failure of that work. The queue itself never fails, so a failed run never stops a later one. The write chain _writes and the command queue _operations of Playback are now each a SerialQueue. A save that fails with an Error that is not an Exception no longer stops the next save. The Error goes to the zone once for a save that _save queued, and to the caller of flush for the save that flush queued. The changes of the failed save stay in _pendingWrites, so the next save and flush send them again. The order of the saves, _persistChanges and its identity check did not change. Tests: test/foundation/serial_queue_test.dart (9 tests) and test/playback/save_queue_test.dart (5 tests). All 5 save tests failed against the old chain and pass now. lib/reader was not changed: boo-23ji and boo-n7no adopt the helper there.
