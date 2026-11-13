---
id: boo-hmrp
status: closed
deps: [boo-f4xm]
links: [boo-0931, boo-s11s]
created: 2026-11-12T23:41:00Z
type: bug
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Upload pending records when playback pauses or the app hides

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: confirmed. lib/main.dart:333-341 calls `sync.suspend()` when the app hides, and `playback.flush()` writes only to local SQLite. No code calls `synchronize()` while the app is hidden (lib/sync/coordinator.dart:171-175). An hour listened with the phone locked stays on the phone until Bookfin opens again. A second device then plays from the old place, and the two devices produce a "Choose a saved place" conflict. Drive the upload from events: pending actions plus a pause, a stop, a book change or the app hiding, with a debounce. During background playback, use the 10-second cadence that lib/playback/reporting.dart:76 already has. Keep the boo-nxp8 decision of no polling while idle.



## Astra implementation launch

Review base: 3e345a1737fd0312e3fb6b5575eddf7de9ea2df1. Separate T3 worktree; implementation and direct fixes use codex/gpt-6-astra with reasoningEffort xhigh. One fresh read-only reviewer is authorized with the same provider/model and reasoningEffort high. No other stage agents. Required checks include affected suites/analysis and the full Flutter suite through nix develop with concurrency at most two. Parent owns integration and closure.

Client request ID: bookfin-boo-hmrp-astra-20261113-1
Task ID: node:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-boo-hmrp-astra-20261113-1
Child thread ID: thread:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-boo-hmrp-astra-20261113-1
Thread: <t3-thread://v2/38d3e8fa-8572-4c2a-8a3b-2eb7c344dfce/thread:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-boo-hmrp-astra-20261113-1>
Launch status: running; stage not yet reported. Completion will be delivered automatically.

## Implementation and verification, 2026-11-13

The lead inspected `/Users/alexispurslane/.t3/worktrees/bookfin/t3-c2623271`, branch `t3/flush-pending-records`, and clean HEAD `3e345a1737fd0312e3fb6b5575eddf7de9ea2df1` before work. No checkout was created, switched, reset, or removed. `tk ready` and the dependency tree confirmed integrated boo-f4xm. This ticket stays in progress; the parent owns integration and closure.

The implementation extends the registered-writer boundary from boo-f4xm:

- Playback registers an optional upload-opportunity signal with its durable domain store. The registration tags events with the writer's current account and removes the listener when it unregisters. ReaderSession is unchanged, including its teardown order and PDF behavior.
- Pause, Stop, a book change, a decoder interruption/completion, and an audio-device failure request an upload. Ongoing audio progress uses the existing ten-second source-position interval, now named in `reporting.dart` and shared by the two reporters. Playback keeps only the last position used for this cadence, never a copy of the durable pending state.
- RecordSync combines nearby events with a short debounce, flushes the registered writers, and asks the store's journal whether durable pending actions exist. App hide stops the existing foreground polling but preserves the event upload. Resume checks pending actions even before periodic discovery comes due. No idle background polling was added.
- An event waits behind an active exchange or user choice. A successful exchange that leaves newly saved actions schedules another check. A failed exchange keeps pending actions and waits for a real event, resume, or manual retry. An event received during that failure still gets its own later attempt.
- Binding a new account or token, signing out, and disposing cancel scheduled events. A generation check after writer flush prevents an obsolete exchange. Exclusive-work completion now clears its owner before waking waiters, so a completed future cannot remain installed while another zone waits for it.
- All app-started exchanges use the same status policy. They show no busy indicator or new message and replace an older choice message when an exchange ends.
- `Playback.flush()` no longer waits for live Jellyfin playback reports. This is necessary for local persistence and the final upload to continue when a report is slow. `Playback.close()` retains its explicit report drain. The separate boo-rw9z question about waiting for the command queue is not implemented here.

No protocol batching, plugin API change, journal snapshot restoration, large wire-payload offload, writer unification, or PDF change is included. No product fork was found.

### Red evidence

All commands below ran through the pinned Nix dev shell, with Flutter concurrency two. Tests use fake time, controlled storage/network futures, real writer registration, and real durable record operations. The transport test double captures actions and acknowledges them through the real store. No test sleeps for a time interval.

