---
id: boo-sthf
status: open
deps: [boo-7o92]
links: []
created: 2026-11-01T21:37:34Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
---
# Deliver offline playback chapters and Jellyfin progress

Build the first complete download-to-listen path, native background playback, media controls, file/chapter mapping, speed, sleep timer, and durable resume.

## Design

docs/plans/bookfin.md

## Acceptance Criteria

Play a downloaded multi-file book offline. Resume after restart. Handle audio focus and lock-screen controls. Correctly report supported progress to Jellyfin without replaying old live-session events.

