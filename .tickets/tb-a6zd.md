---
id: tb-a6zd
status: open
deps: []
links: []
created: 2026-11-09T06:50:32Z
type: bug
priority: 3
assignee: Alexis Purslane
parent: boo-b2ey
---
# Mark the hyphens of a long paragraph without laying out all of it again after each word joiner

Found in t1-qtde. LayoutRun._layOut lays out the whole paragraph again after each word joiner that _markHyphens adds. Darcy's letter in Standard Ebooks' Pride and Prejudice (section 36, item 19: 14,920 characters with 841 soft hyphens) lays out 20 times at 412 x 671 at 20 pixels and 32 times at 360 x 640 at 26 pixels. Its step takes 118 ms and 195 ms on the host (JIT, light load); Paragraph.layout takes 88 ms and 147 ms of that. A joiner changes only its own line and the lines after it, so a pass after a joiner can lay out the paragraph from that line's start, as the hanging first line does with _build(from:). Related: t0-z3m1 (hyphenation cost on the phone).

## Acceptance Criteria

- The step of Darcy's letter takes at most a small multiple of one layout of the paragraph at both corpus page settings.
- The hyphens and lines of every hyphenated paragraph stay the same: the trial's hyphenated saved places, the fidelity test and the corpus runs of the Standard Ebooks books.


## Notes

**2026-11-09T07:20:16Z**

Found in t1-um08: after tables lay out a row per unit, the slowest table units of Standard Ebooks' Plato, Dialogues are hyphenation passes. Section 30 at 360 x 640 at 26 pixels: one row unit (table item 1244) takes 199 ms with 158 paragraph layouts (135 ms in Paragraph.layout); paragraph items 180 and 185 take 98 and 114 ms with 17 and 18 layouts. Host, JIT, load about 10.
