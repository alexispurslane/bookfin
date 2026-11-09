---
id: t9-mqtx
status: open
deps: [t9-of05, t9-mdsj]
links: []
created: 2026-11-09T21:59:37Z
type: feature
priority: 1
assignee: Alexis Purslane
parent: boo-m27l
---
# Store and sync reading history


Design: docs/plans/reading-history.md, "Storage and sync" and "Data safety". Order of work 3. No user decision needed.

Build:

- The record address `["reading", "history", id]`. Its value is the JSON of a `HistoryEvent<TextPosition>`.
- `ReadingChanges.history`, by id, with null for a deletion. `followedBy` and `applyTo` carry it.
- `ReadingRecords.saveReading`, `_flatten`, `_snapshot`, `_records` and `_validateActionValue` handle the new collection. The reading snapshot gets a `history` list.
- `ReaderSession` reads the reading history into memory at bind and at `refreshPersonalRecords`, and exposes it as a list with its own change signal. This ticket adds no recording. Ticket t9-nnon records moves.
- The sync choice labels (lib/sync/labels.dart) name such a record "Reading history entry".

## Acceptance Criteria

Each case is a test in domain language:

- A reading move saved with its resume in one change set survives a restart.
- A kill during that save leaves the old resume without the move, or the new resume with the move, never the new resume alone.
- A failed save keeps the move pending in the session. The reader shows that records are not saved, and the next save writes it once.
- A failed sync keeps the move pending in the journal. The next sync uploads it once.
- Two devices that record moves offline each show the moves of both after they sync, ordered by time.
- A deletion on one device removes the entry on the other after sync, and other entries stay.
- A damaged record file: salvage keeps every reading history entry that parses, and the recovery of kept copies brings back the rest.
- Audio records keep their JSON byte for byte through a save of reading history.
- A sync choice between two versions of a reading history entry names it "Reading history entry" with the quote of its place.
