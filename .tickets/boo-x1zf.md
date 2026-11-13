---
id: boo-x1zf
status: open
deps: []
links: [boo-23ji]
created: 2026-11-12T23:41:00Z
type: bug
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Stop a failed command from poisoning the playback command queue

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: mechanism confirmed, trigger for a non-Exception Error plausible. `_enqueue` (lib/playback/playback.dart:891-904) chains each command on `_operations` and handles only Exception and ArgumentError. (a) Any Exception from any command calls `_audioFailed`, so a store failure inside `refreshPersonalRecords` during a background sync pauses the audio and tells the user to download the file again. (b) Any other Error (TypeError, StateError, RangeError) leaves `_operations` as a failed future. Every later command, `flush()` and `close()` then fail at once until the app is killed. Never let a rejected future become the head of the queue. Classify failures for each command: an engine failure goes to `_audioFailed`, and a store failure goes to the save or refresh status. Make the status a closed set of conditions, not one text slot that code compares by string (playback.dart:906-920). The reader has the same queue shape in `_closing` (lib/reader/session.dart:663), so one shared serial queue helper serves both.

