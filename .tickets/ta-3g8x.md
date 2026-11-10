---
id: ta-3g8x
status: open
deps: []
links: []
created: 2026-11-10T17:20:32Z
type: task
priority: 3
assignee: Alexis Purslane
parent: boo-fval
---
# Decide whether a grown PDF crop keeps a white edge around its content

cropOf in lib/reader/book_crop.dart grows a page's crop to the union of its side's box and its content box. The side box has a padding of half a body line height, but the content outside it gets none. So the wide table of margins-book.pdf page 10 touches the screen's left and right edges in the Original view (docs/evidence/reader/trimmed-margins/after-page-10.png). Decide with the user whether a grown crop pads the content that grows it. Body text on page 3 also has only a thin edge; tb-fb6j tunes on the Pixel 8.

