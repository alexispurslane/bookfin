---
id: t5-odvj
status: closed
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


## Notes (2026-11-09, implementation)

- At the merged head, the corpus run found this bug in other places than the ticket names: Gutenberg's Leaves of Grass (Kindle file), sections 30, 93 and 231, 4 places at each settings value. Section 30's case at 412 x 671 @ 20: line 385 of item 12 is the empty line of a hard break (offset 6083 of node 44), and line 386 starts with the indent of '  Births' (offset 6084). Both count as offset 6086 in document order. Both lines are in the paragraph's segment 5 (lines 322 to 386), and line 386 waits for its widows rule when the search decides.
- The fix: `LineSearch._search` gives `_holder` the lines that wait for their widows rule (`_Segments.waiting`) beside the lines that the run added. The tie then goes to the later line, as it does on laid-out pages.
- The other form of this tie, with the later line in the next segment, cannot happen: the search starts at the later segment when that segment's first place equals the place.
- The corpus run now fails on any lineStart disagreement.
- The full corpus run (2026-11-09) lists no lineStart disagreement at either settings value, and no lookup miss.
