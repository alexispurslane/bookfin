---
id: t9-4hcf
status: open
deps: [t9-k6kd]
links: []
created: 2026-11-11T15:44:45Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-z3is
---
# Go to a landing as a mapped move in the open edition's own track, with Undo

Step 6 of design A in docs/plans/cross-edition-places.md. HistoryEvent gets optional counterpartOf and matchedBy (no migration, JSON unchanged for other moves). ReaderSession.goToLanding and Playback.goToLanding go to a landing as a move of the choice's kind. Data-safety tests: a refused landing changes no record; a mapped jump writes no record of the other medium; Undo returns to the exact place before the jump; a kill during the save keeps the old place or the new place with its move.

