---
id: boo-nklp
status: open
deps: []
links: []
created: 2026-11-12T02:06:15Z
type: bug
priority: 2
assignee: Alexis Purslane
parent: boo-vh77
---
# Run the speech fill only when the phone is idle and charging

The user's design (docs/plans/cross-edition-places.md, 'Decision on speech search', and the anchor-map answer of 2026-11-11) runs the fill for old and synced entries only when the phone is idle and charging, newest first, never in battery saver. As built in boo-vh77, the fill runs whenever the speech queue is empty, on battery too. Make it wait for charging and device idle.

