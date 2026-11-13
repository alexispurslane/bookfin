---
id: boo-7z9a
status: closed
deps: [boo-jlhy]
links: [td-6hd7, boo-8xyn]
created: 2026-11-12T23:41:00Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Store the catalog corrections and hidden libraries of the user outside the server catalog cache

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: confirmed. `CatalogCache` (lib/catalog/store.dart:33-53) holds the entries of the server together with the edits of the user (book links, recording links, book details, file orders) and the hidden libraries. A refresh carries them forward only from the in-memory cache (lib/catalog/controller.dart:657-676), so any refresh that runs while the cache is null drops them. td-6hd7 is one instance. Each correction also decodes, digests, encodes and rewrites the whole catalog (controller.dart:820-852). Put the choices of the user in a small atomic store of their own. The server catalog becomes a derived cache that can be dropped, and the build takes both as inputs. This makes the td-6hd7 class of bug impossible.


## Astra implementation scope

Atomic catalog files from boo-jlhy are integrated and verified (3,252 passes, 25 skips). Build the ticket's settled model: durable account-scoped user corrections and hidden libraries have their own small atomic store; the server catalog is a replaceable cache, and library construction takes both. Preserve legacy choices before removing them from old catalog files or preferences. A missing, damaged or refreshed server cache cannot erase saved choices. Existing unreadable legacy catalog text must be kept aside and reported before replacement; td-6hd7 tracks that linked behavior and depends on this work. The parent will assess both tickets for closure.

Implementation and direct fixes: codex/gpt-6-astra with reasoningEffort xhigh. Exactly one fresh read-only reviewer: same model, high. Required evidence includes real-file reopen/migration/failure ordering, account isolation, corruption preservation, refresh/edit races, no full catalog persistence for a small correction, all catalog/app/durability tests, affected analysis and full Flutter suite at concurrency two. Preserve one-hour freshness, unchanged-content reuse and narrow signals. No sync format changes, device work, coverage, mutation, deployment or closure by the child.

## Delegated task

Original base: 515f431c6d26797a6c1f511b26769cbd373174a3.
Client request ID: bookfin-boo-7z9a-astra-20261113-1
Task ID: node:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-boo-7z9a-astra-20261113-1
Child thread ID: thread:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-boo-7z9a-astra-20261113-1
Thread: <t3-thread://v2/38d3e8fa-8572-4c2a-8a3b-2eb7c344dfce/thread:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-boo-7z9a-astra-20261113-1>
Launch returned running on codex/gpt-6-astra with reasoningEffort xhigh. Stage and branch not yet reported. Completion delivery is automatic.

## Implementation, 2026-11-13

Ticket lead works in the existing T3-bound `t3/preserve-catalog-edits` checkout, starting at `515f431c6d26797a6c1f511b26769cbd373174a3`. No checkout was created, reset or switched. This ticket and linked td-6hd7 remain in progress for parent integration and closure.

The authoritative account choices now live in a separate small record: book links, recording links, book details, file orders, hidden libraries, and a retained-damage notice. Native storage uses the existing flushed temporary-file/rename primitive. Browser storage uses a separate preference record. Version 3 server snapshots contain no choices. The catalog controller owns ordering and visible adoption; widgets report actions.

`LocalCatalogStore` serializes each account's reads, writes and migrations. It commits extracted choices before replacing a legacy catalog or removing a retained preference. A committed choice record wins over both legacy sources, including an explicit reset to empty corrections. Background migration discovers inactive native accounts off the UI isolate and enumerates retained preference accounts; browser migration also extracts inactive choices. A discovery or account failure does not strand accounts from the other source. The existing after-first-frame migration hook is unchanged.

Unreadable legacy text and invalid UTF-8 bytes are retained before replacement. Copies use content-derived names, so retries cannot overwrite different damaged data. Readable corrections can be salvaged from a catalog whose entries cannot build. Unknown or malformed committed choice records are retained and produce a durable notice; old legacy edits never replace those newer choices. A failed preservation or choice commit prevents replacement. The current catalog can browse after a successful server refresh while the retained-data notice remains.

Corrections rebuild books from already decoded entries off the UI isolate and write only choices. They do not decode, digest, encode or write the server catalog. Changed visibility uses known entries and writes only choices; showing a library whose complete data is absent fetches it. Completeness includes empty libraries. Saving an unchanged selection remains a manual refresh. The selector uses the controller's saved-choice result so an offline local save can close it without claiming server verification. Ordinary launch/manual refresh, one-hour resume freshness, unchanged-content reuse, failed/cancelled/superseded-write recovery, access-denial recovery and narrow listenables retain regression checks.

