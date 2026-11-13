---
id: boo-3y46
status: in_progress
deps: [boo-0931]
links: []
created: 2026-11-12T23:41:00Z
type: bug
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Keep discovery going past a server object that this build cannot apply

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: confirmed. lib/playback/store.dart:504-512 and 546-549 throw a FormatException for a tombstone, or for an action value that this build cannot decode, before the cursor advances. The object stays on the append-only server, so every later sync on that device throws on the same page and the device receives no later record from any device. lib/sync/coordinator.dart:321-324 reports the failure as "plugin missing". test/sync/transport_test.dart:211 and closed ticket t9-of05 lock the throw in, so a change needs a user decision. Proposed model: keep the object, apply the rest in causal order, hide the unreadable value, report a count, and give the case its own failure kind. Skip tombstones, or remove DELETE from the plugin.


## Notes

**2026-11-13T01:09:38Z**

User decision, 2026-11-12: keep it, skip it, go on. The phone stores a record that it cannot apply, advances the cursor, receives everything after it, and shows a quiet count of records that need a newer Bookfin. The case gets its own failure kind, not pluginMissing. This reverses the stop that t9-of05 and test/sync/transport_test.dart:211 lock in, so that test changes with this ticket. Add a test for the sync after such a record.

## Astra implementation scope

Implement the recorded user decision on top of boo-0931's committed-current-state restoration. A valid discovery page may contain individual remote objects that this build cannot apply, including unknown versions or values, malformed individual payloads and server tombstones. Retain each such object's original payload and identity/sequence information durably for its account before moving the discovery cursor. Continue receiving later pages and the next sync; apply later readable records where their causal prerequisites are present. Never invent missing predecessors, turn a server tombstone into permission to erase local history, or weaken immutable duplicate checks. Existing valid unknown kinds must remain hidden and retained for a future build.

LocalResumeStore owns the durable transition and retention; RecordTransport owns wire parsing; RecordSync owns scheduling and outcome reporting. Commit received records, retained unreadable objects and cursor together, or commit none. Repeated delivery must not lose records or inflate the count. Keep a quiet per-account count in the existing Sync UI and give unreadable remote records their own outcome/failure kind, separate from a missing plugin. Preserve raw data for a future build or retry; do not delete or coalesce it. Malformed whole-page boundaries, unsafe cursors, local database failures and absent plugin routes still report their actual failure rather than being silently skipped.

Preserve bounded native startup from boo-0931, all retained originals, its recovery protections for deletions/conflicts and accepted server copies, boo-s11s batching and grouped acknowledgments, and boo-hmrp local-first upload scheduling. No plugin protocol/deployment change is needed. The concurrently running boo-721h owns the local-account/credential distinction; do not duplicate it. Parent resolves integration overlap.

Required meaningful red-green evidence includes the rejected object between readable records, a later discovery page, the next sync, native reopen, retained raw payload equality, retry without duplicate counts, account isolation, transaction failure/rollback, local pending writes, unknown kind/version, malformed individual payload, server tombstone, and preserved causal gaps and conflicts. Exercise both legacy and batch transport paths and the quiet UI/status distinction. Update the old stop-on-malformed-remote test. Run sync, durability, playback, app and affected reader persistence tests; affected analysis/format; and the full Flutter suite at concurrency two through Nix, one heavy command at a time.

Implementation/direct fixes use codex/gpt-6-astra xhigh; exactly one fresh read-only reviewer uses Astra high. Parent owns integration, acceptance, hardening and closure. No device, coverage, mutation, push, PR or deployment work.

## Delegated task

Original base: 374390da6e2b37415ed98807ac962b05a9f68ea0.
Client request ID: bookfin-boo-3y46-astra-20261113-1
Task ID: node:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-boo-3y46-astra-20261113-1
Child thread ID: thread:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-boo-3y46-astra-20261113-1
Thread: <t3-thread://v2/38d3e8fa-8572-4c2a-8a3b-2eb7c344dfce/thread:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-boo-3y46-astra-20261113-1>
Launch returned running on codex/gpt-6-astra with reasoningEffort xhigh. Stage and branch not yet reported. Completion delivery is automatic.

## Implementation evidence — November 13

