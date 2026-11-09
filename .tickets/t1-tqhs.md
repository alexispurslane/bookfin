---
id: t1-tqhs
status: closed
deps: []
links: []
created: 2026-11-09T02:25:32Z
type: bug
priority: 3
assignee: Alexis Purslane
parent: boo-b2ey
---
# A run from a page start places lines up to 0.001 pixels off the main run

Found in tc-4f3q (corpus run). tc-nang's property is that a run from any page start cuts the same pages as the main run. In the libmobi conversion of Gutenberg's Wealth of Nations (pg-3300-wealth-of-nations-kf8, sections 14, 15, 30, 34, 36, 38 and 39), 19 runs from page starts at 412 x 671 at 20 pixels differ from the main run in page height, slice positions and piece positions, by at most 0.001 pixels (one step of pageKey's three decimals, for example a piece at 473.834 against 473.833). Page starts, places, visible-character ranges and line starts are the same, so every page holds the same text. The cause is likely the order of floating-point sums: a resumed run adds margins and line heights from the page top, the main run from the section start, and the converted book's CSS gives fractional em margins. A line that ends within such an error of the page bottom could be cut differently, so a resumed page could differ from the true page. The Gutenberg EPUB of the same book has no such difference.

Related: tc-n6wv (place lines at fractional positions) changes how lines are placed and can change this.

## Acceptance Criteria

- A run from every page start of pg-3300-wealth-of-nations-kf8 at both corpus page settings gives the same pageKey as the main run (BOOKFIN_EPUB_CORPUS=1 flutter test test/reader/epub/corpus_test.dart --plain-name pg-3300-wealth-of-nations-kf8), or the cut rule tolerates such rounding and a test shows a line at the page edge cut the same way by both runs.


## Notes

**2026-11-09T04:00:26Z**

Does not reproduce on the renderer after tc-n6wv (fractional line positions) merged: the corpus run of 2026-11-08 on that renderer finds all 1,845 runs of pg-3300-wealth-of-nations-kf8 at 412 x 671 at 20 pixels equal to the main run, and every run of every other book too, except the blank pages of t1-6ta8. The orchestrator can close this ticket as fixed by tc-n6wv.
