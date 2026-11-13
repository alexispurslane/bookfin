---
id: boo-2bl9
status: closed
deps: []
links: [boo-rw9z, boo-n7no, boo-w6m2]
created: 2026-11-13T08:23:18Z
type: bug
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---

## Launch — 2026-11-13

Astra xhigh lead launched from a72d2043804c336877d6f3ed5ef72f3fd4994cd8.
Running, stage uncertain; branch not yet reported. Exactly one fresh read-only
Astra high reviewer authorized. Parent combined boo-gcu6 verification continues.

- clientRequestId: bookfin-boo-2bl9-astra-20261113-1
- taskId: node:delegated-task:command%3Amcp%3Ade3a91ba-7d8c-4ac2-9796-a93ca278e01c%3Adelegate-task%3Abookfin-boo-2bl9-astra-20261113-1
- childThreadId: thread:delegated-task:command%3Amcp%3Ade3a91ba-7d8c-4ac2-9796-a93ca278e01c%3Adelegate-task%3Abookfin-boo-2bl9-astra-20261113-1
- Link: <t3-thread://v2/38d3e8fa-8572-4c2a-8a3b-2eb7c344dfce/thread:delegated-task:command%3Amcp%3Ade3a91ba-7d8c-4ac2-9796-a93ca278e01c%3Adelegate-task%3Abookfin-boo-2bl9-astra-20261113-1>

# Keep record refresh from holding sync behind audio commands

## Parent integration and closure — 2026-11-13

Verified clean child identity, complete original-base diff, original review
and saved red/green checks. Inspected all 34 regression cases, real sync/store
callers, account and record-revision guards, audio mutations across waits,
snapshot acceptance and Undo ownership. Integrated without conflicts:
`85cf3c20` became `3634b062`; `47b39a14` became `5ca486a0`. Parent Playback
production code before integration was identical to the child's original base.
No second review or reviewer execution is claimed.

Parent checks ran sequentially through `nix develop --command bash -c`:

- `dart format --output=none --set-exit-if-changed lib/playback/playback.dart
  test/sync/playback_refresh_test.dart`: two files, zero changes.
- `flutter analyze --no-pub lib test integration_test`: no issues.
- `flutter test --no-pub --concurrency=2 --reporter=expanded` on playback,
  sync, durability, app, crossings, speech, and the affected reader persistence,
  records, unread_records, session, session_signals, session_text_size,
  pdf_session, bookmark_names, history_pages, dock_history, book_words_reader,
  text_outline and book_map test files: 1,289 passed, three existing skips,
  no failures; completed in 1:14.

The driver exited 0. Logs: `/tmp/boo-2bl9-integrated-format.log`,
`/tmp/boo-2bl9-integrated-analysis.log`,
`/tmp/boo-2bl9-integrated-affected.log`, and
`/tmp/boo-2bl9-integrated-driver.log`. The child full suite at the unchanged
implementation passed 3,581 tests with 27 skips; the parent reran integration-
affected suites, including the newly integrated speech work, rather than
claiming a new combined full-suite run. Integration/staged diff checks passed.

Implementation is integrated and closed. Device acceptance, existing gated
checks, user acceptance and hardening remain separate. No device/browser,
coverage, mutations, push, PR, deployment or worktree removal. The known
intermittent test causes remain unresolved.

Found during parent integration of boo-rw9z at 4c020d1e. Read-only evidence; no reproduction has been run. Playback.flush is now independent of unfinished audio commands, and its regression proves transport can exchange durable records while a seek is held. A later step remains coupled: RecordSync._sync awaits records.refreshWriters (lib/sync/coordinator.dart:391); the store awaits every stale writer (lib/playback/store.dart:241); Playback.refreshPersonalRecords uses _recordsCommand (lib/playback/playback.dart:619), which shares the audio command queue. When received listening records make Playback stale during a held audio command, the exchange can finish but the sync operation cannot. _exclusive retains _running until _sync returns, so later manual or background syncs also wait. This is a statically confirmed path; the trigger still needs a controlled regression.

Reproduce an exchange that receives a listening record while an audio command remains held, then request another exchange. Keep the received record durable, protect pending local changes, account/generation identity, revision checks and snapshot acceptance, and preserve clear sync outcomes. Use one coherent ownership model to keep durable sync progress independent of decoder completion while adopting live records safely. Decide the interface from these real callers before implementation; do not add a timeout or claim the records were adopted when they were not. Preserve the existing boo-rw9z flush contract. Related shared-writer and typed-record work may provide the same ownership boundary. Follow red-green TDD and existing single-review rules when scheduled.

## Parent caller audit and settled scope — 2026-11-13

At `992b7310`, the wait remains: RecordSync._sync awaits refreshWriters after
the exchange; refreshWriters awaits each registered stale writer; Playback's
refreshPersonalRecords uses _recordsCommand, which shares _operations and waits
for _binding. Binding itself can wait for an old audio command. The refresh
only adopts history/bookmarks/resumes; it does not drive the audio engine or
move the current decoder position. ReaderSession already uses a direct guarded
record refresh. Existing generation, record-revision, pending-write and accepted
snapshot ownership provide the model for the narrower Playback correction.

Keep personal-record refresh independent of audio-command completion. A sync
that receives records must complete, and a later sync must exchange again,
while load, seek or pause remains held. Keep received records durable and adopt
them in live state when the same restored account and unchanged local state
permit it. A rejected or obsolete snapshot must not clear staleness or become
the store's observed baseline. Capture request/account generation before waits;
checking the account string alone does not protect leaving and returning to
the same account. Pending/restoring account state must not wait on an unrelated
decoder to allow durable sync progress. Preserve safe retry after rejection.

