---
id: boo-3oq0
status: in_progress
deps: [boo-p58t, boo-6h8w, boo-9wgg, tb-5fyd, tb-887c]
links: [t6-t9po, t6-il6y]
created: 2026-11-01T21:37:34Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Sync Bookfin records through validated Jellyfin storage

Implement the transport selected by the feasibility ticket. Prefer existing Jellyfin storage; build the small plugin only if that is the recorded outcome. Keep record ownership and conflict rules in Bookfin.

## Design

docs/plans/bookfin.md

## Acceptance Criteria

Two devices merge offline bookmarks and history, retain deletions, tolerate duplicate retries and clock differences, and preserve both positions on true resume conflicts. Test against actual Jellyfin.


## Notes

**2026-11-02T22:49:09Z**

User explicitly requests a continuous builder lane: production record sync, then remaining ebook formats and approved OCR, while separate acceptance agent owns Android. Begin implementation against reviewed dedicated-plugin storage and existing record owners; outstanding prerequisite acceptance gates remain open and must be respected before closure. No claim that dependencies are fully accepted.

**2026-11-02T23:21:14Z**

Production candidate now implements account-owned Flutter journal, verified plugin transport, serialized audio/reading merges, SQLite atomic records/pending uploads on Android, explicit conflict choices retaining both resume positions as bookmarks, and explicit history deletion. Two real SQLite clients pass actual disposable Jellyfin/plugin integration. Android acceptance remains open; t6-t9po tracks journal growth and t6-il6y tracks production plugin deployment. See docs/research/production-record-sync.md. No closure or release-complete claim.

**2026-11-02T23:26:22Z**

Normal ARM64 debug APK builds successfully from source ccff7dc (241.1s). Candidate: .cache/artifacts/bookfin-ccff7dc-record-sync.apk; SHA-256 recorded in tool/evidence/sync/20261102/apk-sha256.txt. Not installed by builder. JVM/dependency deprecation warnings retained in build evidence. Parent can hand this named build to the acceptance lane; no Android-runtime sync claim.

**2026-11-03T00:25:36Z**

Independent review corrections F1–F4 now have meaningful red regressions and production fixes. Accepted persisted snapshots, not reads or unpersisted pending snapshots, advance audio/reading deletion authority. Decoder-change tracking separates pending-write flush from resume movement; both coordinator/player choices persist without seeking, and stale choices recover. Journal shapes/references reject as FormatException while preserving bytes, unsynced actions and retryable writes. Conflict descriptions use current catalog names and readable positions with explicit unavailable fallbacks. Safe reader milestone 94457bf remains intact. Verified 193 focused tests, SDK checks and 397 full Flutter tests (one optional plugin test skipped), clean analysis, and separate passing two-SQLite-client actual disposable Jellyfin/plugin test. Evidence: tool/evidence/sync/20261102/review-corrections/. No Android sync claim. t6-t9po still gates once-per-second retained-journal parse/rewrite growth; no latency measurement. t6-il6y still gates plugin packaging/deployment/upgrades. Parent owns independent re-review, integration and closure.
