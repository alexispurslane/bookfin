---
id: boo-nxp8
status: in_progress
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

