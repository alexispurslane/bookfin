# t5-6lnm validation

## Checkout and scope

- Worktree: `/Users/alexispurslane/.t3/worktrees/bookfin/t3-f25a0de2`.
- Branch: `t3/ignore-stale-history-bookmarks`.
- Original base and initial HEAD: `cce56bd53c5a2cd4c4611c84507f161be9544272`.
- Initial `git status --short` and original-base-to-HEAD log were empty. No inherited edits or commits were removed.
- Read the ticket's Parent caller audit first, project AGENTS.md (no CLAUDE.md exists in this checkout), product plan, builder role, software-design, test-driven-development and its good-test reference, and ultracode-orchestration.
- `tk ready` and `tk dep tree t5-6lnm` confirmed that boo-2bl9 is closed. `tk start t5-6lnm` retained its in-progress status. Parent owns integration, acceptance, hardening, and closure.

## Caller audit and implementation

| Owner operation | Actual callers and behavior | Change |
| --- | --- | --- |
| Playback.restoreHistory | `lib/playback/timeline.dart` routes Before and Go to through unawaited callbacks. Existence is resolved inside the existing audio command queue. | Return normally when absent. |
| Playback.restoreBookmark | The same timeline routes bookmark Go to through an unawaited restore callback. | Return normally when absent. |
| Playback.editBookmark | Timeline Rename starts `editAudioBookmark` in `lib/playback/records_screen.dart`; it awaits the editor result, then edits by ID. | Return normally when absent. |
| ReaderSession.restoreHistory | The timeline routes reading Before and Go to to the session. | Return normally when absent. |
| ReaderSession.restoreBookmark | The timeline routes reading bookmark Go to to the session. | Already returns when absent; regression tests only. |
| ReaderSession.editBookmark | Timeline Rename starts `editReadingBookmark`; it awaits the editor result, then edits by ID. | Already returns when absent; regression tests only. |

No queue, sync protocol, store model, UI production code, or account policy changes.
The existing owners decide record existence. No catch-all handler or new service was added.
The remaining operation bodies and their command/account/revision guards are unchanged.

## Regression evidence

- The audio fixture is the integrated boo-2bl9 fixture: real LocalResumeStore, RecordTransport, RecordSync, a remote RecordJournal, and the existing controlled HeldEngine. Both preferences and SQLite run each race.
- A pause stays held while a later restore or edit waits in the queue. Sync adopts a real deletion before the pause releases. The stale action then completes normally. Tests check decoder load/seek counts and position, unchanged Undo, no write after the pause, no extra history beyond the pause, no error or save failure, and a later successful seek. SQLite rereads after a database restart establish that the record stays deleted.
- The audio editor tests open the real History timeline, expand a bookmark, tap Rename, adopt a remote deletion while the editor is visible, and tap Save bookmark. A following harmless queued command lets the widget test drain the real command queue. Tests check no uncaught error, write, resurrection, movement, history change, or Undo change; adding another bookmark still works.
- The reading tests use a real SQLite store and sync transport. A viewport double reports confirmed addresses in an admitted two-chapter EPUB; it observes display calls, while the loader observes opens. The stale actions preserve the current place, Undo, saved snapshot, pending upload actions, and the deletion after restart. The reading editor test uses the real timeline callback and editor.
- Account replacement tests call all three owner operations with IDs retained from the earlier account, check that neither account is changed, then reopen the original account's records. Existing queue tests retain cancellation and command-local failure checks. Existing playback tests retain invalid speed/jump arguments, storage failures, programming errors, and valid restores and edits.

## Commands and outcomes

All builds, tests, formatting and analysis run through the pinned Nix development shell. Test concurrency is two. Heavy commands run one at a time in this worktree. All commands below run from the worktree above.

Full output files are retained under `.cache/t5-6lnm/` in that worktree. They are local evidence, not committed log dumps. No failed log was overwritten. Repeated Nix/Flutter notices about absent iOS SDKs and 38 newer incompatible dependency versions are retained; these are host Flutter tests, not iOS acceptance.

The complete executable commands, exit codes, and absolute log paths are in [commands.json](commands.json). The compact ledger below uses these aliases:

