---
id: t2-xkzt
status: open
deps: [t2-uyth]
links: []
created: 2026-11-11T22:44:17Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-vh77
---
# Keep the heard windows of each downloaded audio edition

A new data source owns the heard windows of each audio edition: their times and heard words, not ebook offsets. Derived data: local, rebuildable, never synced, never a personal record. One file per edition, keyed by its files and revisions, written atomically. It hears a window on request through the speech runtime, with one queue: a History tap first, then listening, then the fill. Contracts and checkInvariants.

