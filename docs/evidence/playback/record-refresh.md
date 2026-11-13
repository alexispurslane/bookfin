# Record refresh independent of audio commands

Ticket: `boo-2bl9`. Original base: `a72d2043804c336877d6f3ed5ef72f3fd4994cd8`.
Date: 2026-11-13. Parent owns integration, acceptance, hardening, and closure.

## Initial state and scope

The initial checkout was clean at the original base. Worktree:
`/Users/alexispurslane/.t3/worktrees/bookfin/t3-171de35c`.
Branch: `t3/decouple-record-refresh-audio`.
No checkout was created, switched, reset, or removed. The ticket was already
in progress. `tk ready` and `tk dep tree boo-2bl9` showed no dependencies.
The lead read the required project instructions, plans, role brief, and skills.
No `CLAUDE.md` was present in the worktree.

The production change stays in `Playback.refreshPersonalRecords`. The method
adopts durable records directly after local writes finish. It does not enter
the audio command queue or wait for account restoration. It captures the
account generation before waiting. A generation identifies one account binding
lifetime, so leaving A for B and returning to A cannot revive an old request.
The record revision rejects a read that overlaps a new local save or another adopted snapshot.
Closed or unrestored players and failed pending writes reject adoption.
Only an adopted snapshot reaches the store's acceptance operation.

Undo now uses the matching entry in the adopted history. The earlier refresh
kept the old object, which violated the existing Undo invariant. The controlled
regression reproduced that mismatch before the correction. The correction
also clears Undo when received history deletes its entry.

There is no new writer, pending-action inventory, generic queue, or record type.
The store, sync coordinator, reader, settings schema, and unrelated tickets
remain unchanged. There is no Ask-at-Play change or open product fork.

## Caller and mutation audit

| Owner or caller | Finding |
| --- | --- |
| `Playback` registration | Registers its refresh and flush with its existing `RecordWriterHost`. No caller change is required. |
| `LocalResumeStore.refreshWriters` | Awaits each stale writer. Only `acceptSnapshot` can clear staleness. An ordinary exception becomes a refresh failure. A programming error propagates. |
| `RecordSync._sync` | Awaits refresh after complete or incomplete exchanges, then reports the outcome and releases exchange ownership. No detached success path is added. |
| `RecordSync.resolve` and `recoverKept` | Use the same registered refresh. Startup recovery can overlap sync. Adoption advances the existing record revision to reject an older overlapping read. Their outcome and retry rules remain intact. |
| `ReaderSession.refreshPersonalRecords` | Already adopts records directly under account and revision guards. It remains unchanged. |
| Playback load and seek | Capture command generation. The confirmed position and new history are committed together, followed by `_save` before another asynchronous wait. No pre-wait copy of the history replaces the refreshed list. |
| Playback pause and stop | Record their result after the engine wait and generation check. They append to the current history, then save before the next wait. |
| Samples, bookmarks, and history deletion | Their record mutations and `_save` run without an intervening wait. `_save` increments the record revision and retains pending changes before scheduling storage. |
| Binding and close | Binding invalidates account generation and hides unrestored records immediately. Refresh checks that generation before and after storage. Close still owns audio shutdown, flush, and resource release. |
| `Playback.flush` | Its independent local-write contract from `boo-rw9z` remains unchanged. The retained tests still exercise held audio and account-owned retries. |

## Controlled behavior proof

`test/sync/playback_refresh_test.dart` uses real Playback, RecordSync,
RecordTransport, and LocalResumeStore. The server connection is the existing
`BatchApi` fixture. The audio engine and owner storage boundary expose gates.
A gate holds an operation until the test releases it. The five-second watchdog
only detects a dependency on an unreleased gate. It is not a latency target.
No existing timeout or timing threshold changed. The command persistence assertions observe the command's own completed save before any later flush or exchange.

Every case runs with preferences and SQLite. The cases cover:

- Two complete exchanges during each held load, seek, and pause.
- Two rejected-upload exchanges during each held command, while discovery still supplies records and the failed-upload outcome remains visible.
- Received history, bookmarks, another edition's resume, and the open recording's resume. The decoder retains its confirmed 11,000 ms position.
- Command completion and persistence after release. A seek saves the confirmed 18,000 ms in the second source. An unchanged decoder place does not overwrite a received resume.
- Durable reads through a new store, plus a closed and reopened SQLite connection after command completion.
- A pending A-to-B-to-A binding that permits two exchanges without accepting an unrestored snapshot.
- Startup recovery with a held read while sync adopts a newer snapshot. The old read cannot replace that snapshot or change its accepted baseline.
- A held read across account return and close, a local deletion during a held read, and a held local write before refresh.
- Failed pending writes and retry, received deletions, retained Undo, ordinary read failures, and programming errors.

