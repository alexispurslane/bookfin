---
id: boo-39cu
status: open
deps: []
links: []
created: 2026-11-12T23:41:01Z
type: bug
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Stop or wait for Playback before a playing download is removed

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: plausible, the ExoPlayer reopen was not observed. lib/playback/playback.dart:1204-1210 takes file URIs from `downloads.localFile` without a lend, and `changeDownload` (lib/downloads/local_downloads.dart:690-699) waits only for work held through `readLocalFile`. A removal of the playing multi-file edition deletes the files under the player. The next file or a seek then fails with "Cannot play this local audio file". The position is saved. Playback uses the same lend as the reader, or the controller that confirms the removal stops that edition first. Related: t7-5m4d.


## Notes

**2026-11-13T22:12:19Z**

Parent asked the user on 2026-11-13 whether removing a playing audiobook should save its place, stop playback and remove files immediately, or keep playing and remove files when the user pauses or switches books. Both designs require confirmation, preserve personal records and stop removal on a failed save. The choice is pending; no implementation lead is running. The survey failure remains plausible until reproduced.
