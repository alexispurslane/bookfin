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

**2026-11-02T23:59:04Z**

Independent static review of ccff7dc/e9721ff requires correction before integration: F1 rejected refresh advances store observation and can delete discovered bookmarks; F2 active-player flush invalidates or overwrites conflict choices; F3 malformed local sync metadata escapes storage recovery; F4 conflict choices lack readable book/edition/position identity. Continuous builder steered to preserve current PDF milestone then fix shared snapshot acceptance and persistence semantics with meaningful race regressions. No sync integration or acceptance claimed. Android listening lane remains independent. Growth t6-t9po and plugin deployment t6-il6y stay open.

**2026-11-03T00:51:18Z**

Independent final review approves dbc54ed over b81b472 for bounded source integration: retained action validation and account-generation refresh rejection resolved, no new actionable blocker. Parent executed399 Flutter passes/one optional plugin skip, clean analysis and SDK/native checks. Prerequisite stack includes unreviewed PDF/MOBI94457bf; review of that implementation and packaging4ee30c6/7bb097d must precede combined integration. Continuing branch c0263db includes the correction. No corrected Android sync acceptance or ticket closure; growth/deployment gates remain.
**2026-11-02T23:21:14Z**

Production candidate now implements account-owned Flutter journal, verified plugin transport, serialized audio/reading merges, SQLite atomic records/pending uploads on Android, explicit conflict choices retaining both resume positions as bookmarks, and explicit history deletion. Two real SQLite clients pass actual disposable Jellyfin/plugin integration. Android acceptance remains open; t6-t9po tracks journal growth and t6-il6y tracks production plugin deployment. See docs/research/production-record-sync.md. No closure or release-complete claim.

**2026-11-02T23:26:22Z**

Normal ARM64 debug APK builds successfully from source ccff7dc (241.1s). Candidate: .cache/artifacts/bookfin-ccff7dc-record-sync.apk; SHA-256 recorded in tool/evidence/sync/20261102/apk-sha256.txt. Not installed by builder. JVM/dependency deprecation warnings retained in build evidence. Parent can hand this named build to the acceptance lane; no Android-runtime sync claim.

**2026-11-03T00:25:36Z**

Independent review corrections F1–F4 now have meaningful red regressions and production fixes. Accepted persisted snapshots, not reads or unpersisted pending snapshots, advance audio/reading deletion authority. Decoder-change tracking separates pending-write flush from resume movement; both coordinator/player choices persist without seeking, and stale choices recover. Journal shapes/references reject as FormatException while preserving bytes, unsynced actions and retryable writes. Conflict descriptions use current catalog names and readable positions with explicit unavailable fallbacks. Safe reader milestone 94457bf remains intact. Verified 193 focused tests, SDK checks and 397 full Flutter tests (one optional plugin test skipped), clean analysis, and separate passing two-SQLite-client actual disposable Jellyfin/plugin test. Evidence: tool/evidence/sync/20261102/review-corrections/. No Android sync claim. t6-t9po still gates once-per-second retained-journal parse/rewrite growth; no latency measurement. t6-il6y still gates plugin packaging/deployment/upgrades. Parent owns independent re-review, integration and closure.

**2026-11-03T00:43:29Z**

Parent fixes second review R1/R2 on b81b472: all retained saved action values use the downloaded-record validator, with normal format/type decoding failures and no catch of invariant failures; reading refresh rejects an ended account generation across A-to-B-to-A. Both meaningful reds retained. Eleven focused tests and399 full Flutter tests pass (one optional plugin skip), clean analysis and SDK/native checks. Two old storage fixtures now contain complete valid bookmarks. Evidence tool/evidence/sync/20261102/final-boundaries/. No APK/device/plugin rerun or growth/deployment acceptance; independent re-review pending.

## Reviewed source integration

Main merge 681c168 includes all reviewed sync prerequisites and corrections
through dbc54ed plus reviewed PDF/MOBI corrections through 2e108df. The merge
preserves both ticket histories. No corrected-build two-device Android result
is claimed; journal growth t6-t9po and plugin deployment t6-il6y remain open.

**2026-11-03T14:16:49Z**

Bounded actual normal Android + unchanged packaged plugin proof on source4ae8c6c: UI creates EPUB positions/bookmarks, creates another position/bookmark genuinely offline with no default network or fixture reverse route, and survives process restart with six exact retained/pending actions. Failed sync retains them. Direct ordinary-account sync to owned Jellyfin12.4 / Bookfin Storage0.1.1.0 acknowledges all six; server payload hashes match Android exactly. UI deletion adds action7 while retaining six prior payloads; restart uploads deletion and keeps the second bookmark. Bob discovery empty. Initial observer cannot forward PUT; owned direct route avoids this fixture limitation without changing app origin/API/package. No second Android client, conflicts/listening-history/clock acceptance, production edits, or closure. Report docs/evidence/reader/android-normal-formats-20261103.md.
