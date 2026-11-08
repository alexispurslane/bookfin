---
id: t3-pk3x
status: open
deps: []
links: []
created: 2026-11-08T00:15:11Z
type: task
priority: 4
assignee: Alexis Purslane
parent: boo-bquq
tags: [ui-rules]
---
# Make the reader control bar a leaf that the gallery can show

Rules: UI rule 2 (one component for each kind of thing).

Breaks:
- lib/reader/screen.dart, _ReaderScreenState.build and _button: the control bar (Contents, Search book, Smaller text, Larger text, Bookmark this place, Reading bookmarks, reading theme) is built inline in the screen State.
- lib/development/gallery.dart, _ReaderFixture: the gallery has stand-in TextButtons for these controls (a TODO marks them).

Target design:
A ReaderControls leaf takes which controls are enabled and reports each tap through callbacks. The reader screen stays the controller: it subscribes to the reader session at the lowest level and runs the actions. The gallery shows the same leaf with sample state.

Owned files: lib/reader/screen.dart and its tests, then lib/development/gallery.dart.

## Acceptance Criteria

- The reader screen and the gallery both show ReaderControls.
- The gallery defines no reader control buttons of its own.

