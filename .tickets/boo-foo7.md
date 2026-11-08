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

