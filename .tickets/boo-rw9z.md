---
id: boo-rw9z
status: closed
deps: []
links: [boo-2bl9, boo-n7no, boo-w6m2]
created: 2026-11-12T23:41:00Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Make Playback.flush wait only for record writes

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: confirmed. `flush()` (lib/playback/playback.dart:1756-1770) awaits the whole command queue and `reports.idle`, the chain of Jellyfin progress reports with 20-second timeouts. `SyncCoordinator` awaits `flush()` before each sync (lib/sync/coordinator.dart:225, 294). A slow network delays a sync that the user started, and a command that never returns blocks every later sync. `flush` saves the current place and awaits only the record writes. A caller that also needs the reports drained asks for that separately.

## Settled implementation scope, 2026-11-13

The integrated boo-hmrp changes already removed the wait for live Jellyfin reports. Preserve that implementation and its regressions. At main `25a2fde5`, `Playback.flush()` still waits for `_operations.idle`; `_binding` can also wait for earlier audio commands. The remaining task is to make local record persistence independent of an unfinished audio command, without inventing a second record writer or a second place authority.

Save the current confirmed place and changed records, await the corresponding local writes, and retain/retry failed writes under their original account. A requested seek or book that the decoder has not confirmed must not replace the confirmed place. Saving must work during a held load, seek or pause, and an account transition must not move old pending writes into the new account. Do not silently change command completion into a requirement that callers must invoke flush. Each command remains responsible for saving the records it produces. Inspect current callers that used flush as a command barrier and make each wait for its actual command when needed. Teardown still owns stopping playback, draining live reports and releasing resources. Preserve the existing ordinary-save-failure versus programming-error behavior.

Use controlled engine and storage waits to prove meaningful red-green behavior: flush finishes before an unrelated held audio command, an unconfirmed destination is not saved, local writes still delay flush until durable, failed pending writes survive and retry, account changes preserve ownership, and sync can start an exchange after local saves without waiting for the held command. Retain ongoing playback/upload cadence, history, Undo, record refresh merging and shared writer registration. Read `test/playback/save_queue_test.dart`, `test/playback/replacement_test.dart`, `test/sync/event_upload_test.dart` and actual lifecycle/sync callers before changing them.

Primary ownership: `lib/playback/playback.dart`, relevant playback/sync tests and this ticket. Change other callers only where this behavior requires it. boo-o3cm concurrently owns download restoration and AccountBinding; boo-3y46 owns unreadable remote-object admission. Do not duplicate either task. Parent resolves integration overlap. The pending product decision in boo-56h7 does not belong here.

Required checks through Nix: focused behavior tests, `test/playback test/sync test/durability test/app` plus relevant reader persistence/records tests, affected analysis and formatting, and the full Flutter suite. Flutter concurrency two; one heavy command at a time. Implementation and fixes use codex/gpt-6-astra at xhigh. Exactly one fresh read-only reviewer uses the same model at high. No second review, coverage, mutation testing, devices, browser work, push, PR, deployment or ticket closure. Parent owns integration, acceptance and hardening.

## Delegated task

Original base: `db45fcaa5e13cab6eb2de210d5d0403623f4a31b`.
Client request ID: `bookfin-boo-rw9z-astra-20261113-1`.
Task ID: `node:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-boo-rw9z-astra-20261113-1`.
Child thread ID: `thread:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-boo-rw9z-astra-20261113-1`.
Thread: <t3-thread://v2/38d3e8fa-8572-4c2a-8a3b-2eb7c344dfce/thread:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-boo-rw9z-astra-20261113-1>.
Launch returned running on codex/gpt-6-astra, reasoningEffort xhigh. Branch and precise stage are not yet reported. Build, one fresh read-only review, then direct fixes are authorized. Completion delivery is automatic; do not poll.

## Build evidence, 2026-11-13

Initial inspection: worktree `/Users/alexispurslane/.t3/worktrees/bookfin/t3-752b9c95`, branch `t3/playback-flush-record-writes`, HEAD `db45fcaa5e13cab6eb2de210d5d0403623f4a31b`, clean. No checkout was created, reset, switched or removed. Read the project plan, project instructions, builder brief, orchestration ticket-lead brief, software-design and TDD skills. `tk ready` and `tk dep tree boo-rw9z` show no dependency; `tk start boo-rw9z` retained in-progress ownership.

`Playback.flush` now captures the current confirmed place immediately through the existing save path, waits for local writes, and retries pending changes under their original account. It no longer waits for binding or the command queue, or abandons those retries when the account generation changes. No new writer or position authority. The existing save guards protect unrestored accounts. No change to command persistence, error classification, upload cadence, record refresh merging, writer registration, or teardown. Updated the stale flush entry in `docs/playback.md` to match this contract, including the already-integrated independence from reports.

