---
id: boo-o3cm
status: closed
deps: []
links: []
created: 2026-11-12T23:41:01Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Keep download records across a library change and bind Playback without waiting for the scan

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: confirmed. lib/downloads/local_downloads.dart:220-244 clears `_records` and scans the whole download tree again whenever the bind signature changes. The signature covers every source, so any library change, and every launch, shows "Not downloaded" for every book until the scan ends. The scan costs about 20 asynchronous filesystem operations for each source directory. lib/app/account_binding.dart:121-123 awaits it before `playback.bind`, so the restored book waits. Key the records by source id, compare the old and new source sets at a bind, read only the new ids, and drop only the removed ones. `localFile` already waits for each source, so Playback can bind at once. Related: boo-tapn.

## Astra implementation scope

Keep the download manager as the sole owner of verified local-file availability. A same-account library change keeps already restored records for unchanged sources, including their visible availability and transfer state. Restore only newly included or materially changed sources; remove only catalog membership for excluded sources, never their saved files. Existing retained-download inspection and explicit removal remain intact. Source revision, expected length and original-file identity checks must still invalidate incompatible records. A new account or explicit sign-out clears the previous account's visible records; same-account credential replacement must not expose another account or erase its local availability.

Start Playback binding without waiting for unrelated download restoration. Initial disk restoration remains necessary; do not claim a fresh process knows verified files before reading them. Parent inspection at c475c4f3 found that the survey's final sentence is too broad: `localFile` currently awaits the whole `_binding` inside `_lookup`, not a per-source restoration. Make requested-source readiness owned by Downloads, so a lookup waits for that source and the correct catalog plan without waiting for unrelated directories. Reuse the existing lookup, read ownership, command and binding paths; do not create a second availability authority or a test-only production policy option. Preserve account/generation checks, overlapping plans, accepted-command ordering, removal ownership and file verification. Keep CPU work off the UI isolate under the existing measured small-input rule.

Prove meaningful red-green behavior for unchanged availability during a held added-source restore; work bounded to new or changed sources; requested local-file access while an unrelated restore is held; Playback binding before the overall scan completes; overlapping small/large binds, same-account credential renewal, changed revision/length, removed/reintroduced sources, account switch, disposal, active download and queued commands. Use real files for restoration and controlled completion boundaries for races. Preserve corrupt-file and path-containment checks. Update old tests that explicitly demand serial Playback binding. Run downloads, app, playback, affected reader/download-consumer tests and sync; affected analysis/format; then the complete Flutter suite through Nix at concurrency two. One heavy command at a time.

boo-721h separately owns credential validity after a 401 and may overlap AccountBinding. Do not duplicate that behavior; the parent resolves integration. boo-56h7 owns paused playback after remote moves; boo-39cu owns removing a playing download. Leave both policies alone. boo-tapn's timing-test hardening remains separate; report any observed failure honestly rather than changing its threshold or adding a test-only injection.

Implementation/direct fixes use codex/gpt-6-astra with reasoningEffort xhigh. Exactly one fresh read-only reviewer uses the same model at high. Parent owns integration, acceptance, coverage, mutation testing and ticket closure. No devices, push, PR or deployment.

## Delegated task

Original base: 77e6d62e3a7a6f7018fdeba3efd9d8862278aa81.
Client request ID: bookfin-boo-o3cm-astra-20261113-1
Task ID: node:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-boo-o3cm-astra-20261113-1
Child thread ID: thread:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-boo-o3cm-astra-20261113-1
Thread: <t3-thread://v2/38d3e8fa-8572-4c2a-8a3b-2eb7c344dfce/thread:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-boo-o3cm-astra-20261113-1>
Launch returned running on codex/gpt-6-astra with reasoningEffort xhigh. Stage and branch not yet reported. Completion delivery is automatic. The parent has finished catalog integration checks and owns no running command. Existing boo-721h and boo-3y46 leads remain running at their last reported state.

## Implementation evidence (ticket lead, 2026-11-13)

Worktree: `/Users/alexispurslane/.t3/worktrees/bookfin/t3-a6b11727`.
Branch: `t3/preserve-download-records`.
Original review base: `77e6d62e3a7a6f7018fdeba3efd9d8862278aa81`.
The checkout was clean at that base. No checkout was created, switched or reset.

Downloads keeps one record per bound source, including that source's restoration future. Same-account plans retain compatible records and their active/pending transfers. Compatibility still covers source key/revision, expected bytes and original-file qualification; display metadata does not trigger restoration. Large-plan compatibility comparison shares the existing worker-isolate plan path and applies in call order. Account entry lists saved directories once; later changes inspect only added/incompatible sources. Removing catalog membership keeps the files for retained inspection or reintroduction.

