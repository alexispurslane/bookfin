---
id: boo-gcu6
status: closed
deps: []
links: []
created: 2026-11-12T23:41:00Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---

## Launch — 2026-11-13

Astra xhigh lead launched from eb64fe705198fba0563df0a188939f6e57e16f35. Running, stage uncertain; branch not yet reported. Exactly one fresh read-only Astra high reviewer authorized. Both latest PDF and EPUB integrations are committed prerequisites; parent combined verification is running independently.

- clientRequestId: bookfin-boo-gcu6-astra-20261113-1
- taskId: node:delegated-task:command%3Amcp%3Ade3a91ba-7d8c-4ac2-9796-a93ca278e01c%3Adelegate-task%3Abookfin-boo-gcu6-astra-20261113-1
- childThreadId: thread:delegated-task:command%3Amcp%3Ade3a91ba-7d8c-4ac2-9796-a93ca278e01c%3Adelegate-task%3Abookfin-boo-gcu6-astra-20261113-1
- Link: <t3-thread://v2/38d3e8fa-8572-4c2a-8a3b-2eb7c344dfce/thread:delegated-task:command%3Amcp%3Ade3a91ba-7d8c-4ac2-9796-a93ca278e01c%3Adelegate-task%3Abookfin-boo-gcu6-astra-20261113-1>

# Write the settings of each record domain only when they change

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: confirmed. lib/playback/store.dart:900-913, 1216-1225 and 1444-1458. The listening settings and the reading settings share one account row. After the user changes the view setting of one PDF, `_smallSettings` returns false. From then on, every listening save (about one for each media-second) and every sync acknowledgment starts an isolate through `compute`, then encodes and rewrites the reading settings again. Store the settings of each domain separately and write them only when they change. Related closed ticket: boo-lj72.


## Parent caller audit and settled scope — 2026-11-13

At 15942f1c, ResumeStore._persist still encodes the combined metadata for SQLite commits, including unrelated nested reading settings; the existing scalar-only fast path rejects those maps. Native commits also update record_accounts metadata alongside journal changes. Preserve the existing ResumeStore/RecordDatabase ownership while storing each domain's settings independently and persisting only actual settings changes. A record-only save or upload acknowledgment must not encode or rewrite unchanged reading/listening settings. Keep durable settings and journal changes in one transaction when both change. No new writer abstraction or parallel pending-action inventory.

Use the current record journal, incremental current-state restore, commit encoding and reconstruction paths. Preserve old native database and preference migration, account isolation, settings restore, listening/reading snapshots and caller compatibility, pending records, retained unreadable originals, conflicts, deletion state, cursors, corruption retain-and-report, and retry after failed commits. A failed write must not mark settings as durably saved. Explicit recovery/reconstruction may rewrite whole state, but normal updates must not. Keep browser preference compatibility and its atomic whole-account limitations honest. Expensive settings comparisons/copies must not replace the avoided encoding with equivalent repeated UI-isolate work.

Own playback/store.dart, database.dart and narrowly necessary domain save wiring/tests. Reuse settled per-domain settings ownership rather than redesigning all record writers or typed record APIs (boo-n7no/boo-w6m2). Show a meaningful old-code failure with real SQLite operation/encode counts after nontrivial PDF settings exist, then verify listening saves, sync acknowledgments, actual settings changes, failure/retry, migration and reopen. Counts measure work; no Android latency threshold or timing claim.

Required Nix checks: focused real-file regressions, sync/playback/durability/app and affected reader/settings suites, full Flutter suite, affected analysis/format/diff. Concurrency two, one heavy command per owner. Astra xhigh implementation/direct fixes, exactly one fresh read-only Astra high reviewer; preserve original verdicts and resolve findings with evidence. No devices/browser, coverage, mutations, push, PR or closure. Parent owns integration, acceptance and closure.

## Implementation worktree — 2026-11-13

Lead checkout: `/Users/alexispurslane/.t3/worktrees/bookfin/t3-c6dae15e`,
initial recorded branch `t3/c6dae15e`, final branch
`t3/persist-settings-on-change`, original base
`eb64fe705198fba0563df0a188939f6e57e16f35`.

Implemented schema-six domain settings rows within RecordDatabase's existing
transaction. Native record-only saves and batch acknowledgments leave both
settings domains untouched. ResumeStore compares submitted settings against
its last committed account state; a failed transaction cannot advance that
baseline. ReadingChanges can omit settings, and ReaderSession uses bounded
comparisons of scalar preferences and the identity of its replaced PDF map.
Legacy text-sizing and clamped-size migrations remain real settings changes.

