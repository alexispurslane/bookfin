---
id: boo-gqcc
status: open
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

