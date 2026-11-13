---
id: boo-2bl9
status: in_progress
deps: []
links: [boo-rw9z, boo-n7no, boo-w6m2]
created: 2026-11-13T08:23:18Z
type: bug
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Keep record refresh from holding sync behind audio commands

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
