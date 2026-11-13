---
id: boo-f4xm
status: closed
deps: []
links: [boo-s11s, boo-n7no, t4-kdc8]
created: 2026-11-12T23:41:00Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Move the sync transport out of the playback store and let writers register with the store

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: confirmed. lib/playback/store.dart (2,109 lines) owns durable storage, damage set-aside, the plugin wire protocol (451-637), writer baselines, and the value formats of each domain. lib/sync/coordinator.dart:166-168, 225-235 and 294-299 repeat the sequence "flush each writer by name, sync, refresh each stale writer" in three places. A missed flush already caused finding F2 of boo-3oq0. Move the transport into lib/sync as a module that calls named store operations: pending uploads, acknowledge, receive a page with its cursor, take server copies. The store exposes "this domain is behind" as a listenable, and each writer registers its flush once. Move the address and value codec of each domain next to HistoryEvent and Bookmark.


## Notes

**2026-11-13T02:57:00Z**

Astra-only continuation: lead node:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-boo-f4xm-astra-20261112-1; child thread:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-boo-f4xm-astra-20261112-1; clientRequestId bookfin-boo-f4xm-astra-20261112-1. Lead uses codex/gpt-6-astra reasoningEffort xhigh; fresh reviewer uses the same model with high. Base d5b1686db9b09c30770a0a39a091164be551434c. Required checks and integration remain pending.
## Implementation evidence

Ticket lead worktree: `/Users/alexispurslane/.t3/worktrees/bookfin/t3-466ed0a2`, current branch `t3/extract-sync-transport` (initially `t3/466ed0a2`, renamed by T3), base `d5b1686db9b09c30770a0a39a091164be551434c`. Initial branch, HEAD, and status were inspected; the checkout was clean. The lead did not create, reset, switch, merge, or close a checkout or ticket.

The chosen registered-writer model is implemented without a product fork:

- `lib/sync/transport.dart` owns the existing plugin exchange, response checks, discovery limits, and server-copy lookup. It calls the durable owner's `pendingUploads`, `acknowledge`, `discoveryCursor`, `receivePage`, and `takeServerCopies`. Upload snapshots are detached from retained actions, with nonempty snapshot copying in the store's existing worker mechanism.
- `LocalResumeStore` owns acknowledgment, atomic page-and-cursor saves, filtering and adopting differing server copies, and the account/domain stale signals. It never hands transport mutable journal internals.
- Playback and ReaderSession each register their flush and refresh with their domain store once, at construction, and unregister at teardown. The coordinator flushes registered writers and refreshes only stale writers bound to its account. Failed refreshes remain stale and independent refreshes continue. The reader changes are limited to this lifecycle wiring; PDF behavior is unchanged.
- `lib/playback/record_codec.dart`, beside HistoryEvent, Bookmark and place codecs in `records.dart`, owns record-address flattening, snapshot projection, known-domain/value validation, recoverable legacy records, and resume-address construction. Existing format and migration tests exercise the extraction.
- Direct production and test call sites use `RecordTransport`. Coordinator fixtures replace only the exchange and use real store registration/invalidation. The queue changes through `4f36c1b7` were reviewed: an expected save Exception stays the writer's save status; an Error still reaches its caller. No new background uploading, transfer batching, journal snapshots, history expiry, or writer unification was added.

Red-green evidence: `nix develop --command bash -c 'flutter test test/sync/writer_registration_test.dart --reporter expanded'` first failed both new tests with the expected missing uploaded bookmark after a failed local save and storage recovery. Both passed after registration, with no writers supplied to RecordSync. Further tests exercise unregistering, current-account filtering, narrow notifications, and detached pending uploads. Logs: `/tmp/boo-f4xm-red.log`, `/tmp/boo-f4xm-green.log`.

Affected analysis: `nix develop --command bash -c 'flutter analyze --no-pub lib/playback lib/sync lib/reader/session.dart lib/main.dart test/sync test/playback/incremental_save_test.dart test/playback/opened_place_test.dart test/durability/record_store_test.dart test/reader/reading_moves_test.dart test/research/journal_growth_measurement_test.dart test/settings/screen_test.dart'`: no issues, 6.7 seconds. Dart formatting and `git diff --check` pass.

Focused checks: `nix develop --command bash -c 'flutter test --no-pub --concurrency=4 test/playback test/sync test/durability test/reader/persistence_test.dart test/reader/records_test.dart test/reader/reading_moves_test.dart test/reader/pdf_preferences_store_test.dart --reporter expanded'`: 798 passed, 2 skipped, 33 seconds. Skips are the ordinary-account real-plugin round trip and durable plugin-upgrade integration fixtures, requiring `tool/sync_fixture.py` and `tool/plugin/prove.py` in their pinned environments. Log: `/tmp/boo-f4xm-focused-final.log`.

New relevant finding: `t4-kdc8` tracks the existing large wire-payload JSON work on the UI isolate, which remains after the protocol extraction. Its work must coordinate with boo-s11s. No timing measurement or device claim is made here. The parent owns coverage, mutation testing, final integration, and ticket closure.

Final boundary review before the fresh reviewer: removed the obsolete aggregate stale-domain query/report so the store's domain signals are the only invalidation interface. `receivePage` now guards against a cursor behind the saved cursor before changing records. `flushWriters` starts every independent flush through `Future.sync`, so a synchronous bug does not skip another writer's save, and still propagates the bug after all flushes finish. Both new tests first failed for those actual missing behaviors (6 passed, 2 failed in `/tmp/boo-f4xm-boundary-red.log`). The final focused boundary, stale-signal, coordinator-refresh, transport, and server-copy run passed 55 tests in 1 second (`/tmp/boo-f4xm-boundary-green.log`).

