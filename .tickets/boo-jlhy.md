---
id: boo-jlhy
status: in_progress
deps: []
links: []
created: 2026-11-12T23:41:00Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Keep the saved catalog in its own file, outside the shared preferences DataStore

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: confirmed code path. The DataStore rewrite behavior comes from its documentation and was not measured here. lib/catalog/store.dart:157-169 writes the whole saved catalog (3.9 MB for 1478 books, measured in boo-8v53) through `SharedPreferencesAsync`. On Android that API keeps every key of every caller in one DataStore file, and DataStore rewrites the whole file for each edit. lib/reader/reading_speed.dart:133 writes a short value on forward page turns, so each such turn rewrites the multi-megabyte file. The first preference read at launch parses the whole file before `runApp`. The catalogs of old accounts stay in the file. Give the catalog an atomic file store of its own (temporary file, then rename) with the IO off the UI isolate. Move the old key once, then delete it. Related: boo-8v53, t4-4d21.



## Astra implementation launch

Original review base: 2ab1a6185456761e1c4d10ff06263c17711e28e3. Main baseline: 3,231 passing Flutter tests, 25 existing skips, clean affected analysis. Separate T3 worktree; implementation/direct fixes use codex/gpt-6-astra with reasoningEffort xhigh. One fresh read-only shared-worktree reviewer is authorized on the same model with reasoningEffort high; no other stage agents. Parent owns integration and closure. The brief includes atomic writes, failure-safe legacy migration (including inactive accounts), durable reopen evidence, and preservation of catalog freshness/corrections without the separate correction-store redesign.

Client request ID: bookfin-boo-jlhy-astra-20261113-1
Task ID: node:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-boo-jlhy-astra-20261113-1
Child thread ID: thread:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-boo-jlhy-astra-20261113-1
Thread: <t3-thread://v2/38d3e8fa-8572-4c2a-8a3b-2eb7c344dfce/thread:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-boo-jlhy-astra-20261113-1>
Launch status: running; stage not yet reported. Completion will be delivered automatically.

## Implementation and storage boundary

Implementation starts at `2ab1a6185456761e1c4d10ff06263c17711e28e3` in the T3-bound branch `t3/7c00aac7`. The ticket remains in progress; integration and closure belong to the parent.

`LocalCatalogStore` remains a text-only `CatalogStore`. The controller and worker still own catalog JSON, content digests, freshness, correction meaning, hidden libraries, and canceled/superseded-write recovery. No controller changes.

Native catalog files live in `bookfin-catalog` beside the application-private media directory returned by the existing host channel. Each filename is the SHA-256 of the exact legacy account key. Account URLs and user identifiers never become path components. Disk reads, writes, and conversion between text and UTF-8 bytes run in `Isolate.run`. A write flushes a `.partial` file, then renames it over the committed file. Reads ignore partial files and report errors other than a missing path.

The existing derived-value store cannot be used here: its read treats every filesystem error as a missing value, and its values are explicitly disposable. Catalog text also contains user corrections. The new filesystem boundary keeps that error distinction without changing the catalog domain model or unrelated storage.

The store orders reads, writes, and migration for each account. A committed file wins over a legacy value. A failed operation releases its queue position but still fails for its caller. A failed migration leaves its legacy key for retry. Preference removal follows a successful file commit; if removal fails, the next launch reads the committed file. Concurrent migration calls join the store-owned migration future. One failed account does not prevent attempts for the other accounts. There are no independent in-memory indexes or catalog copies to maintain, and no new contracts or recovery from contract failures.

Restore reads a committed file, or the current account's legacy value when no file exists. It does not scan inactive accounts or contact Jellyfin. The app waits for restore and a frame before starting the store's migration. This also runs while signed out. Background failures reach `FlutterError.reportError`; failed keys retry on the next launch. The store enumerates preference names once because SharedPreferencesAsync has no prefix enumeration API, then reads only `bookfin.catalog.v1.*` values. It never loads all unrelated preference values. Browser builds retain their existing preference store through the conditional filesystem boundary.

## Scope and limitations

- Catalog content and identity are copied without JSON interpretation, including malformed legacy text. Corrections and hidden libraries remain in the same text; boo-7z9a owns their separate-store redesign.
- td-6hd7 remains: after reporting a catalog decode failure, the existing controller can refresh and overwrite unreadable catalog text. This ticket neither interprets catalog JSON nor adds the separate domain recovery policy. Migration itself preserves malformed text and never substitutes an empty catalog.
- Credentials, unrelated preferences, launch scheduling beyond the migration hook, PDF ownership, and personal-record sync are unchanged. No Android/device action, deployment, coverage, or mutation campaign was performed.
- The store has one owner for the application's lifetime. The account queue orders its callers; this is not a multi-process writer protocol.
- The 4,200,000-byte UTF-8 fixture records one catalog-file write and zero catalog-preference writes. Two tiny preference changes cause zero catalog-file reads or writes, and the committed file's bytes and modification time remain unchanged. These are work counts, not device latency, battery, or acceptance measurements.

## Red-green evidence

