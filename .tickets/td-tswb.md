---
id: td-tswb
status: open
deps: []
links: []
created: 2026-11-09T15:41:20Z
type: bug
priority: 3
assignee: Alexis Purslane
parent: boo-fs0n
---
# Move the acceptance DiskCatalog to the text-based CatalogStore interface

Found during boo-j1lm. tool/acceptance/fixture_support.dart DiskCatalog overrides read and write with CatalogCache values, but CatalogStore now moves catalog text (Future<String?> read, write(scope, String)). flutter analyze on tool/acceptance reports two invalid_override errors on main, so the live Jellyfin acceptance tests do not compile. Change DiskCatalog to store the text, and run the acceptance suite against the research server.


## Notes

**2026-11-13T23:10:49Z**

boo-xyrl adds CatalogStore.clearCache(AccountScope), which the acceptance-only DiskCatalog must implement when this existing text-interface migration is completed. Production and gallery use LocalCatalogStore.