The controller still retains its existing decoded entries, encoded server text and built library. On corrections it passes decoded entries to the worker instead of sending text to decode; eliminating the retained copies or introducing a long-lived worker is not claimed here. boo-8xyn remains separate. The worker-crossing test now checks the intentional decoded-entry input and independent choice persistence; refresh and access-denial crossing tests remain in place.

Settings and callers were inspected. Reset catalog corrections still resets only corrections; hidden libraries remain. Clear data is specified in the product plan but its implementation remains the separate open boo-xyrl task; this change adds no Clear data operation and changes no destructive product policy. No sync protocol, record import/export, reader navigation, plugin or broad startup scheduling changes.

## Verification scope

Real-file tests use fresh store/controller instances, exact retained bytes, temporary-file conflicts and controlled completion barriers. No sleep-based race tests were added. These are automated durability regressions, not an operating-system process-kill test or Android latency/battery evidence. No devices, coverage, mutation campaign or benchmark was run. The existing full-app browser PDF `dart:ffi` blocker t7-3j9c remains outside scope; only the catalog storage compile target is required here.

Required-check results and the one fresh Astra review will be appended before handoff.

## Red-green evidence

The initial missing dependency setup was resolved with `nix develop --command flutter pub get` (`/tmp/boo-7z9a-pub-get.log`). A setup or compiler failure is not counted as a meaningful red.

| Reproduced behavior | Red result | Log |
| --- | --- | --- |
| Missing/corrupt cache loss, legacy overwrite, unreadable-byte loss, large correction write | 0 passed, 5 failed | `/tmp/boo-7z9a-red-loss.log` |
| Hiding a known library still fetches server entries | 10 passed, 1 meaningful failure; 2 byte-list matcher mistakes were corrected | `/tmp/boo-7z9a-red-ordering.log` |
| Saving existing choices after reopening reads the server catalog | 0 passed, 1 failed | `/tmp/boo-7z9a-red-reopen-work.log` |
| Missing/unknown choice fields and legacy entries that cannot build | 0 passed, 3 failed | `/tmp/boo-7z9a-red-unreadable.log` |
| Empty-library completeness is not remembered | 0 passed, 1 failed | `/tmp/boo-7z9a-red-empty-library.log` |
| Inactive native choices remain tied to their cache | 0 passed, 1 failed | `/tmp/boo-7z9a-red-native-inactive.log` |
| Discovery failure and malformed identity strand other accounts | 0 passed, 2 failed | `/tmp/boo-7z9a-red-migration-errors.log` |
| Offline choice-save navigation and unchanged-selection refresh behavior | 0 passed, 2 failed | `/tmp/boo-7z9a-red-selector.log` |
| Browser migration omits inactive choices | 0 passed, 1 failed | `/tmp/boo-7z9a-red-browser.log` |
| Temporary read errors are mistaken for damage; denial recovery lacks choices | 0 passed, 3 failed | `/tmp/boo-7z9a-red-io-guard.log` |

Focused commands used `nix develop --command flutter test --no-pub --concurrency=2 ... --reporter expanded`, with the file/name filters visible in each log's test names. The first five all passed in `/tmp/boo-7z9a-green-loss.log`. The final storage run (`test/catalog/choices_test.dart test/catalog/file_store_test.dart`) passed 52 tests in `/tmp/boo-7z9a-green-io-guard.log`; all 31 new choice tests and all 21 existing storage tests passed. The selector/catalog-signal run passed 125 tests in `/tmp/boo-7z9a-green-selector.log` before the last three storage tests were added. The final affected run below includes every current catalog and app test.

The final read-error correction separates malformed bytes from failed disk access. Malformed bytes are retained and reported; an I/O failure leaves the committed choice record and legacy source untouched for retry. A successful saved access denial also adopts account choices after an earlier read failed. No contract failure is caught for recovery.

## Required checks before review

