---
id: boo-jxf9
status: open
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
