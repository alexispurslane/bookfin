---
id: t2-ttb6
status: open
deps: []
links: []
created: 2026-11-12T01:24:33Z
type: chore
priority: 3
assignee: Alexis Purslane
parent: boo-z3is
---
# Let HeardWindows own where a window sits around a place

HeardWindows._span centers a window on a place, and three callers repeat that rule: HearingPolicy shifts the place by -windowMs/2 so that the window ends at the listening place, SpeechPlaces.millisecondsAt uses nextMs - windowMs/2 as a window start, and ReadingSearch.fold steps by windowMs. HeardWindow.covers and _Job.covers repeat each other. Let callers say what they want (the window that ends at this place, or the one around it) and read the start of the window that comes back, so that a change of placement, such as t2-4ci0's suggestion to put the place in the first half, changes one owner. Found in the boo-vh77 review (D1).

