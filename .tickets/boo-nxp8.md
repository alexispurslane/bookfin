---
id: boo-nxp8
status: closed
deps: []
links: []
created: 2026-11-07T20:55:42Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Stop per-tick media session updates and background sync polling

Audit P6, P13: native.dart publishes MediaItem and PlaybackState on every Playback notification (about 10 platform calls per second). The 30 s record sync keeps running while the app is paused. Publish on real changes only; pause the sync timer with the app.


## Notes

**2026-11-08T02:52:42Z**

Closed on user acceptance, Nov 7: the user accepted the merged work and will report any issue they run into.