- `N` = `nix develop --command`.
- `F` = `flutter test --concurrency=2 --reporter expanded`.
- `A` = `test/sync/playback_refresh_test.dart`.
- `R` = `test/sync/stale_reading_actions_test.dart`.
- `H` = `test/playback/history_test.dart`.
- `Q` = `test/playback/command_queue_test.dart`.
- `S` = `queued.*deletion|editor completes|stale reading|account switches`.
- `W` = `editor completes|stale reading`.

Each command's stdout and stderr were redirected with `> .cache/t5-6lnm/<log> 2>&1`. A `bash -c` row puts everything after `bash -c` in one single-quoted shell argument, with the shown double quotes preserved.

| Log | Exact command using the aliases above | Result |
| --- | --- | --- |
| 01-red.log | `N bash -c dart format A R H && F A R H --name "S"` | Exit 1. Two compilation failures (missing EditionKind import, nonexistent TextPosition.toJson) plus the old account assertion failing with ArgumentError. Not accepted as the red gate. |
| 02-red.log | `N bash -c dart format A R && F A R H --name "S"` | Exit 1; 0 passed, 17 failed. Eight meaningful queued audio failures and one account failure; reader Undo setup and editor text finders were not yet valid. |
| 03-red.log | `N bash -c dart format A R && F A R --name "W"` | Exit 1; 0 passed, 8 failed. Reader fixture used a resource path without OPS/; editor finder omitted the book suffix. Setup failures, not red proof. |
| 04-red.log | `N bash -c dart format A R && F A R --name "W"` | Interrupted by this lead after six reader fixture-token failures and an audio widget wait. Sent SIGINT only to owned Flutter PID 47008; command and owned tester exited. Shell reported 0 for interruption; this was not a pass. |
| 05-red.log | `N bash -c dart format A R && F A R --name "W"` | Interrupted after reader history/account failures, two double-dispose fixture failures, and an audio widget wait. Temporary stage prints localized the wait. Sent SIGINT only to owned Flutter PID 48302; shell reported 0, not a pass. |
| 06-red.log | `N bash -c dart format A R && F A R --name "W"` | Reader missing-history failures and the real unawaited audio editor ArgumentError reproduced. Interrupted because widget teardown needed its fake and real event queues drained together. SIGINT only to owned Flutter PID 49028; shell reported 0, not a pass. |
| 07-red.log | `N bash -c dart format A && F A R H --name "S"` | Exit 1; 3 passed, 14 failed. All desired failures reproduced; audio widget cleanup also double-disposed sync. |
| 08-red.log | `N bash -c dart format A && F A R H --name "S"` | Exit 1; 3 passed, 14 failed, all failures at the intended missing-record ArgumentError guards. Existing reader bookmark restore/edit and reader editor cases passed. Meaningful completed red gate before production edits. |
| 09-history-green.log | `N F A --name 'queued history'` | Exit 1; 0 passed, 4 failed. The new no-op succeeded, but the test assumed one pause write. Both the confirmed pause sample and pause command save. Replaced this assumption with the observed write count when the pause completes. |
| 10-history-green.log | `N bash -c dart format A && F A --name "queued history"` | Exit 0; 4 passed. |
| 11-bookmark-restore-green.log | `N F A --name 'queued bookmark restore'` | Exit 0; 2 passed. |
| 12-bookmark-edit-green.log | `N F A H --name 'queued bookmark edit\|audio editor completes\|account switches'` | Exit 0; 5 passed. |
| 13-reader-green.log | `N F R` | Exit 1; 5 passed, 1 failed. Account-return assertion queried the open edition's bookmarks before reopening the edition. Corrected the test to open it before that assertion; all no-op assertions had passed. |
| 14-focused-green.log | `N bash -c dart format lib/playback/playback.dart lib/reader/session.dart H A R && F A R H Q` | Exit 0; 94 passed, no skips. |
| 15-affected.log | `N F test/playback test/sync test/durability test/app test/reader test/crossings` | Exit 0; 2,724 passed, 24 skipped, no failures. |
| 16-full.log | `N flutter test --concurrency=2 --machine` | Exit 0; 3,622 passed, 27 skipped, no failures. The structured completion reports success. |
| 17-format.log | `N dart format --output=none --set-exit-if-changed lib/playback/playback.dart lib/reader/session.dart H A R` | Exit 0; 5 files, 0 changed. |
| 18-analyze.log | `N flutter analyze lib/playback lib/reader lib/sync test/playback test/reader test/sync` | Exit 1; one new test statement needed braces. Added braces without changing behavior. |

