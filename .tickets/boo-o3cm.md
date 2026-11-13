---
id: boo-o3cm
status: in_progress
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
