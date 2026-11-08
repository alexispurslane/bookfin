---
id: tf-o5vc
status: closed
deps: [td-rvpm, ta-7oe6, tf-0nvi, boo-7ua0, t6-n8y3, t1-gaeu, t2-7ptd, boo-du96]
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


## Notes

**2026-11-08T00:12:38Z**

Orchestrator, Nov 7: the orchestrator does this one-line refactor after groups B and C merge.

**2026-11-08T01:23:12Z**

Found in tb-jllp: PdfHop (lib/reader/pdf.dart, the hop that PdfRuntime.open takes to prepare page text) is a fourth copy of the same typedef. Use the shared type there too.
