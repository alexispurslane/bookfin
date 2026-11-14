---
id: t0-dv5n
status: open
deps: [boo-39cu]
links: []
created: 2026-11-13T23:20:24Z
type: task
priority: 3
assignee: Alexis Purslane
parent: boo-fs0n
tags: [engine, follow-up]
---
# Keep independent verified-file lookups concurrent when lending an audio edition

Recorded during boo-39cu. Playback now uses the same verified-file holds as the reader. Its Future.wait starts all source reads, but LocalDownloads.readLocalFile orders each full lookup through the existing global Downloads command queue. This keeps removal safe but serializes independent asynchronous storage checks for a multi-file edition. Follow the engine rule for concurrent independent IO without weakening hold/removal/account ownership; measure representative multi-file open time before choosing a batch or narrower queue change. No runtime timing claim has been established.

## Acceptance Criteria

Show that independent source verification overlaps while removal and account replacement remain guarded; retain the boo-39cu save-before-removal tests and the reader hold tests.

## Notes

**2026-11-14T00:38:07Z**

Parent integration inspection found an additional static invariant concern for this read/removal lifetime work: checkInvariants currently rejects any _reading key that belongs to pending removal, even though removal may legitimately wait for a read callback admitted before removal began. Include a controlled existing-read/removal case and distinguish pre-existing reads from forbidden later admission when narrowing the queue. No runtime reproduction or normal user-flow failure is claimed here; general invariant hardening remains parent-owned after acceptance.
