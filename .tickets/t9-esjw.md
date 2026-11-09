---
id: t9-esjw
status: open
deps: [t7-bbv1]
links: []
created: 2026-11-09T18:24:43Z
type: bug
priority: 2
assignee: Alexis Purslane
parent: boo-b2ey
---
# Make the first text size press move a fixed-size book's text in the pressed direction

Found during boo-0ari on 2026-11-09. Before the first press of a text size button, a book that fixes its body text keeps its own size, for example 16 pixels (12 pt), while the reader's stored size is 20. The first press switches the reader to sizing the book's main text, from the stored size: Smaller gives 18 pixels and Larger gives 22. So the first Smaller press makes such a book's text larger. Every later press moves in the pressed direction. Books whose body text follows the reader's size (all 90 corpus books) are not affected. This needs a user decision. Option A: keep it. The first press is the moment the reader takes over, and the size shown in the settings sheet becomes true. Option B: step the first press from the open book's shown main text size, which needs the pager to report that size to the session.


## Decision (orchestrator, 2026-11-09)

Option B. boo-0ari already required that each press moves the text in the pressed direction. The first press steps from the main text size that the open book shows.