Initial identity: `/Users/alexispurslane/.t3/worktrees/bookfin/t3-4c5cb12a`, branch
`t3/continue-record-discovery`, clean HEAD and original review base
`374390da6e2b37415ed98807ac962b05a9f68ea0`. The checkout was supplied by T3. No
checkout creation, switch or reset occurred. The parent had already started this
ticket. It remains in progress for parent integration and closure.

### Result

Schema five adds account-scoped retained wire originals to the existing database.
The store commits originals, admitted actions and cursor together; accepted
server-copy repair and its archive are part of the same page transaction. Native
startup reads the count without reading wire bodies. A dedicated quiet signal
feeds the Sync page, including after a reopen before any exchange. Retry changes
only interpretation status and never removes originals. The count is by server
identity; separate wire events, including tombstones, keep their own original bytes.

RecordJournal owns preserved-version validation and causal waiting. Unknown valid
kinds still enter the journal; invalid envelopes/values do not grant coverage.
Missing preserved originals wait for end-of-discovery retry. Malformed preserved
references do not stop independent records. Local pending actions survive every
retention and rollback path. A pending action whose server identity was retired
stays pending while discovery continues, then reports `uploadRejected`; it never
becomes `pluginMissing` or schedules an immediate retry loop. All other upload
failures preserve their previous behavior and grouped acknowledgments.

Kept-copy and authoritative-file recovery carry the originals. Reconstruction
refuses to commit if known retained originals are unavailable, just as it already
refuses to lose current deletion or conflict state. Preference migration keeps
originals too. The research document records the ownership, storage and retry model.
No plugin file or protocol was changed.

### Red-green and intermediate evidence

All Flutter commands use Nix and concurrency two. Logs are under `/tmp`.

| Evidence | Observed result |
| --- | --- |
| `boo-3y46-red.log` | Nine meaningful failures: malformed JSON/value, unsupported version and tombstone stopped discovery in both protocols, plus the superseded old stop test. |
| `boo-3y46-status-red.log` | Three meaningful failures: the distinct outcome and quiet UI count were absent. |
| `boo-3y46-recovery-red.log` | Preference migration omitted originals; a changed readable payload reused an unreadable identity. An initial raw-page test damaged the table while its count still read a healthy index; that fixture expectation was corrected. |
| `boo-3y46-recovery-damage-red.log` | Two meaningful failures: damage to original bodies did not enter the owner's reconstruction path. |
| `boo-3y46-retention-check.log` | Four meaningful failures: kept-file recovery omitted originals and retry rewrote wire field order instead of retaining exact stored bytes. |
| `boo-3y46-preserve-red.log` | Two meaningful failures: a malformed preserved-version reference stopped discovery. |
| `boo-3y46-page-repair-red.log` | Two meaningful failures: repairing an audio original failed to mark newly received reading records stale. |
| `boo-3y46-retired-upload-red.log` | Two meaningful failures: a server tombstone for a pending local action stranded discovery. |
| `boo-3y46-count-red.log` | Two meaningful failures: separate wire events for one identity inflated the quiet record count. |
| `boo-3y46-discovery-final.log` | All 54 discovery, retention, recovery, causal, count and boundary tests pass. |

The first test invocation lacked package configuration. `flutter pub get` completed
in the pinned shell (`boo-3y46-pub-get.log`); that setup failure is not red evidence.
Early green attempts contained Dart type-inference/compiler errors and lint errors,
which were corrected. The startup-observation fixture briefly queried an empty
second account through a deliberately narrow observer without a transaction
method (`boo-3y46-bounds.log`); the observation now stays on its seeded account.
Account isolation remains covered separately. None of these fixture/setup errors
is claimed as a behavioral red.

The first sync/durability run reached 391 passes and three opt-in skips, with five
scheduling failures before waiting in a sixth scheduling test. Its fake store did
not supply the new durable-count operation. Only that run's verified process tree
was terminated (PIDs 14693, 14718, 14719, 15037, 15101); the owning command exited
143. The fake now supplies empty count/retry results. No process was stopped by
name. A later run found three old upload-failure cursor expectations changed by
an over-broad discovery continuation. Continuation was narrowed to server
retirement (HTTP 410), preserving ordinary failure behavior. The focused retry,
batch acknowledgment and discovery run then passed 50 tests in
`boo-3y46-retired-upload-green.log`.

