---
id: boo-xifx
status: closed
deps: []
links: []
created: 2026-11-07T20:55:42Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Save only changed records instead of the whole history every second

Audit P5: each whole-second position change builds JSON for all history and bookmarks, deep-copies, flattens and deep-compares it on the UI isolate. Make the Playback-to-store boundary incremental; position-only saves touch only the resume record. Keep every action (November 3 decision).


## Notes

**2026-11-08T02:52:43Z**

Closed on user acceptance, Nov 7: the user accepted the merged work and will report any issue they run into.