- `nix develop --command flutter test --no-pub --concurrency=2 test/catalog test/app test/durability test/sync/durability_test.dart test/foundation/derived_store_test.dart test/appearance/preferences_test.dart test/reader/reading_speed_test.dart test/reader/pdf_preferences_store_test.dart --reporter expanded`: 522 passed, zero failures/skips, 24 seconds. `/tmp/boo-7z9a-affected-final.log`.
- `nix develop --command flutter analyze --no-pub lib/catalog lib/main.dart test/catalog test/app test/compile/catalog_store.dart`: no issues. `/tmp/boo-7z9a-final-analysis.log` also records formatting the 13 affected Dart files before analysis.
- The complete suite before the final read-error guards passed 3,313 tests with 26 existing skips and zero failures in 4:30. `/tmp/boo-7z9a-full-before-io-guard.log`. The guards added three tests, so the final complete suite is rerun after them.
- Work-count tests show that a small correction writes no server-catalog key, leaves its exact text unchanged, and writes fewer than 2,000 UTF-8 bytes for the 80-entry fixture's choice. Existing-choice reads/writes after a fresh store reopen never read the server-catalog key. Hiding or showing a completely cached library sends no catalog request. These are operation/byte counts, not Android performance measurements.
- All heavy commands ran sequentially with Flutter concurrency at most two. No shared process was stopped. Intermediate development compile/analysis errors were corrected before the reported green checks; no failed check is presented as passing.
- `nix develop --command dart format --output=none --set-exit-if-changed lib/catalog/store.dart lib/catalog/controller.dart lib/catalog/catalog_files.dart lib/catalog/catalog_files_io.dart lib/catalog/screen.dart test/catalog/choices_test.dart test/catalog/controller_test.dart test/catalog/file_store_test.dart test/catalog/catalog_signals_test.dart test/catalog/library_visibility_test.dart test/catalog/store_test.dart test/catalog/screen_test.dart test/compile/catalog_store.dart`: 13 files checked, zero changes. `/tmp/boo-7z9a-final-browser-format.log`.
- `nix develop --command flutter build web --no-pub --target test/compile/catalog_store.dart`: passed after the final storage guards, exercising the choice read/write, cache write/read and migration import boundary. Same log, 20.8 seconds. Existing nonfatal secure-storage Wasm and font diagnostics remain. The known failing full PDF browser build was not run.
- Final `nix develop --command flutter test --no-pub --concurrency=2 --reporter expanded`: 3,316 passed, 26 existing opt-in/external-fixture skips, zero failures, 5:00. `/tmp/boo-7z9a-full-final.log`. All owned commands completed. Only explanatory comments changed while this final run was active; implementation and tests remained unchanged.
- The linked td-6hd7 regression is fully proved within the requested automated real-file scope: malformed JSON, invalid UTF-8, failed book construction, failed retention, successful refresh, and reopening all preserve recoverable bytes. Actual process killing and Android acceptance are not claimed. Parent integration and closure remain outstanding.

The one fresh read-only Astra reviewer is the remaining gate. No second review, merge, push, PR, deployment, coverage or mutation work is authorized to this lead.


## Single fresh review and fix stage, 2026-11-13

The authorized reviewer used codex/gpt-6-astra at high effort, shared isolation, async review mode. It inspected the complete original-base-to-442f3601f5eac2bd0f42c8114688de8c1c1ef0f4 diff, callers, project rules and saved logs without edits, builds, tests or children. Its independent correctness, fulfillment and design assessments were each `changes-required`, with no material assessment marked `unverified` and no user fork. The review is preserved as those original verdicts; the lead's resolutions below are not a second review or a claim that the reviewer passed the later fix.

Reviewer: <t3-thread://v2/38d3e8fa-8572-4c2a-8a3b-2eb7c344dfce/thread:delegated-task:command%3Amcp%3A308dda10-6fe2-40a7-9f97-21b2bb749412%3Adelegate-task%3Aboo-7z9a-review-astra-20261113-1>