Schema upgrades retain legacy combined metadata until the first successful
account migration. Account repair keeps exact damaged settings rows alongside
the existing retained action and object rows. Normal current-state restore,
explicit reconstruction, snapshot readers, account isolation, and browser
whole-account preferences use the existing owner paths.

Real SQLite regression tests reproduce the original repeated work after
2,000 nested PDF choices. They cover zero settings work on unrelated listening
saves, first and later reading saves, and batch acknowledgments; one-domain
settings changes; transaction rollback/retry; old schema/preference migration;
reopen; and exact damaged-domain retention. See
`docs/evidence/boo-gcu6/commands.md` for commands, results, and all iteration
failures. Logs accompany that record as compressed files.

No product fork was found. No coverage, mutation testing, device/browser work,
push, PR, merge, closure, or worktree removal was performed. The parent owns
integration, acceptance, hardening, and closure. Review and final checks are
still in progress until the completion evidence below is recorded.

### Check completion before review

- Full Flutter suite: 3,530 passed, 27 explicitly skipped; all required affected
  suites are included. Final log: `docs/evidence/boo-gcu6/full-final.log.gz`.
- Changed analysis: eight Dart files, no issues. Format check: eight files,
  zero changes. Diff check passed.
- Strengthened native migration with an exact retained wire body and cursor
  31. A failing invariant check exposed a lost cached original count; the
  normal persistence/reconstruction path now retains the restored count.
  All 133 focused durability/recovery/migration tests passed after that fix.
- At this checkpoint, the single authorized read-only Astra high review was
  the remaining gate. All implementation commands had finished. Original
  iteration failures and their resolutions remain in the evidence record.

### Review completion and integration handback

The sole authorized read-only reviewer completed the full original-base diff
through implementation commit `9af2b94356c9cb9f7ce59d3bff532294d9d8b340`.
Original verdicts: correctness pass, ticket fulfillment pass, and software
design pass. There were no findings. Full original evidence and gaps are
preserved in `docs/evidence/boo-gcu6/review.json`.

The reviewer used the saved execution evidence and independently verified its
29 compressed log hashes, without rerunning tests. Device, process-kill, and
latency claims remain outside this evidence; 27 explicitly gated checks remain
skipped. No material acceptance requirement remains unverified within the
authorized host-test scope.

The review's branch documentation gap is resolved by recording both the
initial and final branch names. The lead issued no checkout switch or branch
rename. The final evidence commit contains only review and verification
documentation. Both final diff checks passed; exact commands and logs are in
the verification record. All owned commands and the reviewer have finished.
No product fork remains. Ready for parent integration; ticket status stays
in progress because the parent owns integration, acceptance, hardening, and
closure.

## Parent integration and closure — 2026-11-13

Verified the clean child checkout and reported branch/head. Inspected the full
original-base diff, production callers, account migration/reconstruction,
settings comparison and reader retry ownership, all changed tests, original
review verdicts and saved failures/passes. All 31 compressed log hashes match.
Integrated `9af2b943` as `9349d717` and evidence `13902357` as `992b7310`, without
conflicts. Parent launch records remain in this ticket. No production changes
were needed after inspection.

The parent verified the combined settings and section-stylesheet implementation
through Nix. Production and tests stayed unchanged throughout these checks:

- `dart format --output=none --set-exit-if-changed` on the eight changed Dart
  files: zero changes. Log `/tmp/boo-gcu6-integrated-format.log`.
- `flutter analyze --no-pub lib/playback lib/reader/session.dart test/playback
  test/reader/reading_changes_test.dart test/reader/session_native_test.dart
  test/research/current_restore_measurement_test.dart`: no issues.
  Log `/tmp/boo-gcu6-integrated-analysis.log`.
- `flutter test --no-pub --concurrency=2 --reporter=expanded`: 3,547 passed,
  27 existing gated skips, zero failures in 4:54. The full suite includes all
  required affected suites and the real SQLite settings work-count regressions.
  Log `/tmp/boo-gcu6-integrated-full.log`.
- The sequential Nix driver exited zero; log
  `/tmp/boo-gcu6-integrated-driver.log`. Complete integration diff check
  `git diff --check 912c3012 HEAD` passed.

The parent's full run is additional execution, not reviewer reapproval. The
original review verdicts and limits remain unchanged. Native work counts do not
establish Android latency; browser preferences still write a whole account.
Android acceptance remains blocked by `t1-dth0`; coverage/mutations await user
acceptance. Known intermittent failures remain separate tickets even though
this parent run passed. No device/browser retry, publication or deployment
occurred. Implementation is merged and verified; the parent closes this ticket.
