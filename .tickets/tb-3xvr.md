---
id: tb-3xvr
status: in_progress
deps: [t7-bbv1]
links: []
created: 2026-11-09T14:49:11Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-b2ey
---
# Lay out a long paragraph without hard breaks in steps

Found in tb-i6wg. The index of Roget's Thesaurus (Gutenberg) is one justified paragraph per section, with no hard break and no soft hyphen. Section 76 item 12 has 54,475 characters in 6,000 style runs, and section 115 item 12 has 38,255 characters in 4,386 runs. One unit of work lays out the whole paragraph: 94 and 62 ms on the host (JIT, warm, 412 x 671 at 20 px). The corpus run lists 90 such paragraphs at 20 px (up to 71 ms) and 89 at 26 px (up to 76 ms). Before t1-qtde they took up to 713 and 1,098 ms. tb-2l69 segments need hard breaks, so they do not apply. A line's break depends only on where the line starts, so the paragraph can be laid out in parts built from a line start, as tb-a6zd does for hyphens. But a part measures with less float error than the whole paragraph, so a line near the width limit can break in another place (tb-a6zd found 5 such sections). First measure how much of the unit is Paragraph.layout and how much is building the 6,000 style runs.

## Acceptance Criteria

- No layout unit of Roget's index sections takes much more than the budget plus one ordinary paragraph, at both corpus page settings, by the corpus slow-item list.
- A page dump of the corpus is the same as before, or each changed line is proved wrong before.
- Runs from every page start cut the same pages, and saved places still resolve.


## Order (user, 2026-11-09)

This ticket comes right after t7-bbv1. Whole-book layout in the background visits every paragraph of the book, so one long layout step can drop a frame during a page turn.

## Results (2026-11-09)

- Build against layout, Roget's Thesaurus 76, 12 at its fastest: build 20 ms and layout 8.5 ms at 20 px, build 18 ms and layout 48 ms at 26 px.
- Every long paragraph now lays out in segments that end at a cut: after a hard break, before a word that follows a space (not after an opening bracket or quote), or between two ideographs. Runs keep each segment's start and the lines before it, per paragraph item.
- Roget's index (76, 12) took 43 to 56 ms warm and up to 119 ms cold in one unit. Its segments take 3 to 6 ms warm. The corpus's longest step fell from 39.5 ms to 19.6 ms, and steps over 10 ms from 23 book and settings pairs to 3. The 19.6 ms step is a table row measure of Plato's Dialogues, the same before (t2-wcab).
- Runs from every page start cut the same pages, and saved places resolve (corpus test and trial tests).
- Page dump. 36 section layouts changed a line at the very limit of its width, 22 of them in Hong Lou Meng. A segment measures with less float error than the whole paragraph. The longer of the two lines passes the width by at most 0.0098 px, and the new line is sometimes the longer one, so these are not proved wrong before. This needs the user's decision.
