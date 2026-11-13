---
id: boo-p6w1
status: open
deps: []
links: []
created: 2026-11-12T23:41:00Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Read only the collections that hold books during a catalog refresh

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: confirmed. lib/catalog/jellyfin.dart:496-529 lists every BoxSet on the server, then reads the full records of the children of each one (up to 2000, with no field limit), 8 at a time. The cost grows with the collections of the server, which on a mixed server are mostly movie collections. Errors return an empty map silently. Limit the child query to book item types and the Id field, or query the collections of each book library, and keep the map between refreshes.

## Parent read-only audit — 2026-11-13

At `27dc49fd`, catalog starts _collections concurrently with book-library
pages. _collections still requests up to 1000 BoxSet items globally and up
to 2000 children per set, eight child requests at once. Those child requests
contain userId, parentId and limit only. The catalog page query separately
accepts AudioBook, Book and Audio. catalogEntries attaches collection names
only to admitted book item ids; the unneeded work occurs before that filter.
Current collection tests use a real loopback server with a book collection
and a film collection, and preserve catalog success when collections fail.
Cancellation is rethrown; other collection failures produce no series map.

Do not implement the survey's literal fields=Id suggestion without checking
the pinned/supported Jellyfin API: optional fields may not include the core
Id property. Confirm parent/recursive/type filters preserve mixed collections,
audio-book files, all relevant pages and series membership. Establish the
actual request/response reduction through fixtures; no server timing or
memory result has been measured here.

Keeping a map between refreshes also needs an explicit owner, account scope,
refresh/invalidation rule and failure policy. CatalogClient currently has
request lifetime; CatalogController's saved catalog already keeps derived
series facts. A second unversioned map risks stale memberships and must not
be added just because the survey suggests caching. Query narrowing can ship
first if the eventual model keeps that fix unchanged. No design choice,
implementation, test or delegate launch occurred during this audit.
