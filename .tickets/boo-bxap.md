---
id: boo-bxap
status: in_progress
deps: []
links: []
created: 2026-11-11T19:40:28Z
type: bug
priority: 1
assignee: Alexis Purslane
parent: boo-z3is
---
# Refuse chapter alignments whose anchors fail a leave-one-out check

t3-a4fi measured the user's library: 5 of 8 design A matches had wrong anchors (track numbers pairing with chapter numbers by chance, an anthology), so landings went to the wrong chapter. The rate band cannot catch them. Add a leave-one-out self-check: hide each anchor, place it from its neighbors, and refuse the pairing when the median error exceeds 2 pages (right pairings 0.14 to 1.25 pages, wrong 3.2 to 221). Lower the coverage limit from 0.5 to 0.3. Pairings with exactly two anchors cannot be checked: decide and document. Evidence: docs/plans/cross-edition-places.md, 'Measured on the user's library'.


## Notes

**2026-11-11T19:51:18Z**

Built on branch t3/30cd0bb4. alignEditions now (1) refuses as Refusal.misaligned when the median leave-one-out error of the inner anchors exceeds 2 pages (1164 visible characters), placing each hidden anchor from its two neighbors by the span placement rule, checked after the coverage limit; (2) lowers the coverage limit to 0.3. Two-anchor decision: kept only when both pairs agree by title words (word score 2), else fewMatches; every wrong match measured on the library paired by numbers, so 'titled' alone is no evidence, and no two-anchor pairing occurred. History note: 'The chapters of these editions do not line up, so this opens the ...'. Tests: alignment_test.dart (seven public recordings still match; off-by-one tracks with credits in track 01 and a story against a three-work anthology refuse; two word-titled anchors kept; two number-only anchors refused; a third of the recording covered matches; a quarter refuses), crossing_history_test.dart (the note words). MatchedChapters.checkInvariants also checks the self-check.

**2026-11-11T20:38:59Z**

Review fixes. D5: the invariant reads 'hidden one at a time ... at the median'; unsupportedFormat reads 'Bookfin cannot match this kind of ebook'. The plan notes that the absolute 2-page limit can refuse a right pairing of a few very long chapters (A Christmas Carol is at 1.25 pages). Follow-up t3-b7wc: a chance pairing by numbers with exactly three anchors can pass the self-check.
