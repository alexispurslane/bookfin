---
id: boo-x1zf
status: in_progress
deps: []
links: [boo-23ji, td-1vfz, td-w0wc]
created: 2026-11-12T23:41:00Z
type: bug
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Stop a failed command from poisoning the playback command queue

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: mechanism confirmed, trigger for a non-Exception Error plausible. `_enqueue` (lib/playback/playback.dart:891-904) chains each command on `_operations` and handles only Exception and ArgumentError. (a) Any Exception from any command calls `_audioFailed`, so a store failure inside `refreshPersonalRecords` during a background sync pauses the audio and tells the user to download the file again. (b) Any other Error (TypeError, StateError, RangeError) leaves `_operations` as a failed future. Every later command, `flush()` and `close()` then fail at once until the app is killed. Never let a rejected future become the head of the queue. Classify failures for each command: an engine failure goes to `_audioFailed`, and a store failure goes to the save or refresh status. Make the status a closed set of conditions, not one text slot that code compares by string (playback.dart:906-920). The reader has the same queue shape in `_closing` (lib/reader/session.dart:663), so one shared serial queue helper serves both.


## Notes

**2026-11-13T01:43:34Z**

What changed. In lib/playback/playback.dart, _enqueue is now only the queue. It gives each command its own future through a Completer. That future completes as the command completed, and the queue head never fails, so a failed command never stops a later one. An Error that is not an Exception goes to the caller, or to the zone when nothing listens. Nothing turns it into a message. Each command states its kind of failure by how it is queued. An audio command uses the new _audioCommand, where an Exception is an engine failure and calls _audioFailed as before. A records command (addBookmark, editBookmark, deleteBookmark, deleteHistory, refreshPersonalRecords, setJumps, setSleep) uses _enqueue, where an Exception goes to the caller and the audio plays on. A failed save stays the save status of _persistChanges. For refreshPersonalRecords the caller is RecordSync, which already handles the same failure from the reader: a background sync ends as RecordSyncFailure.other, and the stale domain is refreshed at the next sync. In lib/sync/coordinator.dart, recoverKept now also reports nothing when a refresh fails. The _message slot did not change. lib/reader did not change. No shared queue helper was added.

Verification, through nix develop. New file test/playback/command_queue_test.dart, 9 tests. Before the fix 8 failed and 1 passed (the guard "an audio command whose engine call fails stops the audio and says that the file cannot play"). After the fix all 9 pass. With only a queue head that ignores every error, "a bug in a command that nothing awaits is reported once" still failed with an empty list, so the Completer is necessary. The guard test fails when seekEdition is queued as a records command. New group in test/sync/refresh_after_sync_test.dart, 4 tests. Against the old Playback 3 failed (the sync ended with no failure, and the audio stopped twice). With the Playback fix and the old recoverKept the 2 kept-copies tests failed with "Exception: read failed". After both fixes all 4 pass. flutter test test/playback test/sync: 654 passed, 2 skipped (both ask for a pinned shell tool), 0 failed. dart analyze on the 4 changed Dart files: no issues.

Behavior to know. A failed argument guard (ArgumentError) whose caller drops the future is now reported to the zone. Before, the queue head ignored it.

New tickets: td-1vfz (the _writes chain has the same poison defect for an Error from store.save) and td-w0wc (RecordSync names the wrong cause for some failed refreshes).
