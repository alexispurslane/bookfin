---
id: boo-6h8w
status: in_progress
deps: [t0-dqxp, t0-60ea]
links: [boo-sthf]
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