Both plain lookup and owned reading wait for their requested source after the correct plan applies. Owned reading remains in the existing command queue. Full binding completion, accepted commands, transfer shutdown, explicit removal, account changes and disposal retain their ordering guards. Initial availability is unpublished until verification ends. AccountBinding starts Playback without awaiting whole-library restoration. Credential-expiry behavior and playing-file-removal policy remain outside this ticket.

The new `test/downloads/binding_test.dart` uses real saved files. Test-only filesystem wrappers complete ordinary reads in microtasks and hold selected operations with completers, so ordering assertions depend on the held operation, not elapsed time. Its 22 tests cover unchanged availability and narrow notifications; storage work bounded to added/changed sources; plain and owned lookup during a held initial scan; fresh verification; in-progress invariants; metadata/revision/length/original qualification; same-account credential renewal and the existing mobile-permission reset; overlapping small/large restoration and back-to-back worker plans; account switch; disposal; removed/reintroduced files; accepted reads and later removal; pending cancellation; and a preserved active transfer. AccountBinding's two old serial-binding expectations now assert immediate Playback binding.

### Red-green and iteration logs

All Flutter commands below ran in this worktree with `nix develop --command`, one heavy command at a time and `--concurrency=2`. Logs are local `/tmp/boo-o3cm-*.log` files.

| Command after `nix develop --command` | Result | Log |
| --- | --- | --- |
| `flutter test --concurrency=2 test/downloads/binding_test.dart test/app/account_binding_test.dart` | Initial test-authoring run: 18 pass, 3 failures (one compile/load failure plus the two expected binding failures). Corrected the test wrappers before accepting red evidence. | `/tmp/boo-o3cm-red.log` |
| Same command | Meaningful red: 18 pass, 8 behavioral failures. | `/tmp/boo-o3cm-red-behavior.log` |
| Same command | Green: 26 pass, 0 skip. | `/tmp/boo-o3cm-green-initial.log` |
| `flutter test --concurrency=2 test/downloads/binding_test.dart --plain-name 'fresh restoration'` | Meaningful red: 1 failure, availability published before verification. Fixed by keeping pending record facts unpublished. | `/tmp/boo-o3cm-red-verification.log` |
| `flutter test --concurrency=2 test/downloads test/app/account_binding_test.dart` | 215 pass, 0 skip. | `/tmp/boo-o3cm-downloads-1.log` |
| `flutter test --concurrency=2 test/downloads/binding_test.dart` | 18 pass, 1 meaningful failure: a new account waited for the old account's held restoration. Removed that cross-account dependency. | `/tmp/boo-o3cm-races-1.log` |
| Same command | 19 pass, 0 skip. | `/tmp/boo-o3cm-races-2.log` |
| `flutter test --concurrency=2 test/downloads/binding_test.dart --plain-name 'unfinished restoration satisfies'` | Meaningful red: 1 failure, invariant checker treated pending restoration as observed disk facts. Ownership remains checked while disk/queue invariants apply after restoration. | `/tmp/boo-o3cm-red-invariants.log` |
| `flutter test --concurrency=2 test/downloads/binding_test.dart` | 21 pass, 0 skip. | `/tmp/boo-o3cm-binding-final.log` |
| `flutter analyze lib/downloads lib/app/account_binding.dart test/downloads test/app/account_binding_test.dart` | First run found 7 style infos; fixed all. Latest run has no issues. | `/tmp/boo-o3cm-analysis.log`, `/tmp/boo-o3cm-analysis-final.log` |
| `flutter test --concurrency=2 test/downloads test/app test/playback test/sync test/reader test/speech/hearing_policy_test.dart` | First broader run: 2643 pass, 24 skip, no failure. Rerun follows the final invariant/refactoring changes and two additional tests. | `/tmp/boo-o3cm-affected.log` |

No coverage, mutation campaign, device action, wall-clock performance claim, timing-threshold change, push, PR, merge, publication or deployment was performed. Parent owns acceptance, hardening, integration and closure. Exactly one fresh read-only reviewer is pending the completed checks and implementation commit; final verification and review evidence follow below.

### Final compatibility check

