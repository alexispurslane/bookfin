---
id: boo-spjd
status: open
deps: []
links: []
created: 2026-11-08T12:48:01Z
type: bug
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
---
# Playback of a downloaded audiobook takes several seconds to start after Play

Reported by the user on the Pixel 8 (2026-11-08), in the release build from main 4a62653: after a tap on Play for a fully downloaded audiobook, several seconds pass before sound starts, long enough that the user thinks the tap failed. Measure first: the time from the tap to the first audio frame, split into the steps on the path (the playback controller, history and position reads, audio_service/media session start, the player's source setup for the edition's files, the seek to the saved position, and the first decode). Compare a single-file m4b with a many-file mp3 edition, and a cold first Play with a later one. Fix the slow steps. The Play button must also react at once, for example with a loading state, so that a slow start never looks like a failed tap.

