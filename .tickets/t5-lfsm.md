---
id: t5-lfsm
status: open
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