The second broader run passed 2645 tests with 24 skips (`/tmp/boo-o3cm-affected-final.log`) after the invariant correction and the back-to-back plan test. Inspection then found that distinguishing account identity from credentials had also retained temporary mobile permission on credential renewal. That was an unintended policy change. `nix develop --command flutter test --concurrency=2 test/downloads/binding_test.dart --plain-name 'credential renewal still resets'` failed meaningfully (0 pass, 1 failure, `/tmp/boo-o3cm-red-policy.log`). Restored the existing permission reset on account or credential change without resetting records. `nix develop --command flutter test --concurrency=2 test/downloads/binding_test.dart` then passed all 22 tests with no skips (`/tmp/boo-o3cm-binding-policy.log`). The same affected analysis command again reported no issues (`/tmp/boo-o3cm-analysis-policy.log`). Required affected/full checks follow this final code change.

### Required verification on final implementation

- `nix develop --command flutter test --concurrency=2 test/downloads test/app test/playback test/sync test/reader test/speech/hearing_policy_test.dart`: 2646 passed, 24 skipped, no failures. Log: `/tmp/boo-o3cm-affected-policy.log`. All reader tests were included because callers use both plain and owned Downloads lookups, including persistence, admitted books, OCR, PDF and text reading. The speech hearing-policy consumer was included too.
- `nix develop --command flutter test --concurrency=2`: first full run had 3374 passed, 27 skipped and one failure. Log: `/tmp/boo-o3cm-full.log`. The failure was `test/reader/unread_records_test.dart:97`, “the next place after a failed read opens the records again without a flush”: expected one saved resume, found none. Existing ticket `t5-rplx` records the same intermittent failure and now carries this observation. Inspection found no use of LocalDownloads or AccountBinding in that test; its reader and record-store code are unchanged here. Its `pumpEventQueue` wait remains unchanged; the cause is not established.
- `nix develop --command flutter test --concurrency=2 test/reader/unread_records_test.dart`: unchanged immediate retry passed all 5 tests, no skips. Log: `/tmp/boo-o3cm-unread-retry.log`. A complete unchanged rerun follows; no failure was suppressed.
- `nix develop --command flutter test --concurrency=2`: unchanged full retry passed 3375 tests, 27 skipped, no failures. Log: `/tmp/boo-o3cm-full-retry.log`. The reader recovery test passed within this full run too. This does not establish the cause or resolve `t5-rplx`.
- `nix develop --command dart format --output=none --set-exit-if-changed lib/downloads/local_downloads.dart lib/app/account_binding.dart test/downloads/binding_test.dart test/app/account_binding_test.dart`: exit 0, four files, zero changes. Log: `/tmp/boo-o3cm-format-check.log`. Earlier formatting logs are `/tmp/boo-o3cm-format.log`, `/tmp/boo-o3cm-format-final.log`, `/tmp/boo-o3cm-format-policy.log`.
- `git diff --check`: passed. All owned build/test commands finished before review launch. No timing threshold or test wait was changed.

The implementation commit is ready for the one authorized read-only review of the entire original-base diff. Requested reviewer: provider `codex`, model `gpt-6-astra`, `reasoningEffort: high`, shared isolation, async mode, review role. Planned request identifier: `boo-o3cm-review-20261113-01`. Review acceptance remains pending; the parent alone integrates or closes this ticket.

## Independent review and direct fix (2026-11-13)

The one authorized fresh reviewer completed inspection of the entire diff from `77e6d62e3a7a6f7018fdeba3efd9d8862278aa81` to implementation commit `a457b8a917465f4b363cbf72a46cec2fbd04e37c`. The reviewer used `codex/gpt-6-astra`, `reasoningEffort: high`, review role, shared isolation and async mode, after the ticket lead called `orchestrator_capabilities` once. The reviewer started no children, edited no files and ran no builds or tests.

Review thread: <t3-thread://v2/38d3e8fa-8572-4c2a-8a3b-2eb7c344dfce/thread:delegated-task:command%3Amcp%3A1008241e-0482-4db2-ba3a-1ee0dd6df92a%3Adelegate-task%3Aboo-o3cm-review-20261113-01>.

These are the original assessments, not a claim of reapproval after fixes:

| Assessment | Original verdict | Evidence and gaps |
| --- | --- | --- |
| Correctness | changes-required | Retention, verification, account guards, transfer ownership and command ordering were preserved. R1 added unnecessary filesystem inspection on app resume. |
| Ticket fulfillment | pass | Implementation and controlled-completion tests cover retained availability, compatibility changes, both requested-source access paths, immediate Playback binding, overlapping plans, credentials, account isolation, disposal, removal and active/pending transfers. R1 blocked overall acceptance. |
| Design | pass | Downloads remains the sole availability/readiness owner. Readiness belongs to the existing record; readers keep the existing command/ownership path. The text-source index has one maintenance owner and an invariant. Sources: software-design User sections 4/6, Ousterhout information hiding and Muratori's restriction against speculative machinery. No separate design finding. |

