---
id: tf-focn
status: in_progress
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