| Finding | Trigger and reviewed location | Resolution and evidence |
| --- | --- | --- |
| R1, high, correctness/fulfillment | An obsolete account read waits for a former write, captures the newer account's generation, and then adopts the former account's choices. `controller.dart:647`. | Capture account identity and request identity before the first wait; the common adoption boundary checks both before and after asynchronous work. The controlled overlapping sign-in/write/read test verifies Bob's visible hidden libraries and reopened durable choices remain Bob's. |
| R2, medium, correctness/fulfillment | Access recovery commits hidden libraries, then fails its cache write; unchanged retry reuses books built with the former visibility. `controller.dart:946`. | Choice adoption now installs a coherent view of the current cache before further cache persistence. The real-file test blocks only the cache temporary-file path, proves committed visibility and the state invariant after failure, retries, and compares the fresh reopened view. |
| R3, medium, correctness/fulfillment | One native file-read failure discards every successful native account discovery. `catalog_files_io.dart:45`. | Discovery returns usable keys alongside its first failure, continues after individual file errors, and preserves partial results on enumeration failure. The migration owner migrates independent accounts before reporting that failure. The test uses a real unreadable file (chmod 000, restored in finally), verifies Bob's independent native choices commit, and retries after restoring access. |
| R4, medium, correctness/fulfillment | Migration discovers damaged retained preferences after the active choices restored; an unchanged refresh never reports the new notice. `store.dart:442`, `controller.dart:890`, `main.dart:286`. | The catalog reconciles the small choice notice through its account write queue after migration and during response adoption. Tests preserve the exact damaged text, report the notice with and without a server refresh, retain library identity, and show that direct reconciliation reads only the choice key with no network request. |
| D1, high, design; User/Ousterhout | Caller-specific adoption steps independently manage account identity, choices, derived books and notice reconciliation. `controller.dart:546`. Cost: each new adoption path must rediscover these ordering rules and the reuse conditions. | One guarded choice-adoption operation owns account/request identity and the derived view; edits, restore, refresh, visibility and notice reconciliation use it. A prepared view or explicitly justified reuse can be supplied; otherwise the owner rebuilds from the current cache. Snapshot adoption uses the same identity guard. The on-demand invariant checker now verifies books agree with current choices and cache, including grouping and file order. R1/R2/R4 regressions prove the associated failure paths. |
| D2, medium, design; Ousterhout/Muratori | The all-keys-or-exception discovery interface cannot express independent-account progress. `catalog_files.dart:24`. Cost: the migration owner must lose successful work or bypass file ownership. | The small `CatalogDiscovery` result carries keys plus the first I/O failure. Filesystem mechanics remain in DiskCatalogFiles and migration policy remains in LocalCatalogStore. R3 proves real partial progress and reporting. No generic storage framework was added. |

All four behavior findings were reproduced before changing production code with `nix develop --command flutter test --no-pub --concurrency=2 test/catalog/choices_test.dart --name 'an obsolete account restore|a failed access recovery|one unreadable native file|background legacy damage' --reporter expanded`: zero passed, four expected failures (`/tmp/boo-7z9a-review-red.log`). The identical command then passed all four (`/tmp/boo-7z9a-review-green.log`). An initial literal-name filter matched no tests; it was corrected to the regex name filter and is not counted as a red.

The first broader fix run had 524 passes and two failures (`/tmp/boo-7z9a-review-affected.log`): the empty-library work-count regression caught a duplicate worker call, and the joined-background-refresh widget regression caught network startup delayed behind prior writes. The duplicate was removed using the worker's explicit reuse result; network requests remain independent of pending writes and notice reconciliation occurs at ordered response adoption. The existing tests were not weakened. The focused command `nix develop --command flutter test --no-pub --concurrency=2 test/catalog/choices_test.dart test/catalog/catalog_signals_test.dart test/catalog/library_view_test.dart --reporter expanded` then passed 132 tests (`/tmp/boo-7z9a-review-focused.log`).

The reviewer also noted that version 1 native migration had static evidence but no real-file proof. A supplemental real-file test now migrates a version 1 selected-library fixture, drops its cache, reopens, and proves its correction survives while no libraries become hidden. Six tests were added in this fix stage: the four review cases, direct notice reconciliation, and version 1 native reopen. The choice suite now has 37 tests.

The post-first-frame migration schedule is preserved. Its completion now reconciles notices through the catalog controller, including after another account's recoverable migration failure. Assertion failures bypass this recovery path. No second reviewer was started, and no ticket was closed.


## Final fix verification

