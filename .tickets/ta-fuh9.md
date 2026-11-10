---
id: ta-fuh9
status: open
deps: []
links: []
created: 2026-11-10T00:22:23Z
type: bug
priority: 4
assignee: Alexis Purslane
parent: boo-m27l
---
# Record no chapter move for a page turn that shows while a chapter arrow does nothing

Found during t4-um6y on 2026-11-09. A chapter arrow at the book's last chapter asks the navigator for nothing, so no destination request supersedes a page turn that is still in flight. ReaderSession notes the pending chapter move before the arrow finds that there is no chapter to go to, and drops it a few microtasks later. If the turned page reports its place in that window, the session records a Changed chapter move that ends at the turned page. The window is a few microtasks long, so no test reproduces it yet. Possible fix: moveChapter finds the chapter step before _jump notes the pending move, or drops the pending move at once when there is no step.