The retained-view invariant check now reads preference-backed accounts when
checking their views. The added count query exposed this existing gap through the
server-copy regressions (`boo-3y46-preserve-green.log`); the subsequent focused run
passed all 53 tests (`boo-3y46-focused-final.log`). This supplies a direct fix for
the behavior tracked by tc-eri9u, without closing that ticket here.

### Required final verification

The sequential script `/tmp/boo-3y46-final-checks.sh` runs in the pinned Nix
shell. Its commands, with each command's output redirected to the named log:

```sh
dart format --output=none --set-exit-if-changed lib/playback/database.dart lib/playback/record_codec.dart lib/playback/store.dart lib/sync/coordinator.dart lib/sync/journal.dart lib/sync/screen.dart lib/sync/transport.dart test/research/current_restore_measurement_test.dart test/sync/alert_test.dart test/sync/batch_api_test.dart test/sync/schedule_test.dart test/sync/screen_test.dart test/sync/status_test.dart test/sync/transport_test.dart test/sync/unknown_records_test.dart test/sync/unreadable_discovery_test.dart
flutter analyze --no-pub lib/playback lib/sync test/sync test/durability test/playback test/app test/research/current_restore_measurement_test.dart
flutter test --no-pub --concurrency=2 test/sync test/durability test/playback test/app test/reader/persistence_test.dart test/reader/records_test.dart test/reader/history_pages_test.dart test/reader/dock_history_test.dart test/reader/unread_records_test.dart test/reader/reading_moves_test.dart --reporter expanded
flutter test --no-pub --concurrency=2 --reporter expanded
```

Actual outer command (the lint fix and formatting completed before the checks):

```sh
nix develop --command bash -c 'dart fix --apply --code=curly_braces_in_flow_control_structures test/sync/unreadable_discovery_test.dart > /tmp/boo-3y46-final-lint-fix.log 2>&1 && dart format test/sync/unreadable_discovery_test.dart >> /tmp/boo-3y46-final-lint-fix.log 2>&1 && bash /tmp/boo-3y46-final-checks.sh'
```

| Check | Result | Log |
| --- | --- | --- |
| Changed-file formatting | 16 files, zero changes | `/tmp/boo-3y46-format-final.log` |
| Affected analysis | No issues | `/tmp/boo-3y46-analysis-final.log` |
| Required affected suites | 994 passed, 3 existing opt-in skips, zero failures | `/tmp/boo-3y46-affected-final.log` |
| Full Flutter suite | 3,370 passed, 27 existing opt-in/external-fixture skips, zero failures; 5m00s | `/tmp/boo-3y46-full-final.log` |
| Diff whitespace | Clean | `git diff --check` |

Before the one fresh review, `orchestrator_capabilities` confirmed the supplied
`codex/gpt-6-astra` target supports `reasoningEffort: high`. No model was substituted.
The complete sequential command exited zero; all build/test commands finished
before review delegation. The review will assess the committed diff from the
original base above. No reviewer has been reused.

Parent owns integration, acceptance, hardening and ticket closure. No device or
browser work, coverage, mutations, deployment, push or PR work was performed.

### One fresh review and direct resolutions

Review task `node:delegated-task:command%3Amcp%3Ace4ea467-8189-428c-9b4f-fa5850e90a60%3Adelegate-task%3Aboo-3y46-review-astra-20261113-1`
completed on `codex/gpt-6-astra`, `reasoningEffort: high`. It reviewed the complete
diff from `374390da6e2b37415ed98807ac962b05a9f68ea0` to
`876a478646de87892adc8c5c43064ad9cddf0a3f`. Its separate correctness,
ticket-fulfillment and design assessments were all `changes-required`; none was
`unverified`. The reviewer ran no builds or tests, edited nothing and started no
children. There was no second review or claimed reviewer re-approval. The ticket
lead fixed all findings directly at the authorized Astra xhigh setting.

