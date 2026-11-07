---
id: boo-petv
status: closed
deps: [boo-y6fb]
links: []
created: 2026-11-07T19:02:10Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-bquq
tags: [engine-rules]
---
# Reopen the saved book without waiting for the library refresh

Found on the Pixel 8 on 2026-11-07. At launch the saved book reopens only after the full Jellyfin library refresh (about 20 s on the real server). The first reopen, against the cached library, gives up when the refresh replaces the Book and Edition objects mid-open (_currentEdition compares edition objects). Let the first reopen survive an equal catalog replacement, for example by comparing edition ids and sources, so the player and mini player appear at once.

Rules: engine rule 2 (cached information is fully usable, and no network request is on the path to the first useful frame).

Owned files: lib/playback/playback.dart and its tests. Order: after boo-y6fb and before boo-63ti, because all three change playback.dart. t9-dcld moves account binding into lib/app/account_binding.dart. This ticket does not change binding.

## Acceptance Criteria

With a saved library and a slow refresh that replaces equal Book and Edition objects, the saved book reopens paused at its saved position before the refresh completes, and it stays open after the refresh.