The existing owner-refresh cases cover a position save during a held read.
The existing save-queue and writer-registration cases cover failed account-owned
writes across account return. Existing durability tests cover failed commits and
restart. These tests remain part of the required run.

## Commands and results

Commands run from the worktree above. Builds, tests, analysis, and formatting
use `nix develop`. Flutter concurrency is two. Only one heavy command runs at a
time. Complete logs are saved under `.cache/boo-2bl9/` in this worktree.
The logs stay outside the commit so their raw tool output remains unchanged.

| Run | Exact command | Outcome | Log |
| --- | --- | --- | --- |
| Initial format | `nix develop --command dart format test/sync/playback_refresh_test.dart` | Exit 0. One file formatted. Package resolution warning before the first test fetched dependencies. | `format-initial.log` |
| Initial red attempt | `nix develop --command flutter test --concurrency=2 test/sync/playback_refresh_test.dart --plain-name 'preferences two complete exchanges' --reporter expanded` | Exit 1. Missing constructor argument and wrong Undo getter prevented compilation. This is not meaningful red proof. | `red-held.log` |
| Held-command red | Same command as the initial red attempt, after fixing the test errors. | Exit 1. Load, seek, and pause each leave sync waiting on the unreleased audio gate. All three watchdogs fail. | `red-held-valid.log` |
| Race red | `nix develop --command flutter test --concurrency=2 test/sync/playback_refresh_test.dart --name 'preferences (an unrestored\|a held read\|a local deletion\|refresh waits\|failed pending\|a refresh)' --reporter expanded` | Exit 1. Eight cases fail because the queued refresh blocks or waits for another operation. Close cleanup also starts a second close after its watchdog. | `red-races.log` |
| Corrected close red | `nix develop --command flutter test --concurrency=2 test/sync/playback_refresh_test.dart --plain-name 'preferences a held read cannot adopt' --reporter expanded` | Exit 1. Only the expected watchdog failure remains after cleanup awaits the original close. | `red-close-cleanup.log` |
| First implementation | `nix develop --command flutter test --concurrency=2 test/sync/playback_refresh_test.dart --reporter expanded` | Exit 1. Sixteen pass. Twelve reach an Undo invariant failure after refresh. The invariant call moves to a separate test with no command in flight. | `green-refresh-1.log` |
| Undo red | `nix develop --command flutter test --concurrency=2 test/sync/playback_refresh_test.dart --plain-name 'preferences an adopted history' --reporter expanded` | Exit 1. Undo retains an object outside the adopted history. | `red-undo.log` |
| Refresh green | `nix develop --command flutter test --concurrency=2 test/sync/playback_refresh_test.dart --reporter expanded` | Exit 0. Thirty pass after the Undo correction. | `green-refresh-2.log` |
| Format | `nix develop --command dart format lib/playback/playback.dart test/sync/playback_refresh_test.dart` | Exit 0. Test file formatted. | `format.log` |
| Focused | `nix develop --command flutter test --concurrency=2 test/sync/playback_refresh_test.dart test/playback/command_queue_test.dart test/playback/save_queue_test.dart test/sync/event_upload_test.dart test/sync/owner_refresh_test.dart test/sync/refresh_retry_test.dart test/sync/refresh_after_sync_test.dart test/sync/writer_registration_test.dart --reporter expanded` | Exit 0. 127 pass, including the 32 new cases present at that point. No skips. | `focused.log` |
| Required suites | `nix develop --command flutter test --concurrency=2 test/playback test/sync test/durability test/app test/reader/persistence_test.dart test/reader/records_test.dart test/reader/unread_records_test.dart test/reader/session_test.dart test/reader/session_signals_test.dart test/reader/session_text_size_test.dart test/reader/pdf_session_test.dart test/reader/bookmark_names_test.dart test/reader/history_pages_test.dart test/reader/dock_history_test.dart --reporter expanded` | Exit 0. 1,054 pass, three existing opt-in skips. | `required.log` |
| First full suite | `nix develop --command flutter test --concurrency=2 --reporter expanded` | Exit 0. 3,579 pass, 27 existing skips. This preceded the additional overlap regression. | `full.log` |
| Overlap red | `nix develop --command flutter test --concurrency=2 test/sync/playback_refresh_test.dart --plain-name 'late recovery refresh' --reporter expanded` | Exit 1. Both storage backends lose the second live bookmark when the older recovery read returns. | `red-overlapping-refresh.log` |
| Overlap green | Same command as overlap red, after adoption advances the existing record revision. | Exit 0. Both cases pass. | `green-overlapping-refresh.log` |
| Final format | `nix develop --command dart format lib/playback/playback.dart test/sync/playback_refresh_test.dart` | Exit 0. Test file formatted. | `format-final.log` |
| Final focused | Same command as Focused above. | Exit 0. 129 pass, including all 34 final new cases. No skips. | `focused-final.log` |
| Final required suites | Same command as Required suites above. | Exit 0. 1,056 pass, three existing opt-in skips. | `required-final.log` |
| Initial analysis and format check | `nix develop --command bash -c 'dart format --output=none --set-exit-if-changed lib/playback/playback.dart test/sync/playback_refresh_test.dart && flutter analyze lib/playback/playback.dart test/playback test/sync'` | Exit 1. Format passes. Analyzer reports one missing brace around a test assertion. | `analysis-format.log` |
| Final analysis and format check | Same command as Initial analysis and format check above, after adding the test brace. | Exit 0. Both Dart files are unchanged by the formatter. No analysis issues. | `analysis-format-final.log` |
| Final full suite | `nix develop --command flutter test --concurrency=2 --reporter expanded` | Exit 0. 3,581 pass, 27 existing skips, no failures. Runtime: 4 minutes 49 seconds. | `full-final.log` |
| Complete diff | `git diff --cached --check` and `git diff --check a72d2043804c336877d6f3ed5ef72f3fd4994cd8` | Exit 0. Complete staged diff is whitespace-clean. | `diff-check.log` |

