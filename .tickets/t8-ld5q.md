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

**2026-11-02T13:06:55Z**

Independent correction review approved f297520 with no remaining blocker across the complete feature. Parent integrated without conflicts; application/test/toolchain sources match the tested head (292 app tests, clean analysis and Android build). Keep in_progress for Android confirmation interaction, retained-record process restart and user acceptance. No runtime or hardening claim follows from integration.

**2026-11-02T14:13:50Z**

Fresh authorized current-main APK82faf07d captured required sign-in/library/download/playing path first and completed several record/retained-storage observations. Acceptance then stopped after library-navigation action and single advised retry failed while fixture reverse route was absent. Source bytes were never replaced; Android replacement confirmation/cancel/old-record separation remain unobserved. See docs/evidence/playback/current-main-android.md and route follow-up td-7yxu. No code change or closure.

**2026-11-02T18:52:37Z**

Additional validation from ac6a247 reran the21 existing replacement tests within154 focused and310 full passing app tests. Android work prioritized missing History Pause, grouped slider/mini-player Undo, bookmark deletion and unavailable/retained-download lifecycle. Only an owned downloaded copy was corrupted; original Jellyfin source bytes never changed. Therefore replacement confirmation/cancel and original-record separation remain unobserved on Android. Evidence docs/evidence/playback/remaining-acceptance-android.md. No production change, new defect, closure or claim that host tests establish runtime replacement acceptance.

**2026-11-02T23:56:37Z**

Exclusive Android acceptance worker starts from parent1f1b1c6. Own new bindinglocal/emulator-5554 after prior release; no production changes, children, coverage or mutation. Primary replacement confirmation/cancel, retained-record restart; then native listening gates and bounded real-Jellyfin recovery if feasible. PriorPID11695 is not claimed stopped. Parent owns integration/closure.

**2026-11-03T00:00:39Z**

Acceptance from parent1f1b1c6 verified runtime-source equality with17c9e6b and installed APK SHA2568e4f386e79a0446a9ae2c51f0f157d07d9953b4aa4cf5f23ed3c3957b5be534b. Stopped before sign-in: bound server fill refused focus; worker then incorrectly reused an expired username reference in the same shell command. No advised debug retry occurred before that second error. No replacement, record-restart, notification, interruption, or download-recovery acceptance advanced. Evidence docs/evidence/playback/android-replacement-native-attempt.md. No production defect/change, children, hardening or closure. Cleanup complete; renewed Android authorization needed after stop.

**2026-11-03T00:19:10Z**

Fresh explicitly renewed authorized Android acceptance from fc4531c4ff9cf38d85317961e6ce771d9567a058. Runtime/source unchanged from17c9e6b; installed readback matches SHA2568e4f386e79a0446a9ae2c51f0f157d07d9953b4aa4cf5f23ed3c3957b5be534b. Own binding local/emulator-5554; only own7364/7365 fixture and route. One UI action per command with fresh snapshots. No production edits or unaccepted sync branch.

**2026-11-03T00:53:19Z**

Fresh renewed-authorized normal Android run from fc4531c passed replacement confirmation and Cancel (entire playback payload unchanged), then confirmed actual replacement playback from0. Original resume24298ms/history/bookmark retained separately from replacement25864ms. Named relaunchPID22749->26011 retained all records exactly; incompatible original bookmark restore was refused without remapping. Later final record still retains original resume and records. Installed APK readbackSHA2568e4f386e79a0446a9ae2c51f0f157d07d9953b4aa4cf5f23ed3c3957b5be534b, no runtime source differences from17c9e6b. Evidence docs/evidence/playback/android-authorized-retest.md and numbered bounded readbacks/screenshots. No production edit, hardening or closure. Parent owns integration and acceptance.
