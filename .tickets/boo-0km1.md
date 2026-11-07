---
id: boo-0km1
status: open
deps: [boo-um68]
links: []
created: 2026-11-07T21:20:29Z
type: feature
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Refresh the library silently at launch

The library already loads from disk at launch. Hide the background refresh: no progress bar under the app bar and no Saved library timestamp line during it; bind Playback and Downloads to the saved books at launch (see boo-petv); swap fresh data in without moving the scroll position. Speak up only for a user pull-to-refresh, an expired sign-in or revoked access, or a failed refresh while the saved library is old.


## Notes

**2026-11-07T21:47:00Z**

From boo-5jzo: the 'Saved library · Today, 4:29 PM' line (now built with dayAndTime) and the catalog.busy progress bar in lib/catalog/screen.dart are the engine rule 2 breaks this ticket removes.

**2026-11-07T21:55:32Z**

From boo-um68: _CatalogStatus in lib/catalog/screen.dart is now the one place that shows the refresh progress line and the catalog error; it is the seam for this ticket. Pull-to-refresh in LibraryShelf is the other tell.
