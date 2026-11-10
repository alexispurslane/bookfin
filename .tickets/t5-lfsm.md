---
id: t5-lfsm
status: in_progress
deps: [t5-q0hs, tb-3xvr]
links: []
created: 2026-11-09T22:12:53Z
type: task
priority: 3
assignee: Alexis Purslane
parent: boo-b2ey
---
# Keep the line counts of long paragraphs' segments in the page map

Found in t5-q0hs. A page cut from a kept start inside a long paragraph counts the lines of every earlier segment of the paragraph first (LayoutRun._segment and the Expando LayoutRun._linesBefore), as the line search does. So with a page map, a jump into the middle of the largest section of Standard Ebooks' Ulysses still costs about 160 ms on the host, the same as the line search that t5-q0hs removed: the page from the kept start pays it instead. The counts live in an Expando on the paragraph item, so they go when the page source evicts the prepared section. Keep the number of lines before each segment of each long paragraph in the page map, as t5-s1vy keeps table cell widths. A paragraph without hard breaks is one segment; tb-3xvr changes how it is laid out, so this ticket follows it.

## Acceptance Criteria

A test shows that a run from a kept start inside a long paragraph cuts the same pages with kept line counts as with counted ones. A jump into the middle of Standard Ebooks' Ulysses' largest section with a page map lays out no segment before the page's own.


## Notes (2026-11-09, implementation)

- Format 4 of the page map also keeps, for each long paragraph of more than one segment, where each segment starts and the paragraph's lines before it (`SectionMeasures.paragraphs`, the `_Segmentation` of layout.dart). t5-s1vy and this ticket raise the format once, to 4.
- `reuseMeasures` gives them to a new prepared section as a complete segmentation, so a run from a kept start inside the paragraph starts at its own segment. It refuses segments that do not start at 0, do not increase, or start past the paragraph's end.
- The check on use: a run that lays out a segment that a kept map or another run found checks where the next segment starts and the lines before it. When they disagree, what the run found replaces that segment's end and the segments after it, and the page source forgets the map.
- The premise of this ticket was wrong for Ulysses. Its largest section (section 18, Circe) is a play laid out as tables, and t5-s1vy removed its cost. On the host, a jump with a map into the middle of the corpus's longest paragraphs (page_map_jump_test, load 8 to 27):

  | Book, section | Paragraph | Before | After |
  | --- | --- | --- | --- |
  | Gutenberg's Leaves of Grass, 27 | 72,049 code units | 8 ms, 36,964 units laid out | 3 ms, 1,030 units |
  | Gutenberg's Hong Lou Meng, 2 | 48,868 | 13 ms, 25,615 | 3 ms, 2,049 |
  | Gutenberg's Origin of Species, 17 | 29,423 | 13 ms, 15,416 | 3 ms, 1,030 |
  | Standard Ebooks' Ulysses, 22 (Penelope) | 21,938 | 6 ms, 26,541 | 3 ms, 4,486 |
