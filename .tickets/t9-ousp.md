---
id: t9-ousp
status: closed
deps: []
links: []
created: 2026-11-08T21:21:32Z
type: bug
priority: 1
assignee: Alexis Purslane
parent: boo-b2ey
---
# Open a place in a white-space-only node on the line of its next visible character

Some text nodes hold only white space. For a place in such a node, lineStart (lib/reader/epub/layout.dart) picks the line before the next visible character. The cause is that it compares DOM order. ChapterLayout.pageAt compares the same way. A contents entry resolves to the first text node of its element at offset 0, as reader.js resolveDestination does. In many books, that node holds only white space.

Three cases in the downloaded trial books, found by test/reader/epub/saved_places_test.dart (tc-pshi, BOOKFIN_EPUB_TRIAL=1):

- se-poetry, contents entry `text/poetry.xhtml#sleep-and-poetry`, at 20 pixels. The place counts as visible character 46626. The anchored page shows only characters 46611 to 46625, the last line of the poem before. A person who opens "Sleep and Poetry" from the contents does not see it. The saved places test fails here.
- se-poetry, contents entry `text/poetry.xhtml#mrs-cameron-and-ben-nevis`, at 20 pixels. The place counts as character 272648, and the anchored page shows characters 272643 to 272647.
- pg-46 A Christmas Carol, contents entry `#pgepubid00002` ("IN PROSE"). The anchored page starts one line before the heading (characters 1290 to 1294), and the heading is on its second line. The page shows the target.

No saved place is lost: epub.js page starts and search hits never point into such a node in these books.

## Acceptance Criteria

- Take a place in a white-space-only node. Its anchored page and its true page each have a first line that holds the next visible character after the place.
- BOOKFIN_EPUB_TRIAL=1 flutter test test/reader/epub/saved_places_test.dart passes.
- The saved places test then asks contents entries to open on a page whose first line holds them, as it asks of page starts.