- `nix develop --command flutter test --no-pub --concurrency=2 test/catalog test/app test/durability test/sync/durability_test.dart test/foundation/derived_store_test.dart test/appearance/preferences_test.dart test/reader/reading_speed_test.dart test/reader/pdf_preferences_store_test.dart --reporter expanded`: 528 passed, zero failed/skipped, 23 seconds. `/tmp/boo-7z9a-review-affected-final.log`. This final run follows the last account-guard refactor; all required affected groups are included.
- `nix develop --command dart format --output=none --set-exit-if-changed lib/catalog/store.dart lib/catalog/controller.dart lib/catalog/catalog_files.dart lib/catalog/catalog_files_io.dart lib/catalog/screen.dart lib/main.dart test/catalog/choices_test.dart test/catalog/controller_test.dart test/catalog/file_store_test.dart test/catalog/catalog_signals_test.dart test/catalog/library_visibility_test.dart test/catalog/store_test.dart test/catalog/screen_test.dart test/compile/catalog_store.dart`: 14 files, zero changes. `/tmp/boo-7z9a-review-analysis-format.log`.
- `nix develop --command flutter analyze --no-pub lib/catalog lib/main.dart test/catalog test/app test/compile/catalog_store.dart`: no issues. `/tmp/boo-7z9a-review-analysis-format.log`. Format and analysis ran sequentially in one Nix dev-shell command.
- `nix develop --command flutter build web --no-pub --target test/compile/catalog_store.dart`: passed, 21.0 seconds. `/tmp/boo-7z9a-review-browser.log`. The existing nonfatal secure-storage Wasm/font diagnostics remain; the known full-app PDF blocker was not rerun.
- `git diff --check`: passed. All named-path changes stay within catalog durability, its startup completion hook, related regressions, and the two ticket records. The combined batch protocol work is unchanged.

- Final complete `nix develop --command flutter test --no-pub --concurrency=2 --reporter expanded`: 3,322 passed, 26 existing opt-in/external-fixture skips, zero failures, 4:48. `/tmp/boo-7z9a-review-full.log`. Implementation and tests were frozen throughout; only ticket evidence changed. The full run includes all 37 choice tests and 21 file-storage tests. All owned commands and the sole reviewer finished.

All R1–R4 and D1–D2 findings are resolved with the evidence above. There are no unresolved forks or material unverified assessments. The linked td-6hd7 retain-and-report requirement is now fully proved within the assigned automated real-file scope, including the post-restore migration notice path. Both tickets remain open for parent integration, acceptance, hardening and closure. No OS process-kill or Android behavior/performance proof is claimed. The lead is ready for integration after the named-path fix commit and clean-worktree check.

## Parent integration and closure, 2026-11-13

The parent inspected the complete original-base-to-8a28e785 diff, the fresh review, its four meaningful failing regressions and their passing results, migration/startup callers, and the final verification logs. R1–R4 and D1–D2 have recorded resolutions and regression evidence; this is parent integration inspection, not a second independent review. The child's clean branch and two commits were verified before integration.

Integrated 442f3601 as 7c4fa38f and 8a28e785 as c475c4f3b229dfb115a76ab578b7e0ccc90081b1 on main. The only conflict was the ticket's parallel launch and implementation notes; both were retained. All affected production and test files match the child's final commit exactly. `git diff --check 3c092a78 HEAD` passed.

- `nix develop --command flutter test --no-pub --concurrency=2 --reporter expanded`: 3,353 passed, 27 existing opt-in/external-fixture skips, zero failures, 4:41. Log: `/tmp/boo-7z9a-integrated-full.log`. The combined suite includes the catalog, app and durability regressions plus intervening integrated work.
- `nix develop --command dart format --output=none --set-exit-if-changed` with the same 14 Dart paths listed above: 14 checked, zero changes. Log: `/tmp/boo-7z9a-integrated-format.log`.
- `nix develop --command flutter analyze --no-pub lib/catalog lib/main.dart test/catalog test/app test/compile/catalog_store.dart`: no issues, 3.5 seconds. Log: `/tmp/boo-7z9a-integrated-analysis.log`.
- `nix develop --command flutter build web --no-pub --target test/compile/catalog_store.dart`: passed, 21.3 seconds. Log: `/tmp/boo-7z9a-integrated-browser.log`. Existing nonfatal Wasm/font diagnostics remain. This proves the changed catalog boundary compiles; the full-app PDF browser blocker t7-3j9c remains outside scope.

All parent commands finished and ran sequentially. Close boo-7z9a and td-6hd7 for their integrated implementation and automated retain-and-report evidence. Device acceptance remains blocked by t1-dth0; no Android latency, live browser behavior, actual process kill, coverage, mutation, push or deployment claim is made. Acceptance and broader hardening remain separate project work. No catalog product decision is pending.
