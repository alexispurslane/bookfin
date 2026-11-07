---
id: boo-um68
status: in_progress
deps: []
links: []
created: 2026-11-07T20:55:42Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Narrow the app shell rebuild and cache the shelf

Audit P2, P3, P16: CatalogHome root ListenableBuilder listens to Playback (5 Hz) and Downloads, so every tick rebuilds the tab and regroups the library with a regex sort; book, series and search pages too. Listen narrowly; cache shelf() by catalog, filter and download revision; precompute natural sort keys.

