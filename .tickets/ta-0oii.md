---
id: ta-0oii
status: open
deps: []
links: []
created: 2026-11-09T12:48:12Z
type: feature
priority: 3
assignee: Alexis Purslane
parent: boo-b2ey
---
# Show a note that the book's style hides when its reference is tapped

Some EPUB 3 books hide their footnotes with CSS (for example aside[epub:type~=footnote] { display: none }), because reading systems such as Apple Books pop them up. The native renderer prepares no flow items for a hidden note, so PreparedSection.excerpt returns null, and a tap on its reference jumps to the hidden element as before tc-406m (EpubPager.note returns null). Prepare the note element for the sheet even when its computed display is none, for example by building the excerpt's boxes from the note element with display forced to block, and then show it in ReaderNotePanel. Test: a book whose style hides its aside footnote shows the note's text in the sheet.