Use the existing owners: Playback owns its live records and current confirmed
place; LocalResumeStore owns durable records and stale/accepted snapshots;
RecordSync owns exchange completion and reporting. Do not create a second
record writer, queue of pending actions or detached success path. Preserve
pending local changes, in-flight storage writes, record revision checks,
bookmark/history deletion, Undo, account replacement and close. Audit mutations
around audio awaits before removing serialization. Keep ordinary read failures
visible to sync without stopping audio; programming Errors still propagate.
No timeout, retry delay or timing-threshold workaround. This does not change
the ordering of unrelated audio/edit commands or the Ask-at-Play behavior in
boo-56h7. A sync still never moves the open decoder. Broader shared-writer and
typed-record work remain boo-n7no/boo-w6m2.

Read docs/plans/bookfin.md, docs/plans/reading-history.md, docs/playback.md,
test/playback/command_queue_test.dart, save_queue_test.dart, held_engine.dart,
test/sync/event_upload_test.dart, owner_refresh_test.dart, refresh_retry_test.dart,
refresh_after_sync_test.dart, writer_registration_test.dart and actual callers.
Primary ownership is playback.dart, focused playback/sync tests and contract
documentation. Change store/coordinator/reader only for a demonstrated required
ownership or interface correction. Preserve integrated boo-gcu6 domain settings
and boo-3y46 incomplete-exchange refresh behavior; do not duplicate concurrent
boo-j7gh speech work or boo-0740 gallery work.

Required controlled red-green proof: receive a listening record and complete
two exchanges before releasing an audio command; verify durable and live records
and confirmed decoder position, then release and verify command persistence.
Cover held load/seek/pause, late refresh after account change and return, close,
local save during held read, failed pending writes/retry, rejected snapshot
acceptance, ordinary refresh failure and programming errors. Use real Playback,
RecordSync and stores, including SQLite and preference persistence where the
existing fixtures support them; no mock-only coordinator claim. Reuse existing
tests where they already establish a case. Preserve both successful and rejected
upload outcomes without claiming a stale view was adopted.

Run Nix focused regressions, playback/sync/durability/app and affected reader
persistence/records tests, full Flutter suite, affected analysis/format/diff.
Flutter concurrency two; one heavy command per owner. One Astra xhigh lead
builds/fixes and exactly one fresh read-only Astra high reviewer assesses the
entire diff. No second review, device/browser, coverage, mutation, publication
or closure. Parent integrates and closes. Host work counts/completion gates are
not device latency evidence. Parent combined verification of boo-gcu6 is running
independently; its implementation and sole-review checks are already complete.

## Implementation evidence — 2026-11-13

Initial worktree: `/Users/alexispurslane/.t3/worktrees/bookfin/t3-171de35c`.
Branch: `t3/decouple-record-refresh-audio`. Initial HEAD and original review
base: `a72d2043804c336877d6f3ed5ef72f3fd4994cd8`. Initial status was clean.
No checkout was created, reset, switched, or removed. `tk ready` and
`tk dep tree boo-2bl9` showed no dependencies. `tk start boo-2bl9` retained
in-progress status.

Playback refresh now adopts records directly after local writes. It does not
wait for audio commands or binding. Account generation is captured before
waits, and closed, unrestored, pending-write, and record-revision guards reject
unsafe snapshots. Only adoption calls the existing snapshot acceptance method.
Undo uses the matching adopted history object. The existing record revision
also advances on adoption, so startup recovery cannot replace a newer snapshot
that sync adopted during a held recovery read.

The remaining production owners and interfaces are unchanged. No record writer,
pending-action inventory, generic queue, typed-record rewrite, Ask-at-Play,
speech, gallery, or settings-schema change is included. Whole-list decoding on
the UI isolate remains tracked by boo-w6m2. Shared writer work remains boo-n7no.

Full caller audit, controlled red-green evidence, exact commands, results,
failures, skips, and log locations are in
`docs/evidence/playback/record-refresh.md`. Raw logs are in this worktree's
`.cache/boo-2bl9/`. The parent owns integration, acceptance, hardening, and
closure. No device, browser, coverage, mutation, push, PR, or deployment action
was attempted.

Final pre-review checks: focused 129 passed; required playback/sync/durability/app
and reader suites 1,056 passed with three existing skips; full Flutter suite
3,581 passed with 27 existing skips. Affected analysis and formatting passed.
The complete diff is whitespace-clean. All commands finished. No failure from
known intermittent tests t5-rplx or tf-il7u occurred in either full run, and
neither cause is claimed as resolved. The single read-only review is next.

## Review completion — 2026-11-13

The sole fresh reviewer completed the original-base-to-head review at
`85cf3c20aff62c9f52ad9edfe245ae0d3a5caa02`. Correctness, ticket fulfillment,
and software design each passed, with no findings and no material unverified
requirements. Target: `codex/gpt-6-astra`, `reasoningEffort: high`, shared
isolation, asynchronous execution. No fix stage or second review was needed.

Reviewer: <t3-thread://v2/38d3e8fa-8572-4c2a-8a3b-2eb7c344dfce/thread:delegated-task:command%3Amcp%3A7967dee4-db0f-4b04-b5d1-4cf95e3af126%3Adelegate-task%3Aboo-2bl9-sole-review-20261113-1>

The original verdicts, evidence, gaps, and unavailable checks are preserved in
`docs/evidence/playback/record-refresh-review.json`; their disposition and final
diff checks are recorded in `docs/evidence/playback/record-refresh.md`.
The reviewer inspected saved execution logs and did not run tests or builds.
Excluded device acceptance, existing opt-in skips, parent hardening, and the
tracked whole-list decoding work remain unchanged. Only review evidence changed
after the reviewed HEAD; production and tests remain the reviewed versions.
The ticket stays in progress for the parent to integrate, accept, harden, and
close.
