---
id: t5-odvj
status: open
deps: []
links: []
created: 2026-11-10T00:26:30Z
type: bug
priority: 3
assignee: Alexis Purslane
parent: boo-b2ey
---
# Make the line search pick the line that shows a place after a line of only white space

Found in t5-q0hs by the corpus run, in Gutenberg's Leaves of Grass (Kindle file), section 188 at 360 x 640 @ 26. Page 44 ends with a line that shows only the six spaces of an indent in a pre text (offsets 7290 to 7295 of node 28), and page 45 begins with the line 'companions,' at offset 7296. A place in white space counts as its next visible character (_order in layout.dart), so both lines start at the same place in document order, and _holder gives the tie to the later line. But LineSearch._search has not added the later line yet, because it waits for the widows rule of its segment (_Segments.waiting). So lineStart gives the white-space line, and the page that does not show the word, for the places 7289 and 7296. ChapterLayout.pageAt and the page map lookup (keptLineStart) give page 45. The corpus check lists such places as lineStartDisagreements.

## Acceptance Criteria

lineStart gives the line that starts at 7296 for both places. The corpus run lists no lineStart disagreement.

