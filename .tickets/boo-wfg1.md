---
id: boo-wfg1
status: in_progress
deps: []
links: []
created: 2026-11-10T20:42:55Z
type: bug
priority: 1
assignee: Alexis Purslane
parent: boo-fval
---
# Keep word-image pages visible until the next word screen is ready

User reports a brief flash of Original while turning to PDF word-image pages whose layout should already be cached. Trace and reproduce with held asynchronous rendering. PdfWordScreens.open currently resets showing=false on every source-page open, while PdfWordPages already retains its displayed screen until replacement pixels are ready; PdfWordView then draws the Original waiting widget. Fix that transition through the existing displayed-screen ownership. Saved geometry/layout does not imply saved rendered word-screen pixels; document actual cache lifetime rather than claiming disk-cached reflow images. Keep the last readable word screen during page replacement, with positions and interaction referring to the truly displayed content. Preserve cold-open behavior, legitimate no-geometry/content/operational fallback, internal Error propagation, crop/trim behavior and bounded image memory. Treat next-source-page pre-render t8-bnwn as separate unless necessary.

## Acceptance Criteria

Red-first behavior tests: a source-page turn and a return to a cached page never paint Original between readable word screens, including held renders; stale completions and rapid direction changes cannot replace newer content; displayed position does not advance to unseen content; true fallback and opening a word view without a previous screen remain correct. Inspect close/reopen and view-switch paths and report scope honestly. Required Nix checks and one fresh Sol xhigh read-only review, then fix findings. No Pixel UI input.


## Notes

**2026-11-10T20:43:47Z**

Launched Sol xhigh lead from bdf340f. taskId: node:delegated-task:command%3Amcp%3Ae6a3d378-c450-4501-a47c-77e7994db5fb%3Adelegate-task%3Asol-xhigh-word-flash-20261110-boo-wfg1-1; childThreadId: thread:delegated-task:command%3Amcp%3Ae6a3d378-c450-4501-a47c-77e7994db5fb%3Adelegate-task%3Asol-xhigh-word-flash-20261110-boo-wfg1-1; clientRequestId: sol-xhigh-word-flash-20261110-boo-wfg1-1. Running, stage uncertain; worktree branch pending report. Lead owns regression-first transition fix and one fresh read-only Sol xhigh review. Parent integrates/installs; user tests phone. Other word-feature leads continue separately.
