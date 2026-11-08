---
id: boo-foo7
status: closed
deps: [boo-315o]
links: []
created: 2026-11-08T12:48:01Z
type: feature
priority: 3
assignee: Alexis Purslane
parent: boo-fs0n
---
# Show pages as a deck of cards while the reader scrubs

User request (2026-11-08): while the user scrubs back and forth in a book, the page zooms out into a card, and the previous and next pages show as slightly smaller, dimmed cards that overlap it, like shuffling a deck of cards. Design is open: see the two designs discussed in chat on 2026-11-08 and the user's answers. Constraints from the code: EPUB and MOBI render one page at a time in an epub.js WebView with no offscreen rendering; PDF pages can be rendered offscreen with PdfBook.render, and page images are not cached.


## Notes

**2026-11-08T12:51:22Z**

Design decided by the user on 2026-11-08: design A, live pages. Every card shows a real rendered image of its page, both while the finger moves and when it rests. EPUB and MOBI render target pages in a second, hidden epub.js rendition; PDF uses PdfBook.render. Rejected: index cards (chapter title, page number and first lines as text). Consequences to design for: a render takes about 0.1-0.3 s, so during a fast drag the deck must never show blank cards (keep the nearest finished render, blurred or dimmed, until the target's image arrives), drop renders for places the finger already left, and cache recent page images within one drag. Shared by both designs: on drag start the page zooms out into a card, the previous and next pages show as smaller dimmed overlapping cards, release zooms back into the target page, and it works the same in EPUB, MOBI and PDF. Depends on boo-315o, the whole-book scrub bar.

**2026-11-08T15:20:59Z**

Built design A. EPUB and MOBI pages come from a second, hidden epub.js rendition in the same WebView: its page document, with style, fonts and images inlined, becomes an SVG image drawn to a canvas and sent as a JPEG. PDF pages come from PdfBook.render. PagePreviews, owned by ReaderSession, owns the page images; ScrubDeck shows them. The shown frames now lay out in standards mode, as XHTML does (they were in quirks mode), so a preview matches its page. Measured cost per page on emulator-5554: EPUB 0.6 to 0.8 s in a section, 1.4 to 1.7 s across sections; PDF 27 to 93 ms. Follow-ups: t6-rt20 (EPUB cost), t6-6gej (frame rate on hardware graphics).

**2026-11-08T15:27:24Z**

Device check on emulator-5554 (debug build of the final code): the deck opens, shows real pages day and night in First Frost, and lands on the target. Screenshot: docs/screenshots/reader-deck.png. The Windfall (PDF) deck ran on an earlier profile build of the same design (pages drawn in 27 to 93 ms); its final-build screenshots were not taken, because another session took over the emulator.
