---
id: tf-o5vc
status: open
deps: [td-rvpm, ta-7oe6, tf-0nvi]
links: []
created: 2026-11-07T23:48:23Z
type: chore
priority: 4
assignee: Alexis Purslane
parent: boo-bquq
tags: [engine-rules]
---
# Share one isolate hop type between the catalog, records and OCR stores

Found in boo-4bof. CatalogHop (lib/catalog/controller.dart), RecordsHop (lib/playback/store.dart) and OcrHop (lib/reader/ocr_storage_io.dart) are the same one-line typedef of a function that runs work on an input in another isolate. Move one definition to lib/foundation and use it in all three. OcrHop takes FutureOr work, so the shared type takes FutureOr work too.

## Acceptance Criteria

One hop typedef in lib/foundation, used by the three stores, and no behavior change.