- `nix develop --command bash -c 'flutter test --no-pub --concurrency=2 test/sync/event_upload_test.dart --reporter expanded'` against the original production files: 4 passed, 16 failed for missing uploads, missing follow-up/retry, slow-report coupling, or obsolete exchanges after an account/disposal change. Log: `/tmp/boo-hmrp-corrected-baseline-red.log`. The implementation files were kept under `/tmp/boo-hmrp-implementation` during this check and restored afterward; Git HEAD and branch never changed.
- `nix develop --command bash -c 'flutter test --no-pub --concurrency=2 test/sync/event_upload_test.dart --plain-name "slow Jellyfin" --reporter expanded'`: both tests failed while local flush still waited for live reports. Log: `/tmp/boo-hmrp-slow-reports-red.log`.
- `nix develop --command bash -c 'flutter test --no-pub --concurrency=2 test/sync/event_upload_test.dart --plain-name "older choice message" --reporter expanded'`: 1 failed because an event upload kept the old choice message. Log: `/tmp/boo-hmrp-event-status-red.log`.
- `nix develop --command bash -c 'flutter test --no-pub --concurrency=2 test/sync/event_upload_test.dart --plain-name "audio device fails" --reporter expanded'`: 1 failed because a stop whose audio device rejected Pause saved but did not upload the last place. Log: `/tmp/boo-hmrp-failed-stop-red.log`.

Earlier fixture-development runs are not verification: a missing initial package configuration, a cleanup-zone stall, an incorrect resume-address lookup, and a guarded `expect` inside a timer callback were corrected. Stalled runs were interrupted by signaling only the runner PID of this lead. Their logs remain under `/tmp/boo-hmrp-*` (including the trace and initial green-attempt logs); none is called passing. The corrected baseline run above supersedes the initial red attempts. A policy run also exposed old test doubles that did not implement the new pending query; those doubles now explicitly report no pending records, and the rerun passed all 50 tests in `/tmp/boo-hmrp-events-and-policy-final.log`.

### Required checks

The first affected run passed 873 tests, with 2 external-fixture skips, in 1:04: `/tmp/boo-hmrp-affected.log`. A final affected run, affected analysis, formatting/diff checks, and the final full Flutter suite are recorded below after the last stop-path fix.

The Nix Flutter wrapper reports that the iOS device/simulator SDKs are absent. These are host Flutter tests, not iOS or Android acceptance. The external ordinary-account plugin and plugin-upgrade fixtures remain opt-in. No live plugin, Android, coverage, or mutation-testing claim is made. The parent owns acceptance and hardening.

Final affected command:

`nix develop --command bash -c 'flutter test --no-pub --concurrency=2 test/playback test/sync test/durability test/app test/reader/persistence_test.dart test/reader/records_test.dart test/reader/reading_moves_test.dart test/reader/pdf_preferences_store_test.dart --reporter expanded'`

Result: 874 passed, 2 skipped, no failures, 1:47. Log: `/tmp/boo-hmrp-affected-final.log`. Skips: the external ordinary-account plugin round trip and the durable plugin-upgrade fixture. The 26 event tests include the real app lifecycle, slow live reports, delayed local saves, overlapping uploads, failure/retry, account/disposal changes during a flush, writer unregistering/account filtering, cadence, and quiet status behavior.

Final affected analysis command:

`nix develop --command bash -c 'flutter analyze --no-pub lib/playback lib/sync lib/main.dart lib/reader/session.dart test/playback test/sync test/durability test/app test/reader/persistence_test.dart test/reader/records_test.dart test/reader/reading_moves_test.dart test/reader/pdf_preferences_store_test.dart'`

Result: no issues, 4.4 seconds. Log: `/tmp/boo-hmrp-analysis-final.log`. An earlier analysis command was launched before the affected test runner had finished. It completed successfully before the attempt to stop its own process (`kill` reported that the process no longer existed). Its log is `/tmp/boo-hmrp-analysis.log`. The final analysis above ran separately after the affected tests ended. This brief overlap is a process deviation; it is not presented as sequential verification.

`nix develop --command bash -c 'dart format --output=none --set-exit-if-changed lib/playback/playback.dart lib/playback/record_writer.dart lib/playback/reporting.dart lib/playback/store.dart lib/sync/coordinator.dart test/sync/event_upload_test.dart test/sync/schedule_test.dart test/sync/status_test.dart'`: 8 files, 0 changed, in 0.07 seconds (`/tmp/boo-hmrp-format-check.log`). `git diff --check` passed.

