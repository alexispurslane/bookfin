---
id: t6-il6y
status: in_progress
deps: []
links: [boo-3oq0, boo-s11s]
created: 2026-11-02T23:19:27Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Package and validate the dedicated Jellyfin Storage plugin for deployment

The Flutter production sync candidate now uses the reviewed v1 dedicated object API. The tested C# plugin still identifies itself as a research candidate. Promote its shared storage/controller source into a deployable plugin package, document supported server versions, backups, installation and upgrades, and verify install/restart with the app. Do not advertise an available production release or install on a live server until parent approval.


## Notes

**2026-11-03T01:58:03Z**

Builder milestone: reproducible local Bookfin Storage 0.1.1.0 package, exact source/hash manifest and source ZIP. One C# implementation moved unchanged to plugin/Bookfin.Storage (controller/store hashes preserved). Documented installation, stopped backups, research-to-candidate upgrade and rollback, plaintext/privacy and server-version limits. Disposable Jellyfin 12.4.0: all 21 storage regressions, two durable-client upgrade phases, unchanged real-app transport regression, ordinary-account isolation, restart, and whole stopped backup restore pass. Both owned servers stopped and 7464/7465 free. Two clean builds plus extracted-source rebuild match package SHA-256 3b0de5ca1df39baf67c786079898b1ee3b0b09d3bdb86d00ece8a7f5731a9105. Package tests 3 pass, research tests 40 pass, project suite 407 pass/2 fixture skips, analyze clean. Evidence tool/evidence/plugin/{packaging.json,source-rebuild.json,checks.txt,red-tests.txt}. No Android use/build, live install, publishing, deployment acceptance, hardening or closure. Parent review/integration and deployment approval remain required.

## Independent review and bounded integration

Independent review of 96d69c1 found no actionable blocker in correctness,
finite ticket fulfillment or design. Main integrates the candidate as 6f424e1.
Storage/controller source bytes and plugin/database identity remain unchanged;
no merge conflict occurred. Retained supplied install/upgrade/restart/backup
proof is for Jellyfin 12.4.0 macOS ARM64 only. No redundant suite rerun for this
clean integration. Live deployment/publication, Android and broader release
acceptance remain open; this ticket is not closed.

## Approved batch API follow-up

The user approved boo-s11s on 2026-11-12: client batching first, then an additive batch upload API and larger discovery pages selected by plugin version, retaining the current v1 fallback. The parent has inspected this ticket's integrated package evidence. boo-s11s will own the changed source, package metadata/version and disposable compatibility checks, and report the new candidate here. Existing identity, database and retained records must survive. The current 0.1.1.0 evidence applies only to that candidate; live deployment and publication remain outside the follow-up.

## boo-s11s additive candidate proof, 2026-11-13

New local candidate: `Bookfin.Storage_0.2.0.0.zip`, SHA-256 `4e37667dec6f0d8e0610849b6c2059b7b58266d2e0523c9e9f0d41ff9bb187e9`. Prepared under `.cache/plugin/package/` in the boo-s11s worktree, with matching source ZIP and hash file. The plugin identifier `55fb5a92-7fbd-411c-9838-6ee4c88d168b`, database filename/schema and immutable payloads remain unchanged. README documents the complete v1/version-selection/v2 wire contract and bounded requests/pages.

`nix develop ./tool/research/sync --command bash -c 'set -e; PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tool/plugin -p "test_*.py" -v; PYTHONDONTWRITEBYTECODE=1 python3 tool/plugin/prove.py'` passed: 3 package tests, 27 disposable storage/outbox/API tests, and four actual Flutter integration invocations (old-plugin preparation, upgraded-plugin verification, existing production transport regression, and batch workload). C# builds reported zero warnings/errors. Two independent clean builds and an extracted-source rebuild produced identical package bytes. Exact sanitized results and source hashes: `tool/evidence/plugin/packaging.json`. Full log: `/tmp/boo-s11s-plugin-proof-final.log`; complete proof elapsed 114.061 seconds.

The baseline DLL came from integrated `0.1.1.0` source at `1de1ed6ba8a0bd69af70b2123f7fd8a63cedd48f`. New Flutter clients used legacy fallback there, then batch mode after replacement by `0.2.0.0`. Existing v1 clients retained the four-object API and all 21 prior storage/outbox behaviors. Upgrade and restart preserve account identity, records, pending uploads, conflicts and deletion barriers; stopped backup restore recovers the original server inventory. Ordinary users remain isolated.

The actual Flutter-to-plugin workload retains 2,400 immutable actions after both client databases reopen: 10 upload requests, 10 acknowledgment transactions, 11 receiving discovery requests, zero lost actions. Host loopback timings: upload 521 ms; receive 224 ms. The separate C# HTTP workload also retains/discovers 2,400 objects across server restart. These are macOS ARM64/Jellyfin 12.4.0 host results, not Android performance or acceptance.

An earlier proof attempt stopped before starting servers because Nix treated the extracted source as untracked files in the enclosing repository (`/tmp/boo-s11s-plugin-proof.log`). The proof now selects that extracted flake through an explicit filesystem path. A preliminary API run also stopped on the fixture's old version allowlist, which now admits this exact candidate; neither failed attempt is counted as passing. Final cleanup confirms every owned server stopped and loopback ports 7464/7465 free. No live service, credentials, deployment, publication, device action, acceptance claim or ticket closure. This ticket remains open for its original deployment/acceptance work; parent integration and review belong to boo-s11s.

## Proof after boo-s11s review fixes

The single fresh review found two Flutter transport defects: oversized damaged actions could not reach server-copy recovery, and decimal conflict statuses could escape ordinary failure handling. boo-s11s fixed both with meaningful red-green regressions. No plugin source or package bytes changed. The package command above was rerun with the fixed Flutter transport and passed 3 package tests, 27 disposable storage/API/outbox tests, all four actual Flutter integration invocations, reproducible C# builds, upgrade/restart, ordinary-account isolation and stopped backup restore. Log `/tmp/boo-s11s-review-plugin-proof.log`; proof time 112.013 seconds; refreshed evidence `tool/evidence/plugin/packaging.json`.

Candidate `Bookfin.Storage_0.2.0.0.zip` still has SHA-256 `4e37667dec6f0d8e0610849b6c2059b7b58266d2e0523c9e9f0d41ff9bb187e9`. All 17 source/proof hashes and package/source ZIP hashes match; metadata, project and README versions agree. The new run retained all 2,400 actions after both client database reopens: 10 upload requests, 10 acknowledgment transactions, 11 receiving discovery requests, zero lost actions; host upload/receive times 525/223 ms. Both owned servers stopped and ports 7464/7465 are free. The final Flutter suite passed 3,254 tests with 26 existing/opt-in skips (`/tmp/boo-s11s-review-full.log`); all three plugin fixtures passed separately. Same macOS ARM64/Jellyfin 12.4.0 limits and deployment/acceptance exclusions apply. This ticket remains open.

## Parent integration of the additive candidate

boo-s11s is integrated and closed after a combined main run of 3,284 passing tests, 26 skips and clean affected analysis. The parent verified all 17 source/proof hashes and both candidate ZIP hashes against the integrated files and child artifacts. No package bytes changed. Existing disposable compatibility evidence applies; no live installation or publication occurred. This ticket remains open for deployment and acceptance.