Caller inspection: lifecycle background and desktop exit (`lib/main.dart`), Retry saving (`lib/playback/records_screen.dart`), and sync through `LocalResumeStore.flushWriters` need local persistence, not audio completion. Native media controls return their command futures. `Playback.close` already awaits `stop`, then flushes, drains reports and releases resources. No production caller needs changing. Three tests used flush to wait for automatic decoder-error handling or reopening after catalog arrival. They now observe the corresponding Playback change, because those internally initiated operations expose no command future. Direct command tests continue awaiting the commands.

New controlled tests hold load, seek and pause before decoder confirmation. They read reopened storage to check the last confirmed place (11,234 ms), retained history and bookmark, saved Undo, and exclusion of a requested seek or book. They also hold storage to check durability, retry failed records while an account transition waits for audio, and prove that sync exchanges the confirmed 3,456 ms place after local persistence while a seek remains held. Seek and pause completion still persist their resulting records without another flush.

All check commands below ran from this worktree through `nix develop --command bash -c '<command>'`; one heavy command at a time and Flutter concurrency two. Output files are under `/tmp`.

| Attempt | Exact shell payload | Result | Log |
| --- | --- | --- | --- |
| Initial red | `flutter test --concurrency=2 test/playback/save_queue_test.dart test/sync/event_upload_test.dart --plain-name "held"` | Exit 1: test getter typo prevented save-queue compilation; sync test failed because no exchange started. Not counted as the complete red proof. | `/tmp/boo-rw9z-red.log` |
| Meaningful red | `flutter test --concurrency=2 test/playback/save_queue_test.dart test/sync/event_upload_test.dart --name "held\|account change waits"` | Exit 1: all six new cases failed on blocked flush, missing local write, or missing exchange. | `/tmp/boo-rw9z-red-2.log` |
| First green attempt | `flutter test --concurrency=2 test/playback/save_queue_test.dart test/sync/event_upload_test.dart --name "held\|account change waits"` | Exit 1: four passed, two checked completion before real storage work finished. Replaced the short event-queue drain with a bounded wait for flush completion. | `/tmp/boo-rw9z-green.log` |
| Focused | `dart format lib/playback/playback.dart test/playback/save_queue_test.dart test/playback/held_engine.dart test/sync/event_upload_test.dart && flutter test --concurrency=2 test/playback/save_queue_test.dart test/sync/event_upload_test.dart` | Exit 0: 44 passed. | `/tmp/boo-rw9z-focused.log` |
| First affected run | `flutter test --concurrency=2 test/playback test/sync test/durability test/app test/reader/persistence_test.dart test/reader/records_test.dart test/reader/unread_records_test.dart test/reader/epub/saved_places_test.dart` | Exit 1: 908 passed, four skipped, three failed. Failures: “a decoder failure stops starting”, “restart reopens the saved book when the library loads after the account”, and “a native playback failure stops audio and keeps the last durable source position”. All three used flush as a command barrier. | `/tmp/boo-rw9z-affected.log` |
| Caller tests | `dart format test/playback/observe_playback.dart test/playback/play_start_test.dart test/playback/playback_test.dart && flutter test --concurrency=2 test/playback/play_start_test.dart test/playback/playback_test.dart` | Exit 0: 42 passed after observing the automatic changes directly. | `/tmp/boo-rw9z-callers.log` |
| Final affected run | `flutter test --concurrency=2 test/playback test/sync test/durability test/app test/reader/persistence_test.dart test/reader/records_test.dart test/reader/unread_records_test.dart test/reader/epub/saved_places_test.dart` | Exit 0: 911 passed, four existing opt-in tests skipped. | `/tmp/boo-rw9z-affected-final.log` |
| Format and affected analysis | `dart format --output=none --set-exit-if-changed lib/playback/playback.dart test/playback/save_queue_test.dart test/playback/held_engine.dart test/playback/observe_playback.dart test/playback/play_start_test.dart test/playback/playback_test.dart test/sync/event_upload_test.dart && flutter analyze lib/playback/playback.dart test/playback test/sync` | Exit 0: seven files unchanged; no analysis issues. | `/tmp/boo-rw9z-analysis.log` |
| Full Flutter suite | `flutter test --concurrency=2` | Exit 0: 3,395 passed, 27 existing opt-in tests skipped; 4 minutes 32 seconds. | `/tmp/boo-rw9z-full.log` |

The four affected-suite skips require separate live plugin/sync proofs or `BOOKFIN_EPUB_TRIAL=1`. No commands were interrupted. Coverage, mutation testing, acceptance and integration remain with the parent. This ticket stays open until integration.

## Single review completed, 2026-11-13