The first whole Flutter run passed 3,120 tests, with 25 skips, in 3:19 (`/tmp/boo-f4xm-full.log`). A final whole run is required after the boundary fixes. The parent has separately integrated Speech changes and is fixing the known EPUB page-source ordering flake; this worktree keeps its requested base and does not duplicate those edits.

Required checks at the reviewed commit `4e12b94c84be94f4e8fddfe1a51957f2e8dbf892`:

- Affected analysis, using the exact command above: no issues in 4.0 seconds (`/tmp/boo-f4xm-analyze-final.log`).
- `nix develop --command bash -c 'flutter test --no-pub --concurrency=4 --reporter expanded'`: 3,122 passed, 25 skipped, no failures, 2:55 (`/tmp/boo-f4xm-full-final.log`). Skips comprise opt-in EPUB/PDF benchmarks and corpus runs, seven unavailable downloaded trial books, the journal-growth measurement, and the two external plugin integration fixtures. No app/device run is claimed.
- The reviewed code has no unresolved fork. Every build/test command had ended before the authorized read-only Astra review.

## Review and resolution

The one fresh reviewer used `codex/gpt-6-astra` with `reasoningEffort: high`, shared isolation, async mode, and role review. `orchestrator_capabilities` was called once before launch. Client request ID: `boo-f4xm-review-astra-20261112-1`. Task ID: `node:delegated-task:command%3Amcp%3Ad512c24f-1af5-4931-a826-2c68713b168a%3Adelegate-task%3Aboo-f4xm-review-astra-20261112-1`. Thread: <t3-thread://v2/38d3e8fa-8572-4c2a-8a3b-2eb7c344dfce/thread:delegated-task:command%3Amcp%3Ad512c24f-1af5-4931-a826-2c68713b168a%3Adelegate-task%3Aboo-f4xm-review-astra-20261112-1>.

The reviewer read the entire 37-file base-to-head diff, ticket, design skill, and reviewer brief. They made no edits and ran no builds or tests. Their separate verdicts were correctness pass, ticket fulfillment changes required, and software design changes required. They found no new correctness defect; their only finding was F1 below. They inspected the lead's logs rather than executing verification themselves.

F1 (medium, accepted): incremental listening and reading saves and conflict-created bookmarks still constructed domain addresses and payloads in the store, while snapshot conversion constructed them in the codec. This left an address-format change spread over several paths. The finding follows the user's single-owner rule, Ousterhout's information hiding/change amplification, and Muratori's rule to keep a concept's rules together.

Lead resolution: `recordChanges` now encodes both writers' detached change sets in `record_codec.dart`, preserving null deletions and each domain's existing collection/action order. `resumeBookmarkRecord` owns bookmark address and payload conversion, including listening position fields and reading resume copies. Snapshot flattening, incremental changes, conflict bookmarks, and resume lookup all use the codec's single private address encoder. The store keeps conflict selection, bookmark identity/title policy, journal mutations, and transaction ownership. Journal validation already guarantees string address parts and string-keyed value maps, so the extracted typed arguments preserve accepted data. This is a pure extraction under the existing persistence, migration, and conflict tests; it introduces no new user-visible behavior or product fork.

The lead fixed F1 directly. No fixer or second reviewer was launched. The original review verdicts remain recorded above; the fix is supported by the lead's diff inspection and the post-fix checks below, not a claimed re-review.

Live plugin compatibility and upgrade behavior remain unverified because their external fixtures were skipped. Device behavior, coverage, and mutation testing were not run by this lead or reviewer; the parent owns those checks. The existing large-payload work remains tracked in `t4-kdc8`.

## Post-fix verification

- The focused command recorded above passed 800 tests with 2 skipped, no failures, in 42 seconds (`/tmp/boo-f4xm-f1-focused.log`). This includes the two boundary tests added after the earlier 798-test run. The skipped tests are the two external plugin fixtures described above.
- The affected analysis command recorded above found no issues in 3.4 seconds (`/tmp/boo-f4xm-f1-analysis.log`).
- `nix develop --command bash -c 'dart format lib/playback/record_codec.dart lib/playback/store.dart'`: 2 files checked, 0 changed, in 0.04 seconds (`/tmp/boo-f4xm-f1-format.log`). `git diff --check` passed.
- `nix develop --command bash -c 'flutter test --no-pub --concurrency=4 --reporter expanded'`: 3,122 passed, 25 skipped, no failures, in 3:05 (`/tmp/boo-f4xm-f1-full.log`). Skip categories are unchanged from the reviewed run.

All required commands finished successfully, one heavy command at a time. Flutter test concurrency never exceeded four in these final runs. F1 is resolved with the extracted ownership and the checks above; no findings or product forks remain unresolved. The parent still owns integration, ticket closure, coverage, and mutation testing. This ticket remains in progress until the parent integrates it.


## Integrated verification, 2026-11-12

Integrated on main through f84593f6. The parent ran the combined full Flutter suite through the project Nix dev shell: `flutter test --no-pub --concurrency=4 --reporter expanded`. Result: 3,196 passed, 25 skipped, zero failures, 2 minutes 30 seconds. Log: /tmp/bookfin-astra-integrated-final.log. Affected analysis found no issues: /tmp/bookfin-astra-integrated-analysis.log. The command exited successfully and git diff --check passed.

This verifies the combined PDF visibility/History corrections, sync transport and writer registration, and catalog freshness changes. Existing external plugin fixtures and opt-in conditions remain skipped; this is not live plugin or Android acceptance. Coverage and mutation testing remain with the orchestrator after user acceptance. The parent closes this ticket after integration and the successful combined suite.
