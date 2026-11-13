---
id: t5-6lnm
status: open
deps: []
links: [boo-x1zf]
created: 2026-11-13T02:08:04Z
type: bug
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Do nothing when a history entry or a bookmark is gone before its command runs

Found during the second change of boo-x1zf. Nothing was run for this finding. Status: mechanism confirmed by reading, trigger plausible. Since boo-x1zf, the command queue of Playback gives each command its own future, and a failure goes only there. A failed argument guard (ArgumentError) whose caller drops the future now reaches the zone as an uncaught error. Before boo-x1zf, the queue head ignored it. Three guards in lib/playback/playback.dart throw ArgumentError when an id is no longer in the records: restoreHistory (about line 508, 'Choose history from the current account.'), restoreBookmark (about line 647) and editBookmark (about line 569, both 'Choose a bookmark from the current account.'). A sync can remove the entry between the tap and the run of the command, because refreshPersonalRecords replaces the lists. The callers drop the future: lib/playback/timeline.dart:159 runs unawaited(restore()) for Go to on a history entry or a bookmark, and lib/playback/timeline.dart:300 runs unawaited(editAudioBookmark(...)), which reaches playback.editBookmark at lib/playback/records_screen.dart:94. The race at records_screen.dart:94 is wide, because the editor stays open while a background sync runs. Fix: a missing id after such a race is not a misuse by the caller, so the command does nothing and completes normally, as deleteBookmark and deleteHistory already do for an absent id. Keep ArgumentError for arguments that the caller controls, such as a speed outside 0.5 to 3. Look at the same guards of the reader (restoreBookmark and editBookmark in lib/reader/session.dart). Add tests, red first: a Go to on an entry that a refresh removed does nothing and reports no error, and a rename of a bookmark that a refresh removed while the editor was open does nothing and reports no error.

