---
id: t9-9ffz
status: open
deps: [t9-mdsj, t9-mqtx]
links: []
created: 2026-11-09T21:59:37Z
type: feature
priority: 1
assignee: Alexis Purslane
parent: boo-m27l
---
# Share the History timeline between listening and reading


Design: docs/plans/reading-history.md, "A reading place in words" and "The History timeline", and Open decision 1. Order of work 6. Build the reading timeline first. Decision 1 decides whether it also merges the listening entries.

Build:

- `ReaderSession.describe(TextPosition)`: the short place, the chapter and the short quote, by the rules of the design. Page numbers come from `BookMap`, as the scrub bar's drag label does, at the time of drawing.
- `HistoryTimeline` takes a function that puts a place into words, instead of `editionTime`. The listening controller passes `audioTime` of the edition time, as today.
- Move labels for reading: the distance in pages, else the direction, else the verb alone.
- An open entry shows a detail line with the chapter and the short quote of the place where it ended. A listening entry shows its chapter there.
- `openHistory`, the controller of the sheet, routes each choice to the owner of its place: Playback for an audio place, the reader session for a text place. It confirms a delete as today. Its header shows the save status of the records that it lists.
- Design 1A: the sheet in the player, in the reader and on the book page lists both media, with a headphones or book glyph on the rail. Go to on an entry of the other medium opens that medium at the place. With nothing open, the Listening tab's History lists every book's listening and reading.
- Design 1B: the reader's sheet lists the reading entries of the book's ebook editions. The book page offers Listening history and Reading history.

## Acceptance Criteria

- A reading move in the open book reads, for example, "Went to a search result" with "p. 134", or with "37%" before every page is known.
- A PDF place reads "p. 12" in any edition. An EPUB place outside the open edition reads as the first words of its quote.
- The same reading move shows a later page number after a larger text size.
- A tap on an entry shows its chapter and quote, then Go back, Go to and Delete. Go to on a bookmark offers Name or Rename.
- Delete asks for confirmation. Cancel keeps the entry.
- The listening timeline looks and behaves as before (existing widget tests and screenshots).
- On the emulator through the T3 Device panel: open History over a book with reading moves and bookmarks, and record a screenshot for the user.
