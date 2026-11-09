---
id: tb-3xvr
status: open
deps: []
links: []
created: 2026-11-09T14:49:11Z
type: task
priority: 3
assignee: Alexis Purslane
parent: boo-b2ey
---
# Lay out a long paragraph without hard breaks in steps

Found in tb-i6wg. The index of Roget's Thesaurus (Gutenberg) is one justified paragraph per section, with no hard break and no soft hyphen. Section 76 item 12 has 54,475 characters in 6,000 style runs, and section 115 item 12 has 38,255 characters in 4,386 runs. One unit of work lays out the whole paragraph: 94 and 62 ms on the host (JIT, warm, 412 x 671 at 20 px). The corpus run lists 90 such paragraphs at 20 px (up to 71 ms) and 89 at 26 px (up to 76 ms). Before t1-qtde they took up to 713 and 1,098 ms. tb-2l69 segments need hard breaks, so they do not apply. A line's break depends only on where the line starts, so the paragraph can be laid out in parts built from a line start, as tb-a6zd does for hyphens. But a part measures with less float error than the whole paragraph, so a line near the width limit can break in another place (tb-a6zd found 5 such sections). First measure how much of the unit is Paragraph.layout and how much is building the 6,000 style runs.

## Acceptance Criteria

- No layout unit of Roget's index sections takes much more than the budget plus one ordinary paragraph, at both corpus page settings, by the corpus slow-item list.
- A page dump of the corpus is the same as before, or each changed line is proved wrong before.
- Runs from every page start cut the same pages, and saved places still resolve.

