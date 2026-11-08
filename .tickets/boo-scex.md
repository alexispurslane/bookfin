---
id: boo-scex
status: closed
deps: []
links: []
created: 2026-11-08T19:42:53Z
type: bug
priority: 0
assignee: Alexis Purslane
parent: boo-fs0n
---
# Keep the media notification icons in release builds

Release resource shrinking removed audio_service's drawable/audio_service_* icons. Every playback state update then threw 'You must specify an icon resource id to build a CustomAction', so Android showed no media notification, started no foreground service, and froze the app in the background, which stopped playback. Fix: res/raw/keep.xml keeps @drawable/audio_service_*.


## Notes

**2026-11-08T19:44:32Z**

Verified: a release build now contains drawable/audio_service_fast_forward, fast_rewind, pause, play_arrow, skip_next, skip_previous and stop (aapt2 dump resources). Follow-up: the .#apk flake package (boo-77sj) can fail its build when these icons are missing.

**2026-11-08T19:47:35Z**

The user confirmed on the Pixel (2026-11-08) that playback continues in the background and the media notification appears.
