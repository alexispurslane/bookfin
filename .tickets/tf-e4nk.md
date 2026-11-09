---
id: tf-e4nk
status: open
deps: []
links: []
created: 2026-11-09T02:13:04Z
type: feature
priority: 3
assignee: Alexis Purslane
parent: boo-b2ey
---
# Select a word with a mouse double-click on a native page

Found in tc-iwqp. On a desktop, the viewport's own tap recognizer wins every single click, so the SelectionArea's tap-and-pan recognizer never sees a second click, and a double-click toggles the reader controls twice instead of selecting a word. A mouse drag, Cmd or Ctrl+A and Cmd or Ctrl+C work. Files: lib/reader/epub/viewport.dart.

## Acceptance Criteria

A mouse double-click on a word selects it and does not toggle the controls. A single click still toggles them, and a click with a selection clears it.

