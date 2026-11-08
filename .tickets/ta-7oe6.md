---
id: ta-7oe6
status: open
deps: [t6-2ghu, boo-0km1, t9-6u46]
links: []
created: 2026-11-07T22:55:12Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-bquq
tags: [engine-rules, performance]
---
# Hand catalog page bytes to the catalog worker, so a refresh copies no entries

From t6-2ghu. A refresh still builds its entries on the UI isolate and copies them into the catalog worker: 36 to 130 ms on the UI isolate for 5000 entries (t9-se8f measurement in AOT). t6-2ghu could not fix this in its owned files. The cause is the transport: JsonTransport.send (lib/catalog/transport_protocol.dart, transport_io.dart, transport_web.dart) returns a decoded Map. The io transport decodes a large response in its own hop, and the map comes back to the UI isolate. So JellyfinClient.catalog holds every page as maps on the UI isolate, and any later hop must copy them. The fix needs four changes. 1. The transport gets a request that returns the response body as bytes (Uint8List), with the same status, size, timeout and cancellation rules as send. 2. JellyfinClient.catalog returns the raw pages (body bytes and library id per page, plus the collection names by item id) instead of CatalogEntry objects. A top-level function validates the pages and builds the entries; it runs in the worker. The page checks (TotalRecordCount, StartIndex, duplicate ids, item types) and the safe-field filter move into it. 3. CatalogController.refresh sends the pages and the current edits to one hop that decodes, builds the entries, the cache, the content digest, the saved text and the library. A small refresh (under 16 entries or 16 KiB of page bytes) still builds on the UI isolate until t6-n8y3. 4. The test fixtures that override catalog() move to the new return type: FixtureClient in test/catalog/controller_test.dart and _CatalogFixture in test/downloads/screen_test.dart. Owned files: lib/catalog/transport_protocol.dart, transport_io.dart, transport_web.dart, transport_stub.dart, lib/catalog/jellyfin.dart, lib/catalog/controller.dart, test/catalog/controller_test.dart, test/catalog/catalog_signals_test.dart, test/catalog/jellyfin_test.dart, test/catalog/transport_io_test.dart, test/downloads/screen_test.dart.

## Acceptance Criteria

The skipped test 'a refresh hands the worker Jellyfin's responses, not built entries' in test/catalog/catalog_signals_test.dart runs and passes. A refresh of 5000 entries hands no CatalogEntry objects from the UI isolate to the worker. Cancel and dispose still stop the page requests.


## Notes

**2026-11-08T00:12:38Z**

Orchestrator, Nov 7: one agent does ta-7oe6 and t6-n8y3 together (group B), catalog hop work.
