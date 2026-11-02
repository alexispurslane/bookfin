---
id: boo-2cgp
status: in_progress
deps: [boo-u3cg, boo-7o92, ta-qobz]
links: [t7-bzzg]
created: 2026-11-02T01:06:42Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
---
# Verify ordinary-user catalog and media integration

Validate catalog and downloads against disposable Jellyfin with two ordinary accounts, synthetic multi-file audiobooks and ebooks. Live admin research does not establish permission enforcement or pairing.

## Design

docs/plans/bookfin.md; authenticated research d327f68 pending permission-guard correction. Preserve remaining acceptance independently of catalog implementation.

## Acceptance Criteria

Prove account isolation, inaccessible items, disabled or missing download permission, multi-file ordering, distinct editions and ebook pairing. Verify progress writes only on synthetic media. Gate release acceptance; storage proof remains boo-p58t.


## Notes

**2026-11-02T04:54:59Z**

Integrated download corrections at 2cfd959: include corrected-build Android interruption, cancellation, immediate restoration commands, and early-file-failure controls in acceptance. Parent 149 tests and rebuilt APK pass; corrected Android UI run remains unclaimed.

**2026-11-02T05:48:16Z**

Begin app-level disposable integration from integrated catalog/downloads and corrected live probe. Parallel playback owns emulator; this task uses synthetic loopback server and actual production app modules without device operations. Preserve corrected-head Android UI acceptance as outstanding if not exercised.

**2026-11-02T06:28:10Z**

Application HTTP acceptance from ae6be0e84539515b5c77cbb419b2f0a67c923cfd now runs the real JellyfinClient/IO transport, CatalogController/buildBooks/correction operations, and LocalDownloads against a fresh pinned core-only Jellyfin 12.4.0 fixture on 127.0.0.1:7364. Nine live checks pass twice consecutively. Covers two ordinary accounts, accessible non-book exclusion, selected libraries, explicit-only grouping/pairing, disc/track and corrected order, distinct recordings, exact audio/ebook bytes and hashes, account/source identity, source replacement, permission/library revocation and recovery, inaccessible items, and no File fallback. Fixed real modern-Authorization failures in catalog/downloads and real Book-without-MediaSources acquisition after meaningful live failures. Five host regressions added. Full application suite 154 pass; sync research 40 pass; earlier probe/model research 32 pass; SDK-link tests pass; analysis clean; changed Dart format and diff checks pass. See docs/acceptance/jellyfin-app.md, tool/acceptance/README.md and sanitized tool/acceptance/evidence/app-http.json. Platform credentials/preferences use test-only protected disk implementations, not native secure storage. Missing download permission remains an explicitly synthetic client guard. Real Jellyfin omits strong HTTP ETag: interrupted bytes survive owner restart but retry safely restarts HTTP 200; no real prefix-range resume claimed. New t7-bzzg gates boo-gk92 for that unresolved requirement. boo-2cgp stays in_progress and still gates corrected-head Android interruption/cancel/immediate restore/remove/early-failure UI and ordinary-account secure-storage process restart. No playback/progress writes, device/browser/preview operations, children, coverage, mutation jobs or PR. Own server stopped and exited; port 7364 has no listener. Own restartable runtime retained ignored at mode 0700 with credential/result files mode 0600. Parent owns integration and closure.


## Parent evidence-publication correction

The publisher now deletes stale observations and runs the live Flutter acceptance suite itself. Publication requires that same process to exit successfully, including all cleanup. The ninth check records success only after source metadata restoration. A regression reproduced false publication before the fix and now proves a failed runner leaves previous public evidence unchanged.

Parent verification: the corrected publisher executed all nine checks successfully against the retained disposable Jellyfin fixture and regenerated app-http.json; 154 application tests pass, the publication regression passes, and scoped Dart analysis is clean. The server exited and port7364 has no listener. No Android, production-server, or credential-storage acceptance is added by this run.

**2026-11-02T06:54:02Z**

Integrated catalog/download access fixes and runner-authoritative evidence publisher at0faa251; parent reran nine real app acceptance checks and154 app tests. Playback now integrated at8ff61d4. Next: shared Android end-to-end acceptance for secure credential restoration, catalog/download lifecycle, and playback correction behavior; t7-bzzg stays open.

**2026-11-02T08:27:44Z**

Completed missing observable Android follow-up from integrated d9bc3a6 against own disposable Jellyfin only. Production ordinary Alice sign-in and native secure token restoration survived process restarts. Bob could not see Alice corrections/downloads/resume; returning to Alice restored only Alice records. Book-only catalog, explicit ebook confirmation/cancel, separate recordings, two-file audio order, restored Cancel/Remove, early-file503 Cancel, Retry, and exact Android audio/EPUB bytes observed. Actual downloaded AAC played offline on the preceding corrected APK; final adapter correction separately repeated Pause restoration and native interruption cases. No production server or credential-locked-screen proof. Authoritative publisher reran nine checks successfully and regenerated app-http.json only after runner cleanup. Native runtime fixes tracked t0-dqxp; discrete interrupted Pause still t0-60ea. Jellyfin has no strong ETag, so200 full restart is safe recovery, not range-prefix reuse; t7-bzzg stays open. Details and cleanup in docs/evidence/playback/integrated-android.md. Parent alone accepts/integrates/closes; remains in_progress.
