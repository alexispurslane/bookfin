---
id: boo-6h8w
status: in_progress
deps: [t0-dqxp, t0-60ea]
links: [boo-sthf, t7-msmk]
created: 2026-11-01T21:37:34Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Add persistent seek recovery bookmarks and listening history

Use one session transition path for slider, jumps, chapters, external controls, bookmarks, and restores. Retain previous and resulting positions.

## Design

docs/plans/bookfin.md

## Acceptance Criteria

Undo an accidental jump, restart, and restore the same position from history. Test grouped slider seeks, pauses, interrupts, restores, and bookmark edits.


## Notes

**2026-11-02T09:31:54Z**

Playback implementation and native corrections are integrated through7090471. Depend on the completed native correction tickets and retain a link to boo-sthf, whose remaining locked-screen acceptance does not prevent local history implementation. Preserve one Playback transition owner and existing source-relative positions; no transport or retention policy is selected.

**2026-11-02T10:19:54Z**

Implemented from e8fe9c7: one serialized position transition records confirmed before/result positions for seeks, grouped slider release, jumps, chapters, native controls and restores. Added persistent account history, Undo, stable editable/deletable bookmarks, v1 resume migration, read guards and visible write retry with pending account snapshots. Evidence: docs/evidence/playback/personal-records.md. Final Nix validation: all 227 Flutter tests pass, analyzer clean, SDK-link shell tests pass, Android ARM64 debug APK and JavaScript web build succeed. Original native zero/source-identity/interruption regressions pass. No emulator access, production Jellyfin requests, secrets, coverage/mutation, PR or closure. Android runtime acceptance and independent review remain with parent; t8-ld5q and sync/retention decisions remain open. Leave in_progress.

**2026-11-02T10:40:18Z**

Parent reproduced and corrected F1-F5 from review of14ab8c5. Cross-edition selection/history now commit after decoder confirmation; failure retains prior selection/Undo and reloads that selection before later Play/seek. Slider origin captures gesture time despite pending writes. Explicit Pause/Stop records are independent of decoder playing edges. Shared Undo is available in mini/full player, and History retains mini-player controls. Seven new cases failed meaningfully before correction. Full234 application tests and analyzer pass; after adding readiness invariant,29 history tests and formatting pass. Android ARM64 debug build passes. No new Android runtime or web execution claimed. Correction review and runtime acceptance remain pending; no closure.

**2026-11-02T10:50:37Z**

Second correction: reproduced R1 overlapping completed slider releases and R2 Undo loss after an aborted decoder reload. Each release now owns immutable origin/cancellation inputs; non-slider commands and selection/account changes invalidate stale gestures. Loading and seeking return explicit applied outcomes, propagated through restore before clearing Undo. Added both failing regressions plus an intervening-jump cancellation case. All237 app tests, analyzer and Android ARM64 debug build pass through Nix. Runtime acceptance and re-review remain open.

**2026-11-02T10:57:35Z**

Independent final correction review approved10051f6 with no actionable defects. Parent fast-forward integrated the feature and both correction rounds into main. The exact code already passed237 application tests, clean analysis and Android ARM64 debug build; merge introduced no code conflicts or changes. Keep in_progress for Android runtime and user acceptance. After reader proof releases its own device session, observe grouped drag/Undo, mini-player and History controls, bookmark edit/delete/restore, native seek/pause/interruption actions, account isolation, and real process restart with retained history. No ticket closure or hardening inferred from merge.

**2026-11-02T11:39:46Z**

Android acceptance attempt at72996e4: built normal lib/main.dart ARM64 debug APK and installed/read-back SHA256745d4550d11d5d82b8e19b356b259cbb37e85c4a441cde75dba794a5f0404f2f. Stopped before sign-in under device failure rule: server field focus refused, advised debug retry used an expired ref and was not dispatched. No playback/store evidence or product regression established; no code fix or test APK invented. Temporary emulator-only PIN removed and Screen lock None verified; signed out, no own downloads, original networks unchanged, own fixture/observer stopped and forward removed, own binding released without shutdown. Full details and pending matrix: docs/evidence/playback/personal-records-android.md; follow-up t7-msmk. Leave in_progress for parent.

**2026-11-02T12:21:24Z**

Authorized fresh attempt at756ae5f stopped before field entry after my invalid Settings activity argument and failed advised retry. No grouped seek, Undo, bookmark, history, restart, isolation or reconnect runtime observation. Normal main APK built but was not installed. All271 application tests, analyzer and SDK-link tests pass through Nix. No application code changed. Evidence and safe preinstalled signed-out image: docs/evidence/playback/personal-records-fresh-attempt.md. Own services and binding cleaned, settings unchanged. Runtime acceptance remains open; no closure or hardening.

**2026-11-02T14:13:50Z**

Current-main APK82faf07d observed +30s jump00:49 to01:19, Undo to00:49, history-result and previous-place restores adding retained history, bookmark create/edit/restore, and first process relaunch preserving position79757ms, bookmark and history without autoplay. Bob saw no Alice download or records; Alice reauthentication restored her download/position. Slider grouping, mini-player/history Pause, deletion and native interrupt matrix remain unobserved after tool stop. Evidence docs/evidence/playback/current-main-android.md; cleanup complete, no code change or closure.

**2026-11-02T18:20:38Z**

Additional independent acceptance worker started from ac6a247a654829d5204437a203b2b61c3ed15234. EPUB worker owns local/emulator-5554 and ports7364/7365; no device, route, fixture, or binding operations authorized here. Focused host baseline passes150 tests. Inspecting missing UI cancellation/persistence and pointer-gesture cases; Android handoff and limitations will be recorded without closure.

**2026-11-02T18:52:37Z**

Additional acceptance from ac6a247a654829d5204437a203b2b61c3ed15234 completed after explicit parent emulator handoff. Own normal ARM64 debug APK SHA2566ecf12063e68e73a0642563be1cd269fde49f1609b49284a7c84cf39baf38f42 matched installed readback. Newly observed History Pause39977ms, mini-player +30s/Undo, one continuous1500ms slider gesture39977→126957ms/Undo with exactly one persisted Seek, and bookmark Cancel/Delete across process relaunch while six history actions survive. Added two bookmark UI persistence regressions and two retained-removal regressions. Baseline150 focused tests, final154 focused tests, all310 app tests, clean analysis and shell toolchain checks pass through Nix. No production change or defect. Evidence docs/evidence/playback/remaining-acceptance-android.md and remaining-acceptance-runtime.json,27 public screenshots. Signed out, own media removed, own services/route/Gradle stopped, binding released shutdown:false. No closure, coverage, mutation, child or PR; parent integrates and accepts.
