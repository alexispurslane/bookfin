---
id: t9-m4fw
status: closed
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


## Notes

**2026-11-11T19:36:02Z**

Built on branch t3/30cd0bb4. A TextLanding now carries its share of the ebook's visible characters and its chapter, from the text outline that placed it. ReaderSession.describeLanding names a landing by them until the reader measures the open book ('about 23%' with the chapter), then by the map ('about p. N'). Where the map names no chapter (a PDF), the chapter still comes from the outline. describeLanding returns null while no book is open, as goToLanding then moves nothing. Tests: test/reader/landing_words_test.dart (the tile before and after the map, through the History sheet and a PDF reader), test/crossings/crossings_test.dart (share and chapter of a landing).

**2026-11-11T20:38:59Z**

Review fix (C1, D1, D2). describeLanding now names a landing exactly when goToLanding can show it: the reader shows the book (a navigator is attached) and the landing is in the open edition at its revision. Before the reader shows a PDF, the tile keeps the place's own words. Until the book map knows its pages (an EPUB before layout), the tile names the landing by the outline's share and the chapter, not by the map's byte estimate. Tests: test/reader/landing_words_test.dart now uses an EPUB on the session's own pager for the share state, and the PDF test starts with the reader hidden for the own-words state.
