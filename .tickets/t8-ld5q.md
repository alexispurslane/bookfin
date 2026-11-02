---
id: t8-ld5q
status: in_progress
deps: []
links: []
created: 2026-11-02T05:35:06Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Decide recovery when a downloaded source revision changes

AudioPosition.fits rejects changed or empty source revisions. Playback retains the original scoped resume and refuses to apply it; this prevents silent position reuse. Choose the user-facing recovery in the parent: (A) confirm a fresh start while retaining the old resume separately, or (B) require source-position reconciliation before playback. A immediately permits replacement playback but needs a clear fresh-start confirmation; B avoids an implicit reset but blocks listening until reconciliation exists. No recovery choice is implemented by boo-sthf. Keep this separate from live-session reporting and from claims of full personal-record sync.

## Notes

**2026-11-02T12:05:50Z**

User selected confirmed fresh start on 2026-11-02, retaining the old scoped resume separately. Implement this approved recovery through the existing Playback owner; preserve old history/bookmarks and never silently remap them to the replacement.

**2026-11-02T12:38:03Z**

Implemented the approved confirmed fresh start from 756ae5fcf77f8d1f9d18124311fedbc085c7605b in the T3-prepared worktree. Existing Playback/ResumeStore owns confirmation and per-recording resumes; version-1/2 migration preserves old positions, history, bookmarks, settings and pending writes. Cancel, failed load, stale/account-changed offers, unchanged-first-file identity, corrected file order and replacement replay/restoration are tested. Eighteen new behavior cases; final Nix checks: 101 focused playback tests, all 289 app tests, clean analysis, unchanged formatting, SDK-link tests, ARM64 debug APK and JavaScript web release build pass. Evidence: docs/evidence/playback/replacement-source.md. No device/external fixture, child, PR, coverage, mutation or closure. Separate-base Android acceptance does not cover this implementation; parent integration, review and runtime acceptance remain required. Leave in_progress.

**2026-11-02T12:58:29Z**

Parent reproduced review R1/R2 with three meaningful failures: both legacy formats lost the unchanged-first-file resume; a delayed lookup published an obsolete offer. Preserve legacy entries during complete-recording saves, centralize offer membership checks, and recheck catalog membership after local-file awaits. All21 replacement and292 full application tests pass; clean analysis/format/diff and Android ARM64 debug build pass. Await correction review; no runtime acceptance or integration yet.
