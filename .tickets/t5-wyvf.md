---
id: t5-wyvf
status: closed
deps: [t9-nnon]
links: []
created: 2026-11-10T00:34:00Z
type: feature
priority: 2
assignee: Alexis Purslane
parent: boo-m27l
---
# Record a move and offer Undo when History opens the reader at a place

Found in t9-9ffz (2026-11-09). Go to or Go back on a reading entry of an edition that the reader does not show calls ReaderSession.openAt(place), which opens the edition at that place. It records no move and offers no Undo, so the place where this edition was before is not in the history. The design says that a choice that goes to a place offers Undo (docs/plans/reading-history.md, "The History timeline").

Build, after t9-nnon gives the session its pending move and Undo offer: when openAt opens an edition at a place other than its saved place, record one historyRestore move from the saved place to the opened place, and make it the Undo offer. The same applies to restoreBookmark for a bookmark of an edition that is not open.

## Acceptance Criteria

- Go to on a reading entry from the player opens the reader there, records one historyRestore move from the edition's saved place, and the reader offers Undo.
- Undo returns to the saved place.
- An open at the saved place itself records nothing.

