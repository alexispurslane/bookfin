---
id: t5-q0hs
status: in_progress
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


## Notes (2026-11-09, boo-jglf and boo-ok9i)

- The whole-book page index (`BookPages` in lib/reader/book_pages.dart) gives a seeded section its page count only (`PartPages.visible` is null). So a second open shows whole-book page numbers at once, but inside a seeded section the scrub bar places text by its progress and names no page. Keep the visible starts and the section's visible length in the map, and seed `PartPages.visible` from them through `_finish` in page_source.dart. Then the bar is exact to the page in seeded sections too.
- `LaidPage.startVisible` can count text that the book hides (Standard Ebooks title pages). The page index makes the first start 0 and never lets a start go back. Keep the index's values, not raw `startVisible`.

## Notes (2026-11-09, implementation)

- Format 3 of the page map keeps each true page's first place (`LaidPage.startPlace`, or none) and its visible start as the page index counts it, and each section's visible length. A map file's name now begins with the format version, so a write removes the maps of format 2, and a read never finds them.
- `keptLineStart` in layout.dart is the lookup. A binary search over the first places finds the first page to look at. The pages that show the fragments of one split table row are looked at together, because a later cell of the row shows on the row's first page while its first cell goes on over the next pages (Standard Ebooks' Wealth of Nations, section 44). A place after everything that the rest of the section shows is on the last line that shows something (Gutenberg's Divine Comedy, section 2).
- Seeded sections now have `PartPages.visible`, so the scrub bar is exact to the page in them.
- The lookup does not make a jump into a long paragraph or a table faster. A page cut from a kept start there counts the lines of the paragraph's earlier segments or measures the whole table, which the line search did before, through the same cache. t5-s1vy (table widths) and t5-lfsm (segment line counts) keep those results in the map.
- The corpus run found no miss of the lookup in 1,874,244 places. In two places of Leaves of Grass, `lineStart` itself picks a line of only white space on the page before (t5-odvj); the lookup finds the page that shows the place.