### R1: unnecessary resume probes of never-downloaded sources

Severity: medium. Reviewed locations: `lib/downloads/local_downloads.dart:326` and `:1217`; app-resume caller: `lib/main.dart:351`. Trigger: bind a catalog with never-downloaded sources, then resume. Every source now needs a readiness record, but refresh still inspected every record as if it had stored files. With an existing account directory this added root/account/source checks for every absent source, before reaching later saved files. The reviewer requested a record-owned distinction for known storage, with real-file regression evidence and preserved missing/corrupt-file checks. No elapsed-time performance claim was made.

Accepted and reproduced before changing production code. Two tests bind a catalog with 122 never-downloaded sources and one saved source, delete the saved original outside the app, record real filesystem paths during refresh, and require no probes of untouched source directories. One tests a new download and one restarts Downloads to restore durable files. Both failed on the unwanted paths; saved-file deletion detection already passed. A third preservation test confirms that a nonempty restored directory without a manifest still observes newly added derived files and keeps unrelated files.

Direct fix: the existing source record remembers whether restoration found a nonempty directory or a save created its directory. Refresh skips only records without this storage history. The fact stays set after files disappear, preserving later verification and observation. Readiness, availability, command ordering, filesystem containment and saved-file verification keep their existing owners and paths. No additional availability cache or public option was introduced.

| Exact command | Result | Log |
| --- | --- | --- |
| `nix develop --command flutter test --concurrency=2 test/downloads/binding_test.dart --plain-name refresh` | Meaningful red: 1 passed, 2 failed, no skips; both failures report probes of untouched source directories. | `/tmp/boo-o3cm-review-r1-red.log` |
| `nix develop --command flutter test --concurrency=2 test/downloads/binding_test.dart test/downloads/status_test.dart test/downloads/directories_test.dart` | Green: 44 passed, no failures or skips. Includes all 25 binding tests. | `/tmp/boo-o3cm-review-r1-green.log` |
| `nix develop --command dart format lib/downloads/local_downloads.dart lib/app/account_binding.dart test/downloads/binding_test.dart test/app/account_binding_test.dart` | Four files, one test file reformatted. | `/tmp/boo-o3cm-review-format.log` |
| `nix develop --command flutter analyze lib/downloads lib/app/account_binding.dart test/downloads test/app/account_binding_test.dart` | No issues. | `/tmp/boo-o3cm-review-analysis.log` |
| `nix develop --command flutter test --concurrency=2 test/downloads test/app test/playback test/sync test/reader test/speech/hearing_policy_test.dart` | 2649 passed, 24 skipped, no failures. | `/tmp/boo-o3cm-review-affected.log` |
| `nix develop --command flutter test --concurrency=2` | 3378 passed, 27 skipped, no failures. | `/tmp/boo-o3cm-review-full.log` |
| `nix develop --command dart format --output=none --set-exit-if-changed lib/downloads/local_downloads.dart lib/app/account_binding.dart test/downloads/binding_test.dart test/app/account_binding_test.dart` | Four files, zero changes, exit 0. | `/tmp/boo-o3cm-review-format-check.log` |
| `git diff --check` | Passed, exit 0. | `/tmp/boo-o3cm-review-diff-check.log` |

All required affected/full checks passed after the direct fix, one heavy command at a time. All owned commands and the sole reviewer have finished. The earlier full-suite failure and its unchanged retries remain recorded above and in `t5-rplx`; the final full run also passed that reader-recovery test. Its intermittent cause remains unresolved. Skips retain the suite's existing optional corpus, benchmark and separate integration-test requirements; no test or timing threshold was changed to obtain a pass.

R1 is resolved by the ticket lead with the evidence above. There are no unresolved findings or product forks. No second review is authorized or claimed; the original independent correctness verdict remains changes-required, followed by this direct fix and verification. No device action, coverage or mutation campaign was run. Device acceptance remains blocked separately by `t1-dth0`. The parent owns integration, acceptance, hardening and ticket closure.

## Parent integration — 2026-11-13

Inspected the full six-file original-base diff, production consumers, all new binding tests, completed review and saved evidence. Integrated a457b8a9 as 36ef8f61 and b1d2afc5 as d74d9531. Retained parent launch and child evidence. Downloads conflicts preserve boo-721h's credential identity, rejection subscriptions, local-file access and renewed-credential behavior while keeping compatible records and requested-source readiness.