- `/tmp/boo-jlhy-red-ordinary.log`: the first ordinary-write test failed because the catalog preference still contained `first catalog` instead of being absent. `/tmp/boo-jlhy-green-ordinary.log`: the test passed after file storage.
- `/tmp/boo-jlhy-red-migration.log`: 6 passed, 9 failed with the empty migration operation. Legacy keys remained, required failures were not reported, and no committed migration existed. The two blocked-concurrency cases were excluded from this initial batch.
- `/tmp/boo-jlhy-red-ordering.log`: 15 passed, 2 failed before account ordering. Migration and a concurrent write collided on the same temporary file and rename failed. `/tmp/boo-jlhy-green-migration.log`: all 17 passed after ordering.
- `/tmp/boo-jlhy-red-startup.log`: the startup test found zero migration scans after rendering, rather than one. `/tmp/boo-jlhy-green-startup.log`: it passed after the startup hook. An earlier missing-import compile attempt was corrected before counting this red result. A first fake-clock test arrangement stalled disk completions; only its own Flutter process was interrupted, and the test now runs the disk operation in `tester.runAsync` without sleeps.
- `/tmp/boo-jlhy-storage-final.log`: all 21 tests pass, including real-disk reopen, ordinary replacement, current/inactive accounts, interrupted first migration/replacement, creation/write/rename failures, failed preference removal, both concurrency orders, retry, malformed legacy text, unreadable committed bytes, safe account filenames, offline restoration, and tiny preference independence. Filesystem creation and rename failures are real directory/file conflicts; mid-write interruption is controlled at the filesystem boundary while retaining real partial bytes.

## Verification before review

- `nix develop --command flutter test --no-pub --concurrency=2 test/catalog test/app test/foundation/derived_store_test.dart test/durability/record_store_test.dart test/appearance/preferences_test.dart test/reader/reading_speed_test.dart test/reader/pdf_preferences_store_test.dart --reporter expanded`: 483 passed. Log: `/tmp/boo-jlhy-affected.log`.
- `nix develop --command flutter analyze lib/catalog lib/main.dart test/catalog/file_store_test.dart test/app`: no issues. Log: `/tmp/boo-jlhy-analysis.log`.
- Build/test concurrency is capped at two; heavy commands run one at a time. Host memory free was 66% before the verification runs. The existing Nix/Flutter host emits missing iOS SDK diagnostics while native host tests still pass; no iOS build or device claim is made.
- `nix develop --command flutter build web --no-pub --target test/compile/catalog_store.dart`: passed, exercising the complete catalog store import boundary and its read/write/migration calls. Log: `/tmp/boo-jlhy-web-boundary.log`. Nonfatal existing warnings concern the secure-storage package's Wasm support and CupertinoIcons fonts. Native host tests exercise the IO branch.
- Additional broader check `nix develop --command flutter build web --no-pub`: failed at the unchanged `lib/reader/pdf_outline.dart:10` unconditional `dart:ffi` import. The failing PDF import chain is identical to the original base. New ticket `t7-3j9c` records this separate browser build issue. Log: `/tmp/boo-jlhy-web.log`. The dedicated catalog compile target avoids conflating that existing failure with the new conditional storage imports.
- `nix develop --command flutter test --no-pub --concurrency=2 --reporter expanded`: 3,252 passed, 25 existing skips, zero failures, 4 minutes 23 seconds. Log: `/tmp/boo-jlhy-full.log`.
- Final format check over all seven changed Dart files: zero changes. Final affected analysis, including the catalog compile target: no issues. Log: `/tmp/boo-jlhy-final-checks.log`. `git diff --check` passed. All owned test/build processes finished.

## Review

The single fresh read-only Codex `gpt-6-astra` reviewer at high reasoning effort completed the full diff from `2ab1a6185456761e1c4d10ff06263c17711e28e3` to implementation commit `b0a1bc3a7dd5fce8a8763c41c36cbf158b01db65`. Correctness: pass. Fulfillment: pass. Design: pass. Overall: pass. No findings, required changes, material unverified assessments, or user decisions.

The reviewer inspected production callers, source, named scope documents and the supplied red-green, focused, full-suite, analysis and compile logs. It ran no builds or tests and changed no files. It confirmed that the dedicated catalog browser compile satisfies this ticket's changed import boundary; full browser application compilation remains blocked separately by `t7-3j9c`.

Nonblocking evidence limits: concurrent migration joining and host-directory lookup retry were inspected statically, without direct tests of those two cases. Interruption tests use real partial files and controlled failures, not a process kill. Android latency, battery effects, device acceptance, coverage and mutations remain unverified. These are not claims made by this implementation.

Review thread: <t3-thread://v2/38d3e8fa-8572-4c2a-8a3b-2eb7c344dfce/thread:delegated-task:command%3Amcp%3A30288610-5d9b-43db-993a-0f3afbafb856%3Adelegate-task%3Aboo-jlhy-review-astra-20261113-1>

The final follow-up commit records only this review. Production code and tests remain exactly as reviewed and verified. The checkout's observed branch at handoff is `t3/atomic-catalog-files`; no checkout creation, reset or switch was performed by this child. No second reviewer, coverage, mutation work, push, PR, deployment, integration or ticket closure was performed. The parent owns combined integration verification, acceptance, hardening and closure.
