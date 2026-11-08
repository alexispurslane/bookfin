---
id: t3-rlq6
status: closed
deps: []
links: []
created: 2026-11-08T00:15:11Z
type: task
priority: 4
assignee: Alexis Purslane
parent: boo-bquq
tags: [ui-rules]
---
# Make the library filter row a leaf that the gallery can show

Rules: UI rule 2 (one component for each kind of thing).

Breaks:
- lib/catalog/library_view.dart, LibraryTab: the filter chips (All, Audio, Ebooks, Downloaded) are built inline in the tab State, so no other widget can show them.
- lib/development/gallery.dart, _LibraryFixture: the gallery keeps its own two ChoiceChips (All books, Downloaded) because of this.

Target design:
A ShelfFilterChips leaf in library_view.dart takes the shown ShelfFilter and reports onChanged(filter). LibraryTab keeps the filter state and uses the leaf. Then the gallery shows the same leaf with sample state.

Owned files: lib/catalog/library_view.dart and its tests, then lib/development/gallery.dart.

## Acceptance Criteria

- LibraryTab and the gallery both show ShelfFilterChips.
- The gallery defines no filter chips of its own.