Final full-suite command:

`nix develop --command bash -c 'flutter test --no-pub --concurrency=2 --reporter expanded'`

Result: 3,222 passed, 25 skipped, no failures, 4:27. Log: `/tmp/boo-hmrp-full.log`. This is the given 3,196-pass baseline plus 26 new tests. Skips remain the existing opt-in EPUB/PDF benchmarks and corpus runs, seven unavailable downloaded trial books, journal-growth/layout measurements, and two external plugin fixtures. The runner exited successfully. No test process from this lead remains running.

### Independent review, 2026-11-13

Exactly one fresh shared-worktree agent completed the review, role review, async mode, `codex/gpt-6-astra` with `reasoningEffort: high`, client request ID `boo-hmrp-review-astra-20261113-1`. `orchestrator_capabilities` was checked once in this lead's thread and confirmed that exact target. The reviewer inspected the complete nine-file diff from original base `3e345a1737fd0312e3fb6b5575eddf7de9ea2df1` to implementation HEAD `a40f99de1f3ca53fb1c61faca6eabcaa31a1099c`, real production callers, and the saved verification logs. It made no edits and ran no builds or tests.

Review thread: <t3-thread://v2/38d3e8fa-8572-4c2a-8a3b-2eb7c344dfce/thread:delegated-task:command%3Amcp%3A70432dee-dc80-4d30-ac97-4037d21816dd%3Adelegate-task%3Aboo-hmrp-review-astra-20261113-1>

| Assessment | Verdict | Evidence |
| --- | --- | --- |
| Correctness | pass | Traced playback events, the app lifecycle, AccountBinding, writer teardown, and transport/store operations. Local flush precedes the durable pending check; generation checks prevent obsolete exchanges; overlapping events and new actions survive; failures preserve pending actions without idle background retries. Saved logs confirm 874 affected passes, 3,222 full-suite passes, clean analysis, and unchanged formatting. |
| Fulfillment | pass | Pause, stop, book change, app hide, and the existing playback cadence supply upload opportunities. Tests cover debounce, delayed persistence, overlap, failures, resume/manual retry, quiet status, account changes, disposal, writer registration, and the real lifecycle callback. ReaderSession/PDF behavior and account/domain refresh boundaries remain unchanged. |
| Design | pass | Under the user's single-owner rule, LocalResumeStore owns durable pending actions and acknowledgments; RecordSync owns scheduling. Under Ousterhout information hiding, registration owns account tagging/listener removal and transport owns protocol validation. Under Muratori scope/compression, the existing writer boundary is extended without speculative writer abstractions or a second pending inventory. |

Findings: none. No fixes, rejected findings, or unresolved product forks remain. The final review-record commit changes only this ticket; production and test files remain exactly at the reviewed implementation HEAD.

Review limitations: execution evidence came from saved logs, not reviewer reruns. The event tests use controlled transport and preference-backed persistence; existing transport and durability tests cover those boundaries separately. Android background execution and live plugin behavior remain unverified, and existing opt-in/external-fixture skips remain. The pass verdicts cover this implementation ticket; release acceptance, integration checks, coverage, and mutation testing remain with the parent. The ticket stays in progress until the parent integrates and closes it.


## Parent integration and verification

The parent inspected the complete original-base-to-ed8b991e diff, the fresh Astra review, and saved verification logs. Integrated as ecf2cb34 (implementation) and d90ed7c4 (review record). The only conflict was the ticket appendix; both the parent launch record and child evidence were kept. Production and tests match the reviewed branch.

On integrated main, the affected analysis command recorded above found no issues in 6.2 seconds (/tmp/boo-hmrp-integrated-analysis.log). The parent ran `nix develop --command bash -c 'flutter test --no-pub --concurrency=2 --reporter expanded'`: 3,222 passed, 25 skipped, no failures, 4 minutes 48 seconds (/tmp/boo-hmrp-integrated-full.log). The command exited successfully and git diff --check passed. No owned command remains running.

Closed after integration and verification. Android background execution and live plugin acceptance remain unverified; existing external-fixture and opt-in skips remain. No coverage/mutation campaign, deployment, push, or publication was performed. The next dependency is boo-s11s; its client-first and plugin-second scope is already approved.
