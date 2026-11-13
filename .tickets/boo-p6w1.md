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

