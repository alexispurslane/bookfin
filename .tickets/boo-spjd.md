---
id: boo-spjd
status: closed
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


## Notes

**2026-11-08T14:04:00Z**

Measured in profile builds on the AVD bookfin-accept-20261103-db111f95 with an on-device harness (real LocalDownloads, LocalAudioEngine, audio_service), a 301 MB m4b and a 40-file mp3 edition (294 MB) made with ffmpeg. Before: tap to first sound 3.1 to 4.5 s, of which 3.0 to 3.8 s was a SHA-256 of every file on every Play and Listen (LocalDownloads._verified), run one file after another. LocalDownloads.bind also hashed every saved file at each launch (6.5 to 7.1 s for these two editions), and a Play after launch waits for it. After: a saved file is hashed again only when its size or modification time differs from the fingerprint kept from its last match (persisted in record.json as 'verified'); Playback looks up an edition's files together. Tap to first sound 0.23 to 0.75 s; bind at the next launch 0.21 s. Every Play control shows a progress ring from the tap until the sound (Playback.startingNotifier, PlayStateIcon). Not done: the first ExoPlayer prepare in a process still takes 0.3 to 0.56 s; the launch restore already pays it before the mini player's Play.
