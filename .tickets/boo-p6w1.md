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

## Supported API source audit — 2026-11-13

Read Jellyfin v10.11.0 source, the version referenced by the approved plan.
This is static API evidence, not a request to the user's server or an executed
integration test. Source captures and SHA-256 hashes are retained in
`/tmp/bookfin-jellyfin-collection-audit/sources.json`.

- `Jellyfin.Api/Controllers/ItemsController.cs:274-278` explicitly clears
  parentId when includeItemTypes contains only BoxSet. Adding a book-library
  parent to that query therefore does not narrow its collection enumeration.
- `MediaBrowser.Model/Querying/ItemFields.cs` has no Id option.
  `Emby.Server.Implementations/Dto/DtoService.cs:884` assigns dto.Id without
  an optional-field check. Do not send fields=Id.
- ItemsController accepts includeItemTypes, startIndex, limit, enableImages,
  and enableUserData, and passes item types into InternalItemsQuery. These
  are candidates for reducing collection-child responses. The controller
  routes those requests through the selected folder's GetItems operation;
  validate the BoxSet/linked-child path before assuming that filters,
  pagination and recursive behavior have ordinary library semantics.
- `MediaBrowser.Controller/Entities/Movies/BoxSet.cs` includes linked children
  and per-user visibility rules. A narrowed query must preserve mixed
  collections and admitted book membership rather than infer membership
  from the collection's physical parent directory.

Sources:
https://github.com/jellyfin/jellyfin/blob/v10.11.0/Jellyfin.Api/Controllers/ItemsController.cs
https://github.com/jellyfin/jellyfin/blob/v10.11.0/MediaBrowser.Model/Querying/ItemFields.cs
https://github.com/jellyfin/jellyfin/blob/v10.11.0/Emby.Server.Implementations/Dto/DtoService.cs
https://github.com/jellyfin/jellyfin/blob/v10.11.0/MediaBrowser.Controller/Entities/Movies/BoxSet.cs

No production or test changes, query execution, cache design, or delegate
launch followed this audit. Freshness ownership and bounded note selection
remain separate unsettled work; this audit does not authorize a second cache.

Additional paging evidence from
https://github.com/jellyfin/jellyfin/blob/v10.11.0/MediaBrowser.Controller/Entities/Folder.cs:
`GetItemsInternal` at lines 970-1002 passes limit/startIndex into a child
query without includeItemTypes, obtains those children, then applies the
outer filter. It retains the unfiltered child count. `AddChildrenFromCollection`
at lines 1347-1380 applies the page boundary to those children. Therefore a
nonrecursive mixed-collection page can contain fewer matching book items,
or no matching items, while later pages still contain books. A fixture that
filters before paging would hide this server behavior. When narrowing child
queries, advance through the counted source pages; do not end pagination
because a filtered page is short or empty. Keep recursive semantics unchanged
unless a separate equivalence test establishes that changing them preserves
membership. No runtime proof is claimed by this source audit.
