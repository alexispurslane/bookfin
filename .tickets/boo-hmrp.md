---
id: boo-hmrp
status: open
deps: [boo-f4xm]
links: [boo-0931, boo-s11s]
created: 2026-11-12T23:41:00Z
type: bug
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Upload pending records when playback pauses or the app hides

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: confirmed. lib/main.dart:333-341 calls `sync.suspend()` when the app hides, and `playback.flush()` writes only to local SQLite. No code calls `synchronize()` while the app is hidden (lib/sync/coordinator.dart:171-175). An hour listened with the phone locked stays on the phone until Bookfin opens again. A second device then plays from the old place, and the two devices produce a "Choose a saved place" conflict. Drive the upload from events: pending actions plus a pause, a stop, a book change or the app hiding, with a debounce. During background playback, use the 10-second cadence that lib/playback/reporting.dart:76 already has. Keep the boo-nxp8 decision of no polling while idle.

