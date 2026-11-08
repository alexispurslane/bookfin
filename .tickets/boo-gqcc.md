---
id: boo-gqcc
status: closed
deps: []
links: []
created: 2026-11-07T20:55:42Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Throttle download progress notifications

Audit P1: local_downloads.dart notifies and calls freeBytes after every HTTP chunk; the leftover inventory rescans per chunk. Emit at most every 250 ms or 1%, check free space every N MB, reload leftovers only on phase change.


## Notes

**2026-11-08T02:52:42Z**

Closed on user acceptance, Nov 7: the user accepted the merged work and will report any issue they run into.
