---
id: boo-cows
status: in_progress
deps: []
links: []
created: 2026-11-08T14:49:05Z
type: feature
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Name the device or the sync time on sync conflict choices and their bookmarks

On Settings > Personal records, each conflict choice reads like 'First Frost · Tom Avery · First Frost · 2:33:16.313' (lib/sync/screen.dart): the book title repeats as the file name, the narrator stands in for the edition, the time shows milliseconds, and nothing says which device saved the place or when. Seen in docs/screenshots/sync-conflict-choose.png on 2026-11-08.

The bookmarks that the choice creates have the same problem: every one is titled 'Saved before sync choice' (docs/screenshots/sync-conflict-bookmarks.png), so the user cannot tell which device each place came from.

If no device name is available, tell the places apart by when each one was saved or synced, for example 'Saved 9:12 PM yesterday'.

## Acceptance Criteria

Each choice and each bookmark that a choice creates names the saving device, or when no device name is known, the time that place was saved or synced; each shows the place as h:mm:ss with the chapter; the book title appears once; tests cover the labels and the fallback.

