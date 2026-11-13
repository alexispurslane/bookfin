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