Reviewer: <t3-thread://v2/38d3e8fa-8572-4c2a-8a3b-2eb7c344dfce/thread:delegated-task:command%3Amcp%3A82b69cb9-22db-4497-a39c-34709d941d53%3Adelegate-task%3Aboo-rw9z-review-20261113-1>

The one authorized `delegate_task` used shared isolation, async mode, review role, provider `codex`, model `gpt-6-astra`, and `reasoningEffort: high`. `orchestrator_capabilities` was called once before delegation. Client request: `boo-rw9z-review-20261113-1`. Task: `node:delegated-task:command%3Amcp%3A82b69cb9-22db-4497-a39c-34709d941d53%3Adelegate-task%3Aboo-rw9z-review-20261113-1`. Completion was delivered without polling; the finished thread was then read to verify its report.

Original review base: `db45fcaa5e13cab6eb2de210d5d0403623f4a31b`. Original review head: `992159fcb76f163c156d973c95b4ad69a2da9478`. The reviewer inspected all nine changed files, real callers and the saved logs. The checkout stayed clean and unchanged during review. These are the original verdicts, not a second approval:

| Assessment | Verdict | Evidence | Limits |
| --- | --- | --- | --- |
| Correctness | pass | Confirmed-place authority, account-owned retries, ordered writes, failure classification, command persistence and teardown inspected; controlled tests and retained report-independence regressions checked against saved logs. | Static review and observed logs, no independent execution. |
| Fulfillment | pass | Six new behavior cases cover the settled scope; lifecycle, retry-save, sync and native-control callers checked; automatic-transition tests corrected; excluded tickets untouched. | The sync test proves exchange starts while a command is held, not that all subsequent sync steps complete independently. This matches the settled scope. |
| Design | pass | User: one authority for confirmed place and pending records. Ousterhout: persistence no longer depends on unrelated command completion and the contract states that. Muratori: existing save path reused without duplicate state or new production abstractions. | No material design evidence missing for this bounded change. |

Overall verdict: pass. Findings: none. No fixes, rejected findings, unresolved material assessments or product forks. The reviewer confirmed the saved results, including six meaningful red failures and the 3,395-pass full suite. Execution parameters and exit codes are recorded by the builder; output logs alone do not independently prove every parameter. Independent reviewer execution, coverage, mutation testing, device acceptance and skipped opt-in checks were unavailable or excluded as instructed.

Only this review evidence changed after the reviewed head; implementation and test content remain the versions that passed the final checks. No second review or re-check was requested. Ready for parent integration; ticket closure and acceptance remain with the parent.

## Parent integration and closure, 2026-11-13

Integrated onto main at `7b189bf7` as implementation `9b794f1e` and review evidence `4c020d1e`. Only the ticket conflicted; both the parent's launch record and the child's build evidence were retained. Production, tests and playback documentation are identical to the reviewed child head. The parent inspected all nine changed files, actual persistence/account/command/lifecycle/sync callers, the completed review and saved test results. No second reviewer or product edit was needed.

| Check | Result | Log |
| --- | --- | --- |
| `nix develop --command flutter test --no-pub --concurrency=2 test/playback test/sync test/durability test/app test/reader/persistence_test.dart test/reader/records_test.dart test/reader/unread_records_test.dart test/reader/epub/saved_places_test.dart --reporter expanded` | Exit 0; 911 passed, 4 existing skips; 1:07 | `/tmp/boo-rw9z-integrated-affected.log` |
| `nix develop --command flutter test --no-pub --concurrency=2 --reporter expanded` | Exit 0; 3,395 passed, 27 existing skips, zero failures; 4:35 | `/tmp/boo-rw9z-integrated-full.log` |
| `nix develop --command bash /tmp/boo-rw9z-integrated-checks.sh` | Exit 0; seven changed Dart files format-clean; affected analysis found no issues | `/tmp/boo-rw9z-integrated-format.log`, `/tmp/boo-rw9z-integrated-analysis.log` |

The script runs `dart format --output=none --set-exit-if-changed` on the seven Dart files in `git diff --name-only 7b189bf7 HEAD -- '*.dart'`, then `flutter analyze --no-pub lib/playback/playback.dart test/playback test/sync`. `git diff --check 7b189bf7 HEAD` passed. All commands finished, one heavy parent command at a time. The parent run had no failures.

The documented later sync wait is now tracked by `boo-2bl9`: a stale Playback writer refresh still waits behind an audio command, so sync completion and later exchanges can wait after this ticket's independent flush and transport exchange. This ticket does not claim to solve that later step. Closed after integration and host verification. Android acceptance remains blocked by `t1-dth0`; hardening awaits acceptance. No device retry, browser work, coverage, mutation run, push, PR or deployment occurred.
