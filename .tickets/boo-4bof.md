---
id: boo-4bof
status: open
deps: [boo-l5x3, t9-112h]
links: []
created: 2026-11-07T21:30:01Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-bquq
tags: [performance, engine-rules]
---
# Bring storage and CPU work in line with the engine rules

AGENTS.md engine rule 1 says the UI isolate does no synchronous storage access and no modest CPU work.

The boo-bquq audit at f388307 found breaks in many files. The breaks in files that other children own moved to those tickets: t9-se8f (catalog decode, buildBooks, shelf, search and the Jellyfin transport), t9-4jqk (Downloads typeSync, file digests and bind hashing), t9-sspn and t9-kfdf (shelf use in the pages), and t9-3n2m (the PDF page-text digest). This ticket keeps the rest.

Breaks:
- lib/playback/store.dart, LocalResumeStore.read and _snapshot: builds the whole listening or reading snapshot and deep-copies it with jsonDecode(jsonEncode) on the UI isolate when an account binds or refreshes (from boo-xifx).
- lib/playback/store.dart, _readAccount: the startup journal replay and the SharedPreferences fallback decode and rebuild the whole store on the UI isolate.
- lib/playback/store.dart, _persist without a database: jsonEncode of the whole account for each save.
- lib/playback/store.dart, _write, with lib/reader/session.dart, ReaderSession._save: each reader position change, which is each page turn, builds the whole reading snapshot of the account. The store then deep-copies, flattens and diffs it on the UI isolate. Playback moved to change sets in boo-xifx, and the reader did not.
- lib/playback/store.dart, save: deep-copies each change set with jsonDecode(jsonEncode). This is small for one change set. Add the engine rule 1 comment, or batch it into the commit hop.
- lib/reader/ocr_storage_io.dart, _directory: hashes the whole original PDF (sha256.bind over the file) on the UI isolate before each OCR cache read and write, which is once for each recognized page.
- lib/reader/ocr_storage_io.dart, readOcrCache and writeOcrCache: jsonDecode or jsonEncode and sha256 of a whole hOCR page on the UI isolate, and renameSync.
- lib/appearance/cities.dart, CityCatalog.search, called from lib/appearance/city_search.dart on each keystroke: filters and sorts about 34,000 cities on the UI isolate.
- lib/catalog/covers_io.dart, DiskCovers.load: sha256 of the account key for each cover. This is one short string. Add the engine rule 1 comment that says why it stays inline.

Target design:
- The records store does its whole-store work (replay, snapshot and legacy decode) in one off-isolate hop for each account read, and returns plain maps through Isolate.exit.
- The reader saves change sets as Playback does. ReaderSession gives the store the resumes and bookmarks changed since the last save, and the store adds a reading change-set path beside save.
- The OCR store makes sure of the original PDF digest once for each opened document, off the UI isolate, and keeps the result while the document is open. hOCR encode, decode and hashing run off the UI isolate. The rename is asynchronous.
- City search runs off the UI isolate. The search page shows the latest result and drops a stale one.

Owned files: lib/playback/store.dart, lib/playback/database.dart, lib/sync/journal.dart, lib/reader/session.dart (save path only), lib/reader/ocr_storage_io.dart, lib/appearance/cities.dart, lib/appearance/city_search.dart, lib/catalog/covers_io.dart, and their tests. Order: after boo-l5x3 (same store files) and t9-112h (same session file).

## Acceptance Criteria

No *Sync file call runs on the UI isolate outside tests and invariant checkers. Each remaining inline CPU step has a comment that says why the hop costs more than the work. A reader page turn sends a change set with one resume, not the whole reading snapshot (test). Opening two OCR pages of one PDF hashes the original once (counting test). A city search keystroke does not filter on the UI isolate (test).

## Notes

**2026-11-07T21:40:02Z**

From boo-xifx (merged 49edfd5): LocalResumeStore.read() still builds and deep-copies the whole snapshot on the UI isolate when an account binds or refreshes, and the startup journal replay and the SharedPreferences fallback work on the whole store there. Per-second saves are now small change sets and are not affected.

**2026-11-07T21:55:32Z**

From boo-um68: shelf grouping, the catalog sort in buildBooks and search() run on the UI isolate, now once per catalog list or per keystroke.
