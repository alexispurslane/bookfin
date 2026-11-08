---
id: t6-vbcw
status: open
deps: []
links: []
created: 2026-11-08T21:38:30Z
type: task
priority: 4
assignee: Alexis Purslane
parent: boo-b2ey
---
# Fill the space above a split table row with its first lines

Found in te-4cez. A table row taller than a page splits into fragments that table.dart sizes from the row's own top, so the first fragment always starts a new page and leaves the space below the content before it empty. Chromium fills that space with the row's first lines. A first fragment sized to the space left on the page depends on the page's top, which a run that starts at a later fragment of the row cannot know. A fix needs a PageStart that carries the first fragment's height, or a proof that the property holds another way. Decide whether the fidelity check (tc-pshi) shows enough of a difference to need it.

