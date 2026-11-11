---
id: t9-k6kd
status: open
deps: [t9-4ey6]
links: []
created: 2026-11-11T15:44:45Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-z3is
---
# Find the landing of a place of the other edition through Crossings

Step 5 of design A in docs/plans/cross-edition-places.md. Crossings is an app-wide data source. It keeps text outlines in a JSON cache keyed by edition id and revision (atomic write), keeps alignments, and gives landing(place, into: openEdition). It writes no personal record. checkInvariants() checks the four documented invariants on demand.