The first combined focused command passed 172 tests and failed one (/tmp/boo-3y46-o3cm-integrated-focused.log). The new active-transfer test created a fresh JellyfinSession for its second catalog binding, which now means credential replacement and correctly starts a fresh request. The fixture now retains one session for a catalog-only change. No production credential guard was weakened. The corrected combined run, including the parent sync-recovery regression, passed all 174 tests (/tmp/boo-3y46-o3cm-integrated-focused-green.log).

Combined final verification, account-switch ordering evidence and closure follow below. The pre-existing intermittent reader failure remains unresolved under t5-rplx; passing reruns do not explain it.

Parent integration finding: resetting temporary network permission after installing the new session but before replacing its download records emitted one notification with the previous account's downloaded availability. The test `switching accounts never reports the previous account files as available` failed meaningfully with phases `[downloaded, none, none]` (/tmp/boo-o3cm-integrated-account-red.log). The conflict resolution now resets permission after the account's records are installed; the unchanged-catalog credential-renewal path still resets permission and schedules eligible work. This defect came from the parent's integration, not the reviewed child.

`nix develop --command flutter test --no-pub --concurrency=2 test/sync test/durability test/playback test/app test/downloads test/reader test/speech/hearing_policy_test.dart --reporter expanded` passed 2,777 tests with 24 existing skips in 4m16s (/tmp/boo-3y46-o3cm-integrated-affected.log) before the new account-switch regression and its fix. No failures were suppressed. After that fix, `nix develop --command bash -c 'dart format lib/downloads/local_downloads.dart test/downloads/binding_test.dart && flutter test --no-pub --concurrency=2 test/downloads/binding_test.dart test/downloads/transfer_test.dart test/app/account_binding_test.dart test/app/credential_access_test.dart test/sync/repair_recovery_test.dart --reporter expanded'` passed all 105 tests (/tmp/boo-3y46-o3cm-integrated-regressions-green.log). Final analysis/format/full checks run after both direct parent fixes.


## Parent final verification and closure — 2026-11-13

Combined implementation and parent fixes are committed at 7cb281777c991f4e05fd4b731ba70bd3ba7a2971. The subsequent 7a1993fb changes only another ticket's coordination notes. No production/test change occurred during final checks.

`nix develop --command bash /tmp/boo-3y46-o3cm-final-checks.sh` completed with exit 0, one heavy command at a time:

| Check | Result | Log |
| --- | --- | --- |
| Changed Dart formatting | 21 files, zero changes | /tmp/boo-3y46-o3cm-integrated-format.log |
| Affected analysis | No issues | /tmp/boo-3y46-o3cm-integrated-analysis.log |
| Full combined Flutter suite | 3,483 passed, 27 existing skips, zero failures; 4m44s | /tmp/boo-3y46-o3cm-integrated-full.log |
| Diff checks | Passed | git diff --check |

Exact sequential commands:

```sh
set -e
dart format --output=none --set-exit-if-changed lib/app/account_binding.dart lib/downloads/local_downloads.dart lib/playback/database.dart lib/playback/record_codec.dart lib/playback/store.dart lib/sync/coordinator.dart lib/sync/journal.dart lib/sync/screen.dart lib/sync/transport.dart test/app/account_binding_test.dart test/downloads/binding_test.dart test/research/current_restore_measurement_test.dart test/sync/alert_test.dart test/sync/batch_api_test.dart test/sync/schedule_test.dart test/sync/screen_test.dart test/sync/status_test.dart test/sync/transport_test.dart test/sync/unknown_records_test.dart test/sync/unreadable_discovery_test.dart test/sync/repair_recovery_test.dart > /tmp/boo-3y46-o3cm-integrated-format.log 2>&1
flutter analyze --no-pub lib/playback lib/sync lib/downloads lib/app/account_binding.dart test/sync test/durability test/playback test/app test/downloads test/research/current_restore_measurement_test.dart > /tmp/boo-3y46-o3cm-integrated-analysis.log 2>&1
flutter test --no-pub --concurrency=2 --reporter expanded > /tmp/boo-3y46-o3cm-integrated-full.log 2>&1

```

All parent commands finished. Ticket implementation is integrated and verified; closure records that state. Original reviewer verdicts and direct-fix evidence remain above. Android acceptance is still blocked by t1-dth0; no device/performance claim, coverage, mutation campaign, push, PR or deployment. Hardening awaits acceptance. Existing opt-in/external-fixture skips and the unresolved t5-rplx intermittent failure remain limitations.
