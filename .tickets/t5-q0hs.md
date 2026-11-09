---
id: t5-q0hs
status: open
deps: [t5-4l4d]
links: []
created: 2026-11-09T18:18:38Z
type: task
priority: 3
assignee: Alexis Purslane
parent: boo-b2ey
---
# Keep the first place and the visible characters of each true page in the page map

Found in boo-ystu (docs/research/epub-layout-cache.md). A jump or an open finds the page start of its place with LineSearch, which counts the lines of a long paragraph or measures every row of a table first: 2.5 s on the host for the middle of Roget's Thesaurus, 164 ms for Standard Ebooks' Ulysses. Keep each true page's first place (LaidPage.startPlace) and the visible characters before it in the page map (an estimated 5 to 7 bytes a page). Then a place finds its true page by a binary search, and the page source lays out that one page and makes sure that it holds the place; if the place is after the page's last shown place, the next page holds it. The visible characters also let the scrub bar (boo-ok9i) and time left (boo-02sx) work for sections that are not prepared.

## Acceptance Criteria

A corpus test shows that, for every true page start's first place and for places inside pages, the lookup gives the same page as lineStart and trueStart. A jump into the middle of Roget's Thesaurus' largest section with a page map does no line search.

