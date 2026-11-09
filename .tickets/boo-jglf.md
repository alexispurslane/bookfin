---
id: boo-jglf
status: open
deps: [t7-bbv1]
links: []
created: 2026-11-09T17:13:34Z
type: feature
priority: 2
assignee: Alexis Purslane
parent: boo-b2ey
---
# Number the pages of the whole book

Requested by the user on 2026-11-09. After t7-bbv1, every section of an EPUB or MOBI keeps its true page starts once the background work reaches it. Use them to number pages across the whole book, for example "Page 134 of 412", instead of within the section. Decide what the label shows before the whole book is laid out, and after a settings change, when the count is not known yet. Report two designs to the orchestrator if the plan does not settle it. A page number and a count must never jump backward while the reader stays on a page. Saved places do not change: they still save the first visible character.


## Decision (user, 2026-11-09)

Before the whole book is laid out (first open, or after a settings change), the label shows the chapter numbers as today ("Page 3 of 18"). When every section has its page starts, it switches to whole-book numbers ("Page 134 of 412").
