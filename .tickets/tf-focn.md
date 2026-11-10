---
id: tf-focn
status: closed
deps: []
links: []
created: 2026-11-09T22:11:08Z
type: task
priority: 3
assignee: Alexis Purslane
parent: boo-b2ey
---
# Prepare a section faster: cached hyphenation breaks per word, a cheaper cascade, and an event parser for XHTML

Found in t7-49gt. A section's prepare (parse, cascade, boxes, flow items and hyphenation) is on the path of every first page and every jump. Keats' section 2 takes 328 ms on the emulator. On the host, parse is 20 to 25 percent of prepare, the cascade 30 to 35 percent and hyphenation 20 to 25 percent. Speed up each stage as a separate change, keep only those that pay, and make sure that prepared sections stay identical on the whole corpus.

## Acceptance Criteria

Prepared sections (flow items, styled runs, hyphenation points and the DOM) are identical before and after on every corpus book. Prepare time drops for Keats' section 2, Roget's section 1, Plato's Dialogues 30 and Van Dyke's section 2 and for the corpus median, in same-load paired host runs, and for Keats' section 2 on an emulator.


## Notes

**2026-11-10T01:34:36Z**

Kept: cheaper selector matching with each declaration's longhands kept (089a0b4), and computed styles shared among elements that the cascade styles the same (f3d07be). Dropped: the hyphenation bookkeeping rewrite and the per-word break cache (no gain beyond noise in four paired corpus rounds), and the XHTML event parser (about 5 percent of Keats' prepare). Every change prepared identical sections on the whole corpus. Host, three paired rounds: Keats 2 321 to 195 ms, Roget's 1 505 to 345, Dialogues 30 296 to 249, Van Dyke 2 217 to 151, corpus total 15.3 to 12.0 s, median book ratio 0.79. Emulator: open of Keats' section 2 26 to 35 percent less time. docs/research/epub-first-page-timing.md, 'After tf-focn', has the numbers.
