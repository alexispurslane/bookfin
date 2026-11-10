---
id: t9-7fxw
status: in_progress
deps: [t9-nnon, t9-9ffz, t7-49bp]
links: []
created: 2026-11-09T21:59:37Z
type: feature
priority: 1
assignee: Alexis Purslane
parent: boo-m27l
---
# Put History, Bookmarked and Undo in the reader dock


Design: docs/plans/reading-history.md, "The interface", and Open decision 3. Order of work 7. t7-49bp removes the plain bookmark editor first.

Build in the reader screen and its dock:

- The History entry point by decision 3. Design 3A: a History tool after Bookmark, before the cover button, and a contents sheet without tabs. Design 3B: the contents sheet's tabs become Contents and History. In both, today's Bookmarks tab goes away.
- The Bookmark tool follows `bookmarkHere`. Without a bookmark on the shown page, it reads "Bookmark this place" and a tap saves an untitled bookmark at once. With one, its icon fills, its tooltip reads Bookmarked, and a tap opens the shared editor for that bookmark.
- The Undo row: the player's `UndoNotice`, above the place label inside the dock, while the session has an Undo offer. Full screen hides it with the dock.
- The shared bookmark editor for reading bookmarks: the headings "Add bookmark" and "Edit bookmark", and the place line from `describe`, such as "On p. 134 · Chapter 4".
- Leaf widgets report events only. The reader screen is the controller (UI rule 1). Every new popover uses the glass components (UI rule 4).

## Acceptance Criteria

- A tap on Bookmark adds one untitled bookmark and the tool reads Bookmarked. A second tap opens the editor for that bookmark. After a page turn, the tool reads "Bookmark this place" again.
- A jump shows the Undo row. Undo returns to the page where the jump began. Dismiss hides the row.
- A link followed in full screen keeps the offer, and the row shows with the controls.
- The Undo row coming or going does not move or lay out the page.
- Every tool keeps a 48-point touch target (androidTapTargetGuideline).
- The bookmark marks on the scrub bar still show each bookmark of the open edition.
- On the emulator through the T3 Device panel: add a bookmark, name it, jump by search, Undo, and open History. Record screenshots for the user.
