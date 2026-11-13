---
id: t5-6lnm
status: in_progress
deps: [boo-2bl9]
links: [boo-x1zf]
created: 2026-11-13T02:08:04Z
type: bug
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Do nothing when a history entry or a bookmark is gone before its command runs

Found during the second change of boo-x1zf. Nothing was run for this finding. Status: mechanism confirmed by reading, trigger plausible. Since boo-x1zf, the command queue of Playback gives each command its own future, and a failure goes only there. A failed argument guard (ArgumentError) whose caller drops the future now reaches the zone as an uncaught error. Before boo-x1zf, the queue head ignored it. Three guards in lib/playback/playback.dart throw ArgumentError when an id is no longer in the records: restoreHistory (about line 508, 'Choose history from the current account.'), restoreBookmark (about line 647) and editBookmark (about line 569, both 'Choose a bookmark from the current account.'). A sync can remove the entry between the tap and the run of the command, because refreshPersonalRecords replaces the lists. The callers drop the future: lib/playback/timeline.dart:159 runs unawaited(restore()) for Go to on a history entry or a bookmark, and lib/playback/timeline.dart:300 runs unawaited(editAudioBookmark(...)), which reaches playback.editBookmark at lib/playback/records_screen.dart:94. The race at records_screen.dart:94 is wide, because the editor stays open while a background sync runs. Fix: a missing id after such a race is not a misuse by the caller, so the command does nothing and completes normally, as deleteBookmark and deleteHistory already do for an absent id. Keep ArgumentError for arguments that the caller controls, such as a speed outside 0.5 to 3. Look at the same guards of the reader (restoreBookmark and editBookmark in lib/reader/session.dart). Add tests, red first: a Go to on an entry that a refresh removed does nothing and reports no error, and a rename of a bookmark that a refresh removed while the editor was open does nothing and reports no error.

## Parent caller audit and settled scope — 2026-11-13

Audited after boo-2bl9 integration and at `27dc49fd`. Playback still throws
for missing ids in restoreHistory, restoreBookmark and editBookmark. Its
independent record refresh can now adopt a deletion while an audio command is
held, so tests must cover a queued restore whose record disappears before the
restore executes. ReaderSession already returns normally for absent bookmark
restore/edit, but restoreHistory still throws. Both media use the timeline's
unawaited restore callbacks; bookmark editors await storage work after their
sheet closes. The settled rule applies to all six owner operations: a missing
record is an ordinary stale user action, so complete normally without moving,
opening, resurrecting or writing records, changing Undo, or showing an error.

Keep genuine argument checks, command failure propagation, storage failure
reporting, existing account/command/revision guards and successful operations.
Do not catch every ArgumentError at the UI or swallow unrelated failures in
the command queue. The record owner resolves existence when it handles the
action. Reuse the existing interfaces and queues; no new stale-action service,
pending inventory, result protocol, cross-account lookup or UI feature is
needed. There is no unresolved product choice in this rule.

Build meaningful red cases for deleted audio history/bookmark restores and
bookmark edits, plus the reader history gap. Protect the existing no-op reader
bookmark behavior with realistic stale-action coverage where missing. Exercise
the audio queue with a controlled held command and a real adopted deletion,
and the editor path where a bookmark disappears while its sheet is open.
Check no uncaught error, no decoder/reader move, no unintended record write or
resurrection, and continued successful commands afterward. Cover account
replacement without crossing account records; use existing guards, not new
identity policy. Include actual sync/store fixtures and durable rereads where
they establish that deletion stays deleted. Preserve genuine-error tests.

Own narrowly necessary changes in lib/playback/playback.dart and
lib/reader/session.dart, related playback/reader/sync regression tests, and
only a UI test if required to prove the editor callback. Concurrent typed
sync-conflict work owns its store/coordinator/views; do not change that model.
Audit actual current callers and tests rather than relying on the old line
numbers. Useful fixtures include test/sync/playback_refresh_test.dart,
test/playback/command_queue_test.dart, test/playback/history_test.dart,
test/playback/records_test.dart, test/playback/root_history_test.dart,
test/reader/session_test.dart, test/reader/history_pages_test.dart and
test/reader/bookmark_names_test.dart.

Run focused regressions, affected playback/sync/durability/app/reader/crossings
suites, full Flutter tests, changed-file formatting, affected analysis and
complete original-base diff whitespace checks through Nix. Concurrency at most
two; one heavy command at a time. Exactly one fresh Astra high read-only
reviewer after the Astra xhigh build; fix findings directly, no second review.
Keep all failed runs and exact commands, counts, skips and limits in ticket
evidence. No devices/browser, coverage/mutations, timing-threshold changes,
push/PR/deployment or closure. Parent integrates and closes.

## Launch — 2026-11-13

Astra xhigh lead launched from `cce56bd53c5a2cd4c4611c84507f161be9544272`.
Running, stage uncertain; branch not yet reported. Exactly one fresh read-only
Astra high reviewer authorized. Parent integrates and closes.

- clientRequestId: bookfin-t5-6lnm-astra-20261113-1
- taskId: node:delegated-task:command%3Amcp%3Ade3a91ba-7d8c-4ac2-9796-a93ca278e01c%3Adelegate-task%3Abookfin-t5-6lnm-astra-20261113-1
- childThreadId: thread:delegated-task:command%3Amcp%3Ade3a91ba-7d8c-4ac2-9796-a93ca278e01c%3Adelegate-task%3Abookfin-t5-6lnm-astra-20261113-1
- Link: <t3-thread://v2/38d3e8fa-8572-4c2a-8a3b-2eb7c344dfce/thread:delegated-task:command%3Amcp%3Ade3a91ba-7d8c-4ac2-9796-a93ca278e01c%3Adelegate-task%3Abookfin-t5-6lnm-astra-20261113-1>

## Implementation evidence — 2026-11-13

Worktree `/Users/alexispurslane/.t3/worktrees/bookfin/t3-f25a0de2`, branch
`t3/ignore-stale-history-bookmarks`, started clean at original base
`cce56bd53c5a2cd4c4611c84507f161be9544272`. No inherited changes were removed.

Implemented only the four missing-record guards: Playback history restore,
bookmark restore/edit, and ReaderSession history restore. Existing reader
bookmark restore/edit remain unchanged. Actual timeline and editor callers
were audited. No fork or sync-conflict model change.

Red proof: 14 expected missing-record failures, with the three existing reader
bookmark cases passing. Green proof includes adopted remote deletion during a
held audio pause, both history directions, actual open-editor callback races,
account replacement, decoder/reader movement checks, unchanged Undo and
records, SQLite restart rereads, later successful commands, and retained
argument/storage/programming-error regressions.

Required Nix checks: focused 94 passed; affected playback/sync/durability/app/
reader/crossings suites 2,724 passed and 24 skipped; full Flutter suite 3,622
passed and 27 skipped. No failures in those completed green suites. The only
later code change added braces to a test for analysis; final formatting,
94 focused tests, and affected analysis passed. Analysis reports no issues.

Exact commands, all earlier failures and interrupted attempts, logs, caller
audit, skipped-test inventory and limits are in
`docs/evidence/t5-6lnm/validation.md`, `commands.json`, and `full-suite.json`.
Raw outputs remain at this worktree's `.cache/t5-6lnm/` paths. The complete
original-base diff passed the Nix whitespace check, including staged new files
and evidence. One fresh read-only Astra high review follows the local commit.
No devices/browser, coverage/mutations, timing-threshold edits, push/PR,
deployment, integration, acceptance, or closure. Parent owns those stages.
