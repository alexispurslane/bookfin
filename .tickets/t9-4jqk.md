---
id: t9-4jqk
status: in_progress
deps: []
links: []
created: 2026-11-07T22:09:38Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-bquq
tags: [ui-rules, engine-rules, performance]
---
# Downloads publishes per-edition state, owns the leftover inventory, and hashes off the UI isolate

Rules: UI rule 1 (long-lived data in a leaf State). UI rule 3 (narrow change signals). Engine rule 1 (no synchronous storage access or heavy CPU work on the UI isolate).

Breaks:
- lib/downloads/downloads.dart, Downloads: one notifier carries the byte progress of every edition, beside phases. A widget that shows one edition (DownloadControls, DownloadButton, _DownloadRow, library tiles) cannot subscribe to that edition, so each parent rebuilds on any byte notice.
- lib/downloads/screen.dart, _LeftoverInventory: the leftover-file read (retainedStorage) lives in a leaf State and repeats on each phases notice. After this ticket the data source owns it. The Downloads tab ticket changes the screen.
- lib/downloads/local_downloads.dart, retainedStorage: FileSystemEntity.typeSync on the root and account directories on the UI isolate. _savedLength serves only checkInvariants and can stay.
- lib/downloads/local_downloads.dart, _verified and _download: sha256.bind over a whole downloaded file on the UI isolate. An audiobook file is hundreds of megabytes.
- lib/downloads/local_downloads.dart, bind: on each bind, which is each catalog change, it hashes every source of the library (sha256 of jsonEncode per file) and jsonEncodes a signature of the whole library on the UI isolate.
- lib/downloads/local_downloads.dart, _restore: decodes one manifest per record on the UI isolate. Batch these reads into one hop if a library with many records shows a cost.
- lib/downloads/local_downloads.dart, _current: jsonEncode of one edition identity per command. This is small. Add the engine rule 1 comment that says why it stays inline.

Target design:
Downloads stays the one owner of transfer state and saved files.
- It adds watch(edition), a ValueListenable<EditionDownload> that notifies only when that edition's state changes, byte progress included.
- It adds leftovers, a ValueListenable of the leftover inventory (last list, a reading flag and an error), and reloadLeftovers(). It reads the inventory when an account binds, when phases notifies, and on reload. A screen shows it without its own future.
- File digests run in a worker isolate that reads the file itself.
- The bind signature and the source ids come from one off-isolate hop per bind.
- The broad notifier and phases stay for current listeners. The cut-over ticket removes broad byte notices later.

Owned files: lib/downloads/downloads.dart, lib/downloads/local_downloads.dart, lib/downloads/platform_io.dart, lib/downloads/platform_stub.dart, lib/downloads/derived_files.dart, and their tests.

## Acceptance Criteria

- A byte notice for edition A notifies watch(A) and does not notify watch(B).
- leftovers notifies once for each phase change and each reload, and never for byte progress. It keeps the last good list while a reload runs.
- A failed inventory read sets the error and removes no file.
- The digest of a downloaded file is computed in another isolate (test), and a changed file still fails verification.
- No *Sync call remains in local_downloads.dart outside checkInvariants and its helpers.

