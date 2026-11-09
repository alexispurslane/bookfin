---
id: boo-zcb8
status: open
deps: []
links: []
created: 2026-11-09T16:01:35Z
type: bug
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Do not group books by a series name that is only the library folder's name

Jellyfin 12.4 gave 21 of the 24 ebooks in the user's Ebooks library the series name "Books". That is the name of the library's root folder (/media/Streaming/Books), and the books have no series of their own. Bookfin trusts SeriesName first, so the library showed one series "Books" that held 21 books.

On 2026-11-09 the orchestrator cleared SeriesName on those 21 items through the Jellyfin API. A full metadata refresh with replaceAllMetadata did not bring it back, so a resolver probably sets it only when Jellyfin first creates the item. New ebooks added to that folder can get the same folder series.

Decide whether the app must ignore a SeriesName that equals the name of the folder that holds the item, when that folder is a library root. A folder below the root that is named after a real series (Dune/Dune.epub) must still group. First make sure that a newly added ebook really gets the folder series.

