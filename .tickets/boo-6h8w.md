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
