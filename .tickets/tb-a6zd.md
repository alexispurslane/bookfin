---
id: tb-a6zd
status: in_progress
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

**2026-11-09T13:27:49Z**

Built: layout marks the line ends of a hyphenated paragraph a part of about 256 code units at a time, built from a line's start (_build start/end), then lays out the whole paragraph with the marks and again until no mark changes. Darcy's letter (Pride and Prejudice 36, 19) went from 105 to 17 ms at 20 px and from 187 to 14 ms at 26 px on the host; Plato's Dialogues 30, 184 from 125 to 28 ms and 126 to 39-49 ms; the step benchmark paragraph from 669 to 14-17 ms (4-6 ms without hyphens). A page dump of 47 corpus books at both settings changed 5 of 4,822 section layouts, all at 26 px, each where the old line broke the hyphen rule by an exact measure (float noise near the limit, or stale word joiners after a misjudged hyphen); docs/plans/native-epub-reader.md (Hyphenation) gives the cases.

**2026-11-09T14:15:45Z**

Fix after tb-2l69 measurements: a misjudged hyphen dropped the marks after it, and the whole-paragraph loop then decided the rest of the paragraph with one whole layout per word joiner. Darcy's letter at 20 px laid out 198,000 code units (13 times the paragraph). Now the loop goes back to parts from the line that breaks again: 62,000 code units (4 times). The page dump of 48 books is the same as before the fix.
