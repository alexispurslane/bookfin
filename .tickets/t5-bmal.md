---
id: t5-bmal
status: open
deps: []
links: []
created: 2026-11-10T00:51:50Z
type: bug
priority: 3
assignee: Alexis Purslane
parent: boo-m27l
---
# Separate block texts in the saved quote of a reading place

Found in t9-9ffz (2026-11-09). The quote that a native EPUB place saves in its anchor joins the texts of adjacent blocks without a space. On the emulator, a bookmark at the start of First Frost's chapter two saved the quote "Two. The Ledger in the BarnHer grandmother kept a ledger…": the heading and the first paragraph run together. The History timeline shows this quote as the place of an entry outside the open book, and in the detail line of an open entry, so the person reads "BarnHer".

The quote also serves to match a saved place against the text (quoteMatches in lib/reader/epub/pager.dart), so a change of how it joins blocks must keep old saved places restorable. Owners of lib/reader/epub/ decide where the fix goes: in the saved quote, or only in ReaderSession.describe for display.

## Acceptance Criteria

- A place at the start of a section whose heading precedes a paragraph reads with a space between the heading and the paragraph in the History timeline.
- Places saved before the change still restore.

