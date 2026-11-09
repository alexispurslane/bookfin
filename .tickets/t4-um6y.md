---
id: t4-um6y
status: open
deps: []
links: []
created: 2026-11-09T23:55:23Z
type: bug
priority: 3
assignee: Alexis Purslane
parent: boo-m27l
---
# End a reading jump's move at the page that the jump itself shows

ReaderSession ends a pending move at the first place that the navigator reports. A page turn asked for before a jump, whose page shows after the jump began, ends the jump's move at the turned page, and the jump's own page then records no move. Jumps already run one after another. Possible fix: the navigator reports which request showed a place.

