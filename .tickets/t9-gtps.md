---
id: t9-gtps
status: closed
deps: [t9-4vsl]
links: []
created: 2026-11-09T21:59:37Z
type: feature
priority: 2
assignee: Alexis Purslane
parent: boo-m27l
---
# Record a listening move for a book that opens at another device place


Design: docs/plans/reading-history.md, "The opened place from another device". Order of work 8. Found during the design of boo-m27l on 2026-11-09: a book opens at another device's listening place, and no listening move records it.

Build: apply the rule of t9-4vsl to Playback. At the open of an audio edition, compare the opened place with this installation's last place. If they differ and another device saved the opened place, record an `open` listening move with the device's name, and offer Undo. Use the store query from t9-4vsl.

## Acceptance Criteria

- Phone A listens to 1:10:00 and syncs. Phone B last played 0:40:00, syncs, and opens the book at 1:10:00. B's timeline shows "Opened at the place from A" with Go back to 0:40:00, and B offers Undo.
- A book that opens at this phone's own last place records no such move.
- The recently listened list does not change its order because of the `open` move alone.
