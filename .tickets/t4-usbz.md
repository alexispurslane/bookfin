---
id: t4-usbz
status: open
deps: []
links: []
created: 2026-11-08T14:11:18Z
type: bug
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Keep the player's position thumb out of Android's edge gesture zone

Found during boo-315o on emulator-5554: Android's back gesture zone is 78 px (30 points) at each edge. The reader's scrub bar now keeps the system gesture insets clear (lib/reader/screen.dart ReaderScrubBar). The player's PositionSlider sits 24 points inside its pane, so its thumb at the start or end of an edition is about 32 points from the screen edge, half inside the zone with its 8-point radius. Check on the emulator whether a drag from the thumb at 0 opens Back, and if so pad the player bar by MediaQuery.systemGestureInsets like the reader does. lib/playback is shared with boo-spjd.

