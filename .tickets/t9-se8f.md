---
id: t9-se8f
status: open
deps: []
links: []
created: 2026-11-07T22:09:38Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-bquq
tags: [ui-rules, engine-rules, performance]
---
# The catalog builds the library off the UI isolate and publishes narrow change signals

Rules: UI rule 3 (narrow change signals). Engine rule 1 (no whole-store JSON work, grouping or sorting of the library on the UI isolate).

Breaks:
- lib/catalog/controller.dart, CatalogController: one ChangeNotifier carries the session, access, books, libraries, busy and message. A busy change during a refresh rebuilds every page that shows books (LibraryShelf, SearchPage, SeriesPage, BookPage).
- lib/catalog/controller.dart, _publish, refresh and _edit: buildBooks runs on the UI isolate. refresh builds the books twice, once to validate and once in _publish.
- lib/catalog/store.dart, CatalogCache.decode and encode: the whole saved catalog is decoded, encoded and validated with buildBooks on the UI isolate, from LocalCatalogStore.read and write.
- lib/catalog/transport_io.dart, the response read: jsonDecode(utf8.decode(bytes)) of each Jellyfin response, including whole library pages, runs on the UI isolate.
- lib/catalog/shelf.dart, shelf and search: widgets call them on the UI isolate. shelf groups and sorts the whole library for each book list and filter. search filters and sorts the whole library on each keystroke.
- lib/catalog/model.dart, possibleMatches: BookPage scans the whole library on each catalog notification.

Target design:
The catalog stays the one owner of the book list. It builds a library view in one Isolate.run hop. The hop decodes a saved cache when there is one, runs buildBooks, groups the shelf for each filter that needs no download state (all, audio, ebooks), and builds a series index and a match index. The hop takes the JSON string or the fetched entries and returns the view through Isolate.exit, so the result is not copied. Validation and publication use the same built books, so a refresh builds once. The Jellyfin transport decodes large responses off the UI isolate. search(query) and shelfOf(books), for the Downloaded filter, run off the UI isolate and complete with a list. A caller drops a stale result.

The catalog adds narrow listenables beside its ChangeNotifier:
- library: the published view. It changes only when the books change.
- account: the session and access.
- status: busy and message.
The ChangeNotifier stays for its current listeners. The widget tickets move to the narrow listenables. Keep the members that other files use today (books, shelf, search, possibleMatches, readingOrder) working, so this ticket merges before the widget tickets. Document which members the widget tickets replace.

Owned files: lib/catalog/controller.dart, lib/catalog/store.dart, lib/catalog/model.dart, lib/catalog/shelf.dart, lib/catalog/transport_io.dart, lib/catalog/transport_web.dart, and the tests of these modules.

## Acceptance Criteria

- A refresh that changes no book notifies status and does not notify library (notification counter).
- Restore, refresh and a correction each build the books once, in another isolate (a test records the isolate of the build).
- The saved catalog decodes in another isolate. A corrupt saved catalog still gives the same message and keeps the account signed in.
- search and shelfOf give the same results as today's functions for a fixture library. The existing shelf tests pass.
- checkInvariants also proves that the library view matches the books.

