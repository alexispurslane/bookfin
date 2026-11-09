---
id: boo-02sx
status: open
deps: [t7-bbv1]
links: []
created: 2026-11-09T17:13:34Z
type: feature
priority: 2
assignee: Alexis Purslane
parent: boo-b2ey
---
# Estimate the time left in the book

Requested by the user on 2026-11-09. Show an estimate of the reading time left in the book and in the chapter. The reading speed comes from this reader's own page turns (pages or characters per minute, ignoring very short and very long pauses). The amount left comes from the whole-book page starts of t7-bbv1, or from visible characters before the book is laid out. Decide where the speed is stored and whether it is per book or per reader; it is derived data and must never put listening history or reading places at risk. Show nothing until the estimate has enough samples.

