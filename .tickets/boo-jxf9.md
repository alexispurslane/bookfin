---
id: boo-jxf9
status: closed
deps: []
links: []
created: 2026-11-14T15:51:55Z
type: bug
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
---
# Resume from the Listening tab after an app restart starts the audiobook at 0:00 instead of its saved place


## Notes

**2026-11-14T15:51:55Z**

Seen 2026-11-14 on a private emulator (bookfin-shots-20261114) with release build of a32ce302 and tool/showcase_fixture.dart --sync-conflict on port 8196. First Frost was paused at 2:43:43 in chapter 4 (History: 10:47 Paused 2:43:43). A listening sync choice was waiting (1 choice waits). The app was relaunched; the Listening tab's 'Resume First Frost' then played from 0:00 (History: 10:47 Played 0:00, Paused 0:09), and the next sync uploaded 0:09 as this phone's place. History kept 2:43:43, and Go to restored it. Earlier in the same session, the fixture server was restarted, so the server's own progress for the book may have been reset; check whether Resume prefers a server progress of 0 over the newer local place, which breaks the engine rule 'never let older data overwrite newer data'. Needs a test that reproduces it.

**2026-11-14T16:04:47Z**

Cause: RecordJournal.value gives no current value for a resume with competing versions, so the snapshot that Playback and ReaderSession restore lacks that edition's resume, and an open with no resume started at 0. Fix: Playback._open and ReaderSession.open fall back to PlaceOrigin.own, this installation's last own place from the journal, when no restored resume exists; the sync choice stays open. Tests: test/playback/restart_resume_test.dart (4 behaviors x preferences and SQLite) and a two-phone reader test in test/reader/reading_moves_test.dart. Each failed with position 0 / section 0 before the fix. flutter analyze clean; test/playback, test/sync, test/reader: 2805 passed, 24 skipped. Not rechecked on a device.
