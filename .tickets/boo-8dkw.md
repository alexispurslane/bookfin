---
id: boo-8dkw
status: open
deps: []
links: []
created: 2026-11-07T20:55:42Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Compute player and timeline derived lists once per change

Audit P7, P8, P9: recent, the history timeline and the position slider rescan the whole library per entry on every tick; editionTime runs before the edition guard for bookmark marks. Index edition id to file offsets at bind; cache by history revision; ListView.builder for the timeline; one CustomPainter for chapter and bookmark marks.