| Finding | Original evidence and severity | Resolution and executed evidence |
| --- | --- | --- |
| R1 | High. Preference migration supplied originals in `RecordCommit.objects`, while file reconstruction used `_objectWrites`; a damaged first commit could reconstruct an advanced cursor with zero retained originals. User/Ousterhout: callers had to coordinate two representations. | Normal saves, prepared migrations and account repairs now stage the exact prepared commit's originals through one `_stageCommit` transition before attempting SQLite writes. Recovery consumes that same staged input. The regression damages the real `record_objects` table after preference restoration, before the first commit. Both protocol variants failed with count zero before the fix and now preserve count, cursor and exact original body through reconstruction and reopen, with invariants checked. |
| R2 | Medium. HTTP 410 continued discovery but then threw before `refreshWriters`, leaving actual Playback and reader sessions stale. | The coordinator performs the same stale-writer refresh after completed and incomplete exchanges, while keeping exchange failure, pending writes and the previous successful-sync time. Both protocol regressions failed because the live player lacked the received bookmark. They now check live Playback and reader bookmarks over two successive rejected-upload exchanges after startup recovery has finished. |
| R3 | Medium. HTTP 410 used `remoteUnreadable`, so the Sync page hid the failure and falsely claimed the phone matched Jellyfin. User/Ousterhout: one outcome meant both completed exchange and rejected upload across several consumers. | `uploadRejected` now means an incomplete upload; `remoteUnreadable` retains its meaning of a completed exchange with unreadable objects. The existing quiet count remains independent. The page reports “Not syncing” and an upload failure with Retry; it keeps the previous success time without claiming current success. UI regressions before the first successful exchange and after an earlier success both failed on the false match claim and now pass. The original tombstone test now expects `uploadRejected`. |

The first attempted regression command had a fixture compile error: it called
`ReadingLocation.encode`, which does not exist. `/tmp/boo-3y46-review-red.log`
records that setup error; it is not red evidence. The fixture now supplies the
existing anchor format. The corrected command used `--name` for the regex filter,
not `--plain-name`.

```sh
nix develop --command flutter test --no-pub --concurrency=2 test/sync/unreadable_discovery_test.dart test/sync/screen_test.dart --name 'file damage during preference migration|a rejected upload' --reporter expanded
```

This produced six meaningful failures in
`/tmp/boo-3y46-review-behavior-red.log`. After fixes, the same command passed all
six in `/tmp/boo-3y46-review-green.log`. R1 also passed separately with
`--plain-name 'file damage during preference migration'` in
`/tmp/boo-3y46-review-r1-green.log`. The migration fixture was then reduced to a
small payload; its existing worker boundary still permits damage at the same
point. No production fault switch or test-only policy was added.

```sh
nix develop --command bash -c 'dart format lib/playback/store.dart lib/sync/coordinator.dart lib/sync/screen.dart test/sync/unreadable_discovery_test.dart test/sync/screen_test.dart > /tmp/boo-3y46-review-format.log 2>&1 && flutter test --no-pub --concurrency=2 test/sync test/durability --reporter expanded > /tmp/boo-3y46-review-focused.log 2>&1'
```

The broader run passed 424 tests with three existing opt-in skips and no failures.
The Nix shell reports unavailable iPhone SDKs; these host tests need neither SDK.
No device validation was attempted or claimed.

The review's nonblocking cost note remains explicit: counting retained wire
events scans their index, and explicit retry reads retained wire originals,
including ones already interpreted. Ordinary current-state restore does not
decode their bodies or the complete action history. No constant-time or Android
latency claim is made. No user-visible design forks remain.

### Required verification after review fixes

`nix develop --command bash /tmp/boo-3y46-post-review-checks.sh` runs the same four
sequential required commands recorded above. It uses separate
`/tmp/boo-3y46-post-review-*-final.log` files, preserving the pre-review evidence.

| Check | Result | Final log |
| --- | --- | --- |
| Changed-file formatting | 16 files, zero changes | `/tmp/boo-3y46-post-review-format-final.log` |
| Affected analysis | No issues | `/tmp/boo-3y46-post-review-analysis-final.log` |
| Required affected suites | 1,000 passed, 3 existing opt-in skips, zero failures; 1m09s | `/tmp/boo-3y46-post-review-affected-final.log` |
| Full Flutter suite | 3,376 passed, 27 existing opt-in/external-fixture skips, zero failures; 5m03s | `/tmp/boo-3y46-post-review-full-final.log` |

The complete sequential command exited zero. `git diff --check` is clean.
All commands and the sole reviewer finished before the integration report.
R1, R2 and R3 have recorded resolutions with executed red-green evidence and
passing required checks. No findings, material unverified assessments or design
forks remain unresolved. The final report gives the ordered implementation and
fix commit SHAs. Parent alone integrates, accepts, hardens and closes the ticket.
