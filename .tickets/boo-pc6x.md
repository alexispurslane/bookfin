---
id: boo-pc6x
status: in_progress
deps: []
links: []
created: 2026-11-11T13:47:11Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
---
# Rerun EPUB engines to page preparation readiness

User requests a fresh rerun timing until the page picture is ready, excluding display scheduling, drawing and capture overhead where a common preparation endpoint can be exposed. Audit all three real engine adapters, distinguish drawing-command readiness from bitmap rendering and WebView layout readiness, keep post-timing independent content validation, and measure the same balanced workload on local emulator-5556. Plan: docs/plans/epub-engine-ready-comparison.md.

## Acceptance Criteria

Explicit defensible endpoints for Bookfin, epub.js/WebView and KOReader; new release-run raw timings and content evidence; no stale/blank-page timings accepted; original comparison preserved; equal-book-weight arithmetic mean table plus per-book counts/median/p90; one fresh Sol xhigh review and verified resolutions. No Pixel actions or homepage rewrite.

