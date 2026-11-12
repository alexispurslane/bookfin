---
id: t2-xkzt
status: closed
deps: [t2-uyth]
links: []
created: 2026-11-11T22:44:17Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-vh77
---
# Keep the heard windows of each downloaded audio edition

A new data source owns the heard windows of each audio edition: their times and heard words, not ebook offsets. Derived data: local, rebuildable, never synced, never a personal record. One file per edition, keyed by its files and revisions, written atomically. It hears a window on request through the speech runtime, with one queue: a History tap first, then listening, then the fill. Contracts and checkInvariants.


## Notes

**2026-11-11T23:30:47Z**

Built: lib/speech/heard_windows.dart. HeardWindows owns the windows of each audio edition (file, revision, start, length, heard words with times; no ebook offsets), in edition order, read lazily from a DerivedStore value per edition id (JSON through an isolate hop, atomic write), filtered to the files' current revisions; an unreadable value starts empty; a failed write keeps this run's windows. One queue, one window at a time: hear() for a person who waits goes before hearSoon() of listening; an 8 s window centered on its place, kept inside its file; a place that a kept or queued window covers is not heard again. checkInvariants: edition order, words in every window, no duplicate queued windows. Second use of the outline store: lib/foundation/derived_store*.dart (DerivedStore, DiskDerivedStore, createDerivedStore) now serves Crossings too; lib/crossings/outlines*.dart removed. Tests: test/speech/heard_windows_test.dart, test/foundation/derived_store_test.dart.

**2026-11-12T01:28:13Z**

Review fixes: a place of a file that this phone streams is refused at once in _request, not after the queued windows (Go to no longer waits behind another window for a streamed book). Contracts: _add asserts that a kept window holds words and that the edition's windows stay in order; _request asserts that no two queued windows share a file and start; _pump asserts that it takes the most pressing priority. checkInvariants shares the helpers.
