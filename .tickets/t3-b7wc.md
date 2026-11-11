---
id: t3-b7wc
status: open
deps: []
links: []
created: 2026-11-11T20:33:29Z
type: bug
priority: 2
assignee: Alexis Purslane
parent: boo-z3is
---
# Refuse a chance pairing of three numbered anchors that passes the self-check

boo-bxap's leave-one-out self-check hides each inner anchor and places it from its two neighbors. With exactly three anchors, there is one inner anchor. A chance pairing by numbers, such as audio chapters 'Part 1', 'Part 2', 'Part 3' against contents entries 'Chapter 1' to 'Chapter 30', passes when its two spans read at about the same rate. Then design A lands far from the true place. Find such pairings in the user's library and in synthetic fixtures, and measure a check that catches them without refusing a right pairing: for example the rate of the whole book against the rate of the spans, or the share of the text that the spans cover. Measure first; see 'Measured on the user's library' in docs/plans/cross-edition-places.md.

