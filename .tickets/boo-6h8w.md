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
