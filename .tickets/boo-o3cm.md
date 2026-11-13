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
