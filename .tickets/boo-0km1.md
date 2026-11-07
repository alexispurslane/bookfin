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

