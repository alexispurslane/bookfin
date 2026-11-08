---
id: boo-foo7
status: open
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
