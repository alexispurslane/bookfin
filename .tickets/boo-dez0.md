---
id: boo-dez0
status: in_progress
deps: [tb-887c, tb-5fyd]
links: []
created: 2026-11-02T12:05:50Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
---
# Prove dedicated Jellyfin storage for retained Bookfin records

User selected a server storage surface separate from ordinary playlists, with history retained until explicit deletion. Prove a small Jellyfin plugin in a disposable fixture; no production installation. Existing research remains input, not proof that the plugin works.

## Design

docs/plans/bookfin.md

## Acceptance Criteria

Authenticated account isolation; durable concurrent independent operations; retry deduplication; discovery; explicit deletion without delayed resurrection; no automatic history or device expiry; preserve offline pending actions; restart proof; documented limits. Keep merge/conflict semantics owned by Bookfin.


## Notes

**2026-11-02T12:46:19Z**

Dedicated plugin feasibility proof completed in the isolated worktree from 756ae5f; keep this ticket in_progress for orchestrator review/integration/closure. docs/research/jellyfin-dedicated-storage.md and tool/research/plugin/README.md document reproduction and limits. Pinned official disposable Jellyfin 12.4.0, .NET SDK 10.0.401 from the existing locked Nix input, no NuGet package additions or global toolchain install. Fresh ordinary Alice/Bob accounts, own loopback ports 7464/7465 only. Release build: zero warnings/errors. Final bounded experiment: 20 passing tests (4 local, 16 actual-server), including 80 independent writes with 8 workers, duplicate retries, account isolation, cursor discovery during mutations, permanent physical deletion markers, upload/delete races, Bookfin causal conflict/deletion behavior despite clock skew, history retained until explicit deletion, missing predecessors, a real unread-response upload witnessed on another connection, durable pending retry and explicit 410 rejection. Two clean restarts and one forced process stop preserve acknowledged state; plugin remains Active. Red evidence includes HTTP 501 before implementation, local durability/scope failures, missing acknowledgment handling, null-payload SQL length bug, and concurrent local scope initialization lock failure. Existing research suite: 40 passing tests. Full project test command: SDK-link checks plus 271 Flutter tests pass. nixfmt --check and git diff --check pass. Sanitized runtime.json records source/DLL hashes, object/byte counts and cleanup; checks.txt retains broader checks. No history/device expiry, pending-action discard, production requests, devices, browsers, children, PR, coverage or mutation jobs. No lifetime bound, plugin upgrade/migration, power-loss, disk-full, complete client sync or secure byte-erasure proof is claimed. Prior research reports now link to the dedicated result. Own fixture processes exited; ports 7464/7465 have no listeners; private state stays ignored under .cache/plugin/run-*/, directories 0700 and credential/database files 0600. Production integration and operational qualification remain under boo-3oq0 and release gating.

**2026-11-02T13:10:31Z**

Parent reproduced both review defects: leading-null payload returned500 after restart with invariants enabled, and coordinated conflicting enqueues both reported acceptance. Byte-based invariant condition now matches schema; enqueue acquires immediate transaction before lookup. Corrected release build has0 warnings/errors;21 experiment and40 sync research tests pass. Refreshed sanitized runtime evidence/source hashes, five starts and complete own-fixture cleanup; secret-value audit passes. Correction review pending, no integration/closure or production proof.
