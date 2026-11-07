---
id: t6-2ghu
status: in_progress
deps: []
links: []
created: 2026-11-07T22:41:16Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-bquq
tags: [engine-rules, performance]
---
# Build the refreshed catalog entries in the worker, not on the UI isolate

From t9-se8f. JellyfinClient.catalog in lib/catalog/jellyfin.dart filters each library page into safe maps and freezes every CatalogEntry on the UI isolate. The catalog refresh hop then copies all entries into the worker isolate. Measured in AOT on an M-series Mac, that copy costs 36 to 130 ms on the UI isolate for 5000 entries with descriptions and chapters. A correction (CatalogController._edit) and a saved denial (_failure) copy the cached entries into the hop in the same way. Target: the worker receives response text or bytes, which cross as one block copy, and builds the entries, the books and the saved text there. Owned files: lib/catalog/jellyfin.dart, lib/catalog/controller.dart, and their tests.

## Acceptance Criteria

A refresh of 5000 entries hands no CatalogEntry objects from the UI isolate to the worker. A correction hands the saved text, not the entries.

