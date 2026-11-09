---
id: boo-0ari
status: closed
deps: []
links: []
created: 2026-11-09T18:00:04Z
type: bug
priority: 1
assignee: Alexis Purslane
parent: boo-b2ey
---
# Make the text size buttons resize a book's body text even when the book fixes its size

Reported by the user on 2026-11-09 with In the Dust of This Planet (Eugene Thacker, EPUB): the book sets a fixed font size on its body text, so the reader's text size buttons change only the chapter headings. Cause: the reader's size enters the cascade only as the body element's font-size (_bodyOverrides in lib/reader/epub/prepare.dart, copied from epub.js), so a book rule such as p { font-size: 12pt } wins over it.

The user's rule: if the user uses the text size buttons, the reader immediately switches to overriding the book's own body text size.

Decided model (orchestrator, from the user's words): before the user ever uses the size buttons, a book keeps its own design (and the epub.js fidelity tests stay valid). Once the user has used them, the reader's text size is the size of the book's main text in every book, and every other size in the book keeps its proportion to the main text, so headings, notes and small print scale with it and never end up smaller than the body text by accident. The main text size is the font size that covers the most characters; decide whether to measure it per section or per book, and test a section that is all small print (notes, index). Whether the user has used the buttons is stored with the text size, and it survives restarts. The size steps stay monotonic: each larger step gives larger body text.


## Implementation notes (2026-11-09)

- The reader session owns the choice as `sizesMainText`, stored as `sizesMainText: true` beside `fontSize` in the reading settings. The first `setFontSize` turns it on. A saved size other than the default 20 from before this change also counts as a used size button.
- `PageSettings.sizesMainText` carries the choice to layout, and it is part of the settings' equality and hash.
- Off: the cascade is unchanged (the reader's size is the body's font size, as epub.js sets it).
- On: the reader's body font size is left out, and the book's own design grows by `fontSize / mainTextSize` (`Cascade.fontScale`). Font sizes in absolute units, keywords and `initial` grow, and so do absolute line heights. Relative sizes and em lengths follow. Margins in absolute units stay.
- The main text size is measured per book, not per section: 48 of the 90 corpus books have a section of smaller print (Standard Ebooks colophons at 0.833 em, a 83,000-character section of the Iliad at 0.9 em, the Jungle Book's songs). The page source measures the three longest sections in a worker, once per page size. On all 90 corpus books, the three longest give the same size as the whole book.
- Corpus: 0 of 90 books fix their body text size. One book (Leaves of Grass, EPUB) has a main text size other than 16 pixels (0.9 em).
