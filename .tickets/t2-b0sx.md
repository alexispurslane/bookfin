---
id: t2-b0sx
status: open
deps: []
links: []
created: 2026-11-12T01:24:35Z
type: chore
priority: 4
assignee: Alexis Purslane
parent: boo-z3is
---
# Remove the HeardWindows members that only tests use

HeardWindows.windowsNow, changes and flush have no production caller, and the _editions map serves mostly them. Remove them and rewrite their tests through windowsOf and hear, or give them a production caller (for example, Crossings growing its anchor map when a window arrives). Found in the boo-vh77 review (D6).

