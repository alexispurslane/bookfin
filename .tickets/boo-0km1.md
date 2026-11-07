---
id: boo-0km1
status: open
deps: [t9-se8f, t9-dcld, t9-sspn, boo-petv, t6-2ghu, t6-epwo, t4-lvhh]
links: []
created: 2026-11-07T21:20:29Z
type: feature
priority: 2
assignee: Alexis Purslane
parent: boo-bquq
tags: [engine-rules]
---
# Refresh the library silently at launch

The library already loads from disk at launch. Hide the background refresh: no progress bar under the app bar and no Saved library timestamp line during it; bind Playback and Downloads to the saved books at launch (see boo-petv); swap fresh data in without moving the scroll position. Speak up only for a user pull-to-refresh, an expired sign-in or revoked access, or a failed refresh while the saved library is old.

Rules: engine rule 2.

Breaks (verified at f388307):
- lib/catalog/screen.dart, _CatalogStatus: shows the LinearProgressIndicator for catalog.busy, and the catalog message, during the background refresh at launch.
- lib/catalog/library_view.dart, _LibraryShelfState._build: shows the 'Saved library · <time>' line while the catalog is not verified.
- lib/catalog/controller.dart, refresh: a user refresh and a background refresh share one busy and message state, so no widget can tell them apart. A failed background refresh sets message, which every tab and the book page show.
- lib/catalog/controller.dart, refresh and _publish: a refresh replaces every Book and Edition object. That ends the first reopen of the saved book (boo-petv) and can move the scroll position.

Target design: the status listenable from t9-se8f carries a visible status only for a refresh that the user asked for (pull-to-refresh, Save libraries, Refresh libraries) and for the failures that the first paragraph names. The background refresh at launch is silent. AccountBinding from t9-dcld binds Downloads and Playback to the saved books at once. The shelf keeps its scroll position when the view changes in place.

Replaced by the user later on November 7, 2026 (supersedes the 7-day decision):
- At launch the library shows the saved library and refreshes in the background. The progress line in _CatalogStatus appears only after the refresh runs longer than 1.5 seconds; a faster refresh shows nothing. The delay is ephemeral UI state in the widget that shows the line.
- If Jellyfin cannot be reached (network error, timeout or server error; the catalog's status signal from t9-se8f says which), the library shows only downloaded books, with a short message such as "Cannot reach Jellyfin. Showing downloaded books." and a Retry action. The user's chosen filter (ShelfFilter) does not change; the shelf derives the offline view from the status. With no downloads, the empty state says so.
- The next refresh that reaches Jellyfin (app resume, pull to refresh, Retry) brings the full library back. An expired sign-in and revoked access keep their own messages.
- No "Saved library" label.

Former open decision: what counts as an old saved library for the failure notice.
- Option A: a fixed age, for example 7 days after completedAt. Cost: a limit that the user did not choose.
- Option B: never speak about a failed background refresh. Speak only for a user refresh, an expired sign-in and revoked access. Cost: a user whose library is very old gets no hint that refreshes fail.

Owned files: lib/catalog/screen.dart (_CatalogStatus), lib/catalog/library_view.dart (the Saved library line and RefreshIndicator), lib/catalog/controller.dart (refresh status), lib/app/account_binding.dart (binding at launch), and their tests.

## Acceptance Criteria

A launch with a saved library and a slow refresh shows no progress bar, no Saved library line and no message, and the shelf is usable at once. A pull-to-refresh shows progress and a failure. An expired sign-in and revoked access still speak. A refresh that replaces equal books keeps the shelf's scroll offset.

## Notes

**2026-11-07T21:47:00Z**

From boo-5jzo: the 'Saved library · Today, 4:29 PM' line (now built with dayAndTime) and the catalog.busy progress bar in lib/catalog/screen.dart are the engine rule 2 breaks this ticket removes.

**2026-11-07T21:55:32Z**

From boo-um68: _CatalogStatus in lib/catalog/screen.dart is now the one place that shows the refresh progress line and the catalog error; it is the seam for this ticket. Pull-to-refresh in LibraryShelf is the other tell.
