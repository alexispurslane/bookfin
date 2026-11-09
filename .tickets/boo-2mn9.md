---
id: boo-2mn9
status: open
deps: []
links: []
created: 2026-11-09T01:55:36Z
type: task
priority: 3
assignee: Alexis Purslane
parent: boo-b2ey
---
# Let idle layout go on during an animation that never ends

Since t7-hufl, PageSource runs an idle layout step only after a frame that ends with no animation (transientCallbackCount == 0). An animation that runs without end while a book is open (an indeterminate progress indicator, a looping icon) would hold the main runs back for as long as it runs, so page counts and back turns across a section would wait. Today the reader shows only short ones (the search progress line). Make sure that no endless animation runs over the reader, or let an idle step run after a frame when the frame left enough time (for example from the frame timings), so idle work still moves forward at a bounded cost.

