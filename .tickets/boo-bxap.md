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

