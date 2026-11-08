---
id: boo-8dkw
status: closed
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


## Notes

**2026-11-08T02:52:42Z**

Closed on user acceptance, Nov 7: the user accepted the merged work and will report any issue they run into.
