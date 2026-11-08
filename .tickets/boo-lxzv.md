---
id: boo-lxzv
status: in_progress
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


## Notes

**2026-11-08T19:51:25Z**

Decision (user, 2026-11-08): option B. Hand Android a blurred copy of the cover, made off the UI isolate and cached beside the cover. The user accepts that the lock screen, car displays and watches show the same blurred image.

**2026-11-08T20:12:48Z**

Built (option B). The cover cache (DiskCovers.blurred) owns the blurred copy: <item>@<tag>.blur.png beside the kept cover, made once per cover image in another isolate (image package), written to .partial then renamed. PlaybackHandler asks once per book through its art function, publishes the book at once without art, and adds artUri when the file arrives; a late file of a book that was left is dropped. The blur sigma is 22/390 of the width, as the chip's CoverGlass blur. The chip's page-color tint is not applied: Android draws its own dark scrim and light text from the art's colors, and a cream wash would lower that contrast and make every book's player beige. Checked on a disposable AVD (API 36) with a signed copy of the release APK and tool/showcase_fixture.dart: the system player turned navy for A Map of Quiet Rooms and olive after a change to A Field Guide to Small Weather. Follow-ups: t5-h6ep (books without a cover image), t5-vbno (unsigned release APK).
