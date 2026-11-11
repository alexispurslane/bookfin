---
id: t9-m4fw
status: open
deps: [t9-4v0r]
links: []
created: 2026-11-11T17:47:01Z
type: task
priority: 3
assignee: Alexis Purslane
parent: boo-z3is
---
# Name a listening place's landing in the reader before the book map is measured

Found in the boo-z3is review (B6). In the reader's History, a tile of a listening place names its landing through ReaderSession.describeLanding, which needs the open book's map. Until the map is measured, the tile shows the place's own words ("1:02:15") and no note, but Go to already moves the reader to the landing. The window is short after a book opens. Name the landing without the map, for example by its share of the book from the text outline, or say that Go to stays in this ebook.

