---
id: boo-8xyn
status: open
deps: []
links: [boo-7z9a]
created: 2026-11-12T23:41:01Z
type: task
priority: 3
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Keep one copy of the catalog on the UI isolate

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: confirmed, size estimated. lib/catalog/controller.dart:268-276. The controller keeps the frozen entry maps (`_cache.entries`), the encoded text (`_text`) and the built library. On the UI isolate only `checkInvariants` reads the entries. The estimate is 20 to 30 MB for 1478 books, and it grows linearly. Keep the account facts and the built library, and let the worker read the entries again when it rebuilds. The corrections store ticket makes this natural.

