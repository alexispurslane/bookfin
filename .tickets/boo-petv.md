---
id: boo-petv
status: open
deps: []
links: []
created: 2026-11-07T19:02:10Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Reopen the saved book without waiting for the library refresh

Found on the Pixel 8 on 2026-11-07. At launch the saved book reopens only after the full Jellyfin library refresh (about 20 s on the real server). The first reopen, against the cached library, gives up when the refresh replaces the Book and Edition objects mid-open (_currentEdition compares edition objects). Let the first reopen survive an equal catalog replacement, for example by comparing edition ids and sources, so the player and mini player appear at once.