The complete skip inventory, original runner reasons, and source conditions for boolean skips are in [full-suite.json](full-suite.json). The affected run's 24 skips are the same reader/plugin cases; the full suite adds three opt-in research measurements. No test was disabled for this ticket. Neither t5-rplx nor tf-il7u failed in these runs; this does not explain their earlier failures.

The full suite tested the final behavior. Its only later code change was adding braces to a test's `if` statement for the analyzer. Final formatting, focused tests, analysis and whitespace checks follow that correction.

## Final checks

| Log | Command | Result |
| --- | --- | --- |
| 19-final-focused.log | `N bash -c dart format --output=none --set-exit-if-changed lib/playback/playback.dart lib/reader/session.dart H A R && F A R H Q` | Exit 0; 5 files, 0 formatting changes; 94 tests passed, no skips. |
| 20-final-analyze.log | `N flutter analyze lib/playback lib/reader lib/sync test/playback test/reader test/sync` | Exit 0; no issues found. |

The complete original-base diff, including staged new tests and evidence, passed `N git diff --check cce56bd53c5a2cd4c4611c84507f161be9544272` (exit 0, `21-whitespace.log`). The committed implementation also passed `N git diff --check cce56bd53c5a2cd4c4611c84507f161be9544272 HEAD` (exit 0, `22-committed-whitespace.log`).

## Independent review

Exactly one fresh reviewer ran read-only with `isolation: "shared"`, `mode: "async"`, `role: "review"`, and target `codex/gpt-6-astra` at `reasoningEffort: "high"`. Capabilities were resolved once before launch. The reviewer completed on 2026-11-13, and its completed thread was read before saving its report.

Reviewer: <t3-thread://v2/38d3e8fa-8572-4c2a-8a3b-2eb7c344dfce/thread:delegated-task:command%3Amcp%3Add3c8374-c3f5-461e-a54d-1720447e59c6%3Adelegate-task%3At5-6lnm-review-astra-high-20261113-1>

Reviewed HEAD: `2ed2aa7b2b0687838c132b47c406a631f8acac0f`, against original base `cce56bd53c5a2cd4c4611c84507f161be9544272`.

| Assessment | Original verdict | Gaps |
| --- | --- | --- |
| Correctness | pass | None |
| Ticket fulfillment | pass | None |
| Design | pass | None |

The [original review report](review.json) preserves the reviewer's exact assessments, evidence, empty findings and gaps, and notes. The reviewer inspected the full nine-file diff, actual callers, and saved verification output. No findings required fixes or rejection. There are no unresolved gaps or forks. No second review was requested.

The review explicitly retains the full-suite-before-test-braces sequence and the 27 skipped tests as evidence limits. It makes no claim about the causes of earlier intermittent failures. Device/browser acceptance and hardening remain outside this ticket's scope.

The review-evidence commit changes only this ticket and saved evidence. No production or test changes followed the reviewed HEAD, so the completed Flutter checks remain applicable. Parent owns integration, acceptance, hardening, and closure; the ticket remains in progress.

The complete original-base diff including staged review evidence passed `N git diff --check cce56bd53c5a2cd4c4611c84507f161be9544272` (exit 0, `23-review-evidence-whitespace.log`). The final handoff records the subsequent committed-HEAD check.

## Limits

No devices, browser build or checks, coverage, mutation testing, timing-threshold changes, push, PR, deployment, merge, or ticket closure. Did not retry or bypass t1-dth0 or t7-3j9c. Did not run a separate combined t7-vq21/boo-8xyn job; the mandated full suite necessarily includes their existing tests. Did not alter boo-zs5i's typed-conflict work. Known intermittent t5-rplx and tf-il7u failures are not assumed to have a known cause.
