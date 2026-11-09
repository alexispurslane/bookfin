---
id: t9-4vsl
status: open
deps: [t9-nnon]
links: []
created: 2026-11-09T21:59:37Z
type: feature
priority: 2
assignee: Alexis Purslane
parent: boo-m27l
---
# Record the opened place from another device, and reading visits


Design: docs/plans/reading-history.md, "The opened place from another device" and Open decision 2. Order of work 5. Wait for the user's answer to decision 2 before the visit entries. The part about another device's place does not wait.

Build:

- A store query that reads the retained actions of the journal. It gives the last place that this installation saved for an edition. It also gives the name of the device that saved the current place.
- At the open of a book in the reader, compare the opened place with this installation's last place. If they differ and another device saved the opened place, record an `open` move from this phone's place to the opened place. The move holds `device`, the other device's name, and becomes the Undo offer.
- Design 2B only: record "Opened" at every open of a book in the reader, and "Closed" at Back or at the open of another book. The background records nothing.

## Acceptance Criteria

- Phone A reads to page 200 and syncs. Phone B last showed page 120, syncs, and opens the book at page 200. B's timeline shows "Opened at the place from A" with Go back to page 120, and B offers Undo.
- A book that opens at this phone's own last place records no such move.
- A sync while the book is open does not move the shown page and records nothing.
- A kill right after the open keeps the `open` move or the old resume, never neither.
- Design 2B: an open and a Back record one "Opened" and one "Closed" entry with their places. A trip to the background and back records nothing.
