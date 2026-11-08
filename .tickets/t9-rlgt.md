---
id: t9-rlgt
status: in_progress
deps: [t9-sspn, t9-xj41, t9-8v91]
links: []
created: 2026-11-07T22:09:39Z
type: task
priority: 4
assignee: Alexis Purslane
parent: boo-bquq
tags: [ui-rules]
---
# Build the development gallery from production widgets

Rules: UI rule 2 (one component for each kind of thing).

Breaks:
- lib/development/gallery.dart, _BookRow, _Cover, _PlayerFixture and _ReaderFixture: the development gallery keeps its own copies of book rows, covers, the player and the reader.

Target design:
Build the gallery fixtures from the production widgets (BookRow, BookCover, the player leaves, the reader panels) with fake sources. Keep the gallery's fixtures and its browser preview use. te-6x43 also concerns the gallery. If both run at once, order them.

Owned files: lib/development/gallery.dart and its tests.

## Acceptance Criteria

- The gallery defines no widget that duplicates a production widget.
- The gallery test renders each fixture.

