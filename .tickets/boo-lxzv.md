---
id: boo-lxzv
status: open
deps: []
links: []
created: 2026-11-08T19:47:35Z
type: feature
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Show the book cover behind Android's media player

The user wants Android's built-in media player (the notification and the quick settings player) to have the same blurred audiobook cover background as the in-app player chip.

Today the session's MediaItem (lib/playback/native.dart, around line 241) has no artUri, so Android has no artwork and draws a plain player. Android 13 and later draw the session artwork as the player's background on their own, scaled and darkened with a gradient. The app cannot style that background directly.

Steps:
1. Give the MediaItem an artUri for the cover that the catalog already caches on disk (a file URI), so that it works offline and needs no Jellyfin auth header. Use the same cover that the player chip shows.
2. Make sure that the cover appears on the Pixel and that changing books changes it.

Design fork to bring to the user before step 3: the system background is the sharp cover, not a blur. To match the chip, the app can hand Android a pre-blurred copy. The cost: the same artwork also goes to the lock screen, Bluetooth car displays and watches, where a blurred cover looks broken. Option A uses the sharp cover everywhere. Option B uses a blurred copy (blur work off the UI isolate, cached beside the cover).

