---
id: t9-nnon
status: in_progress
deps: [t9-mqtx]
links: []
created: 2026-11-09T21:59:37Z
type: feature
priority: 1
assignee: Alexis Purslane
parent: boo-m27l
---
# Record reading jumps in the reader session, with Undo


Design: docs/plans/reading-history.md, "Kinds of moves" and "What causes a reading move". Order of work 4. No user decision needed.

Build in `ReaderSession`:

- A pending move: before a jump verb asks the navigator, the session notes the kind and the shown place. The first place that the navigator reports after that request ends the move.
- The verbs and their kinds follow the table of the design. `followLink`, `restoreHistory(id, previous:)` and `undoMove()` are new verbs.
- The reader screen calls `followLink` for a link on the page and for Go to note.
- A move whose after equals its before records nothing. A failed navigation, or the open of another book, drops the pending move.
- The move saves with the new resume in one `ReadingChanges`.
- The recorded move becomes the Undo offer, with its own change signal, as `Playback.undoNotifier` does. A page turn keeps the offer. The next move, Undo, Dismiss, or another book ends it.
- If the place of `restoreHistory` or `restoreBookmark` belongs to another ebook edition of the same book, the session opens that edition first.
- `bookmarkHere`: the bookmark of the open edition whose place lies on the shown page, from its start to its end. Otherwise null.
- Add the reading history to `checkInvariants`: the Undo offer is a recorded move of the account, and a pending move belongs to the open book.

## Acceptance Criteria

- A drag of the scrub bar to another chapter records one "seek" move from the old page to the new page.
- A contents entry, a chapter arrow, a link, Go to note, a search result and a bookmark each record one move of their kind.
- A swipe or a tap that turns the page records no move. In a PDF, the arrows turn a page and record no move.
- A jump to the page that already shows records no move.
- A jump that fails records no move and keeps the saved place.
- Undo returns to the place where the last move began and records an "undo" move.
- Go back on a move returns to its before. Go to returns to its after. Each records a "historyRestore" move.
- A change of the text size records no move, and the Undo offer stays.
- `bookmarkHere` names the bookmark on the shown page, and none after a page turn away from it.
- A failed save keeps the recorded move pending in the session. The reader says that records are not saved, and the next save writes the move once. This test moved here from t9-mqtx, because t9-mqtx adds no verb that records a move. `ReaderSession._save` takes no moves yet: add a `history` argument that fills `ReadingChanges.history`.

## Notes

**2026-11-09T23:37:06Z**

Built in ReaderSession: the pending move (_Move), goTo, moveChapter, goToContents, followLink, openHit, restoreBookmark, restoreHistory and undoMove as moves; undoOffer with undoChanges; dismissUndo; bookmarkHere; _save takes history. Jumps in one book run one after another; the open of another book drops a waiting jump. The reader screen calls followLink for a link and for Go to note. The Undo row and the Bookmarked tool are t9-7fxw. Known limit: a page turn whose page shows after a jump began, and before the jump's page, ends that jump's move.
