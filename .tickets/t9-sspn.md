---
id: t9-sspn
status: open
deps: [t9-se8f, t9-4jqk, boo-y6fb, t9-dcld]
links: []
created: 2026-11-07T22:09:38Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-bquq
tags: [ui-rules, engine-rules]
---
# Library pages subscribe narrowly, group off the UI isolate, and own navigation from their tiles

Rules: UI rule 1 (only controllers cause side effects). UI rule 3 (depend on the minimum, subscribe at the lowest level). Engine rule 1 (no grouping or sorting of the library on the UI isolate).

Breaks:
- lib/catalog/library_view.dart, _LibraryShelfState.build, SearchPage and SeriesPage: listen to the whole catalog and the whole layout, so busy and message changes rebuild the shelf.
- lib/catalog/library_view.dart, _GridTile and _ListRow (through _open): leaves push BookPage and SeriesPage routes.
- lib/catalog/library_view.dart, _GridTile and _ListRow: each tile listens to services.activity, which merges all of Downloads and Playback. While a book plays or downloads, every visible tile reruns its selector (services.progress and services.downloaded) several times a second.
- lib/catalog/library_view.dart, ShelfEntries: reads layout.view and layout.density without subscribing, and depends on the parent's rebuild.
- lib/catalog/library_view.dart, LayoutToggle: writes layout.view itself, which saves to storage.
- lib/catalog/library_view.dart: LibraryShelf groups with shelf(), SearchPage runs search() on each keystroke, and SeriesPage groups the whole library to find one series on each notice. All of it runs on the UI isolate.
- lib/catalog/library_services.dart, LibraryServices.activity: the merged listenable that the tiles and BookPage use.
- lib/catalog/book_cover.dart, CoverScope: one InheritedWidget carries the covers, the session and the playing book. A change of the playing book rebuilds every _CoverFace, but only glass panes read playing.

The Saved library line and pull-to-refresh in LibraryShelf belong to boo-0km1. Leave their behavior as it is.

Target design:
- LibraryTab, SearchPage and SeriesPage are the controllers of their pages and own navigation. ShelfEntries takes onOpen(ShelfItem), and the tiles report taps through it.
- The pages subscribe to the catalog's library listenable and to the layout. LayoutToggle and ShelfEntries get the view and the density as narrow listenables or values. LayoutToggle reports onChanged(LibraryView), and the page sets the layout.
- The shelf comes from the catalog's library view. The Downloaded shelf comes from catalog.shelfOf, asked again when the set of downloaded books changes. Search results come from catalog.search, and the page drops a stale result.
- LibraryServices adds bookActivity(book). It merges Downloads.watch for the book's editions with Playback's position and records signals for its audio editions. A tile subscribes to its own book.
- CoverScope becomes an InheritedModel with one aspect for covers and session and one for the playing book. A cover face does not depend on the playing book.
- Keep LibraryServices.activity, progress and downloaded for BookPage. The book page ticket removes activity.

Owned files: lib/catalog/library_view.dart, lib/catalog/library_services.dart, lib/catalog/book_cover.dart, and their tests.

## Acceptance Criteria

- A playing tick of book A rebuilds only A's tile (rebuild counter).
- A byte notice for an edition of book B rebuilds only B's tile.
- A catalog busy change rebuilds no tile and no page body.
- A tap on a tile reports onOpen with its item, and the page pushes the route (navigator observer).
- LayoutToggle reports onChanged and writes nothing (a layout fake that throws on write).
- A change of the playing book rebuilds no cover face outside glass panes.
- A typed query reaches results through catalog.search, and a stale result does not replace a newer one.


## Notes

**2026-11-07T22:25:14Z**

boo-y6fb merged: Playback has positionNotifier (AudioPosition?, fires on every decoder report), selectionNotifier ((book, edition, playing, active)), sleepNotifier (Duration? left, once a second), recordsNotifier (history, bookmarks or resumes replaced), settingsNotifier ((speed, backward, forward)) and statusNotifier ((message, saveFailed)). Undo, the replacement offer and unsavedChanges have no narrow signal; those widgets stay on the broad notification, which stops firing on ticks after t9-cx1u.

**2026-11-07T22:26:04Z**

User decision (see boo-0km1): when the catalog status says Jellyfin cannot be reached, LibraryShelf shows only downloaded books without changing the user's ShelfFilter. Build the shelf so the effective filter can come from the catalog status; boo-0km1 adds the message and Retry.