The three required-suite skips request `tool/plugin/prove.py` or
`tool/sync_fixture.py` in their pinned shells. They need separate live plugin
acceptance. The host test logs include missing iOS SDK diagnostics and Flutter's
fixture warning about HTTP. These runs use host test runners and controlled
server connections, not iOS builds or device acceptance.

The existing whole-list decode on the UI isolate remains tracked by `boo-w6m2`.
The shared record-writer redesign remains `boo-n7no`. Neither is expanded here.
The parent owns the independent combined verification of `boo-gcu6`.
No Android or browser action was attempted. The known Android Device panel
failure is `t1-dth0`, and the full browser app's PDF blocker is `t7-3j9c`.
Coverage and mutation testing remain with the parent after acceptance.

Both full runs passed. The known intermittent tests tracked by `t5-rplx` and
`tf-il7u` produced no failure here. Their causes remain unresolved. A passing
repeat is not evidence of a cause or a fix. The 27 full-suite skips are the
existing opt-in corpus, benchmark, and live-plugin checks. Their exact reasons
remain in the full logs.

All owned commands finished before review. No process was killed. Only the five
paths in this ticket's diff are staged. The sole reviewer will assess the
original-base-to-head diff without edits or independent execution.

## Sole review completed — 2026-11-13

Reviewed HEAD: `85cf3c20aff62c9f52ad9edfe245ae0d3a5caa02`.
The original-base-to-head diff received one fresh read-only review using
`codex/gpt-6-astra` with `reasoningEffort: high`, shared isolation, and
asynchronous execution. The reviewer has completed. No second review or fix
stage was needed.

Reviewer: <t3-thread://v2/38d3e8fa-8572-4c2a-8a3b-2eb7c344dfce/thread:delegated-task:command%3Amcp%3A7967dee4-db0f-4b04-b5d1-4cf95e3af126%3Adelegate-task%3Aboo-2bl9-sole-review-20261113-1>

| Original assessment | Verdict | Findings | Material unverified requirements |
| --- | --- | --- | --- |
| Correctness | pass | None | None |
| Ticket fulfillment | pass | None | None |
| Software design | pass | None | None |

The complete original review, including its evidence, validation gaps, and
unavailable checks, is preserved without changes in
`docs/evidence/playback/record-refresh-review.json`. Independent execution was
prohibited for the reviewer; runtime conclusions use the saved builder logs.
Native-device behavior and latency, existing opt-in live-plugin/corpus/benchmark
checks, parent acceptance and hardening, and whole-list decoding in boo-w6m2
remain outside this gate. No gap represents an unverified in-scope requirement.

Only review evidence changed after the reviewed HEAD. Production and tests are
unchanged, so no further test run is needed. The final evidence commit is
checked with `git diff --cached --check` and
`git diff --check a72d2043804c336877d6f3ed5ef72f3fd4994cd8`; results are saved in
`.cache/boo-2bl9/handoff-diff-check.log`. The ticket stays in progress for parent
integration, acceptance, hardening, and closure.
