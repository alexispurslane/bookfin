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


## Notes

**2026-11-11T13:48:23Z**

Started Sol xhigh ticket lead. taskId node:delegated-task:command%3Amcp%3A9af129e3-220f-4626-b1b7-2038d2bfc625%3Adelegate-task%3Asol-xhigh-boo-pc6x-engine-ready-20261111-1; childThreadId thread:delegated-task:command%3Amcp%3A9af129e3-220f-4626-b1b7-2038d2bfc625%3Adelegate-task%3Asol-xhigh-boo-pc6x-engine-ready-20261111-1; clientRequestId sol-xhigh-boo-pc6x-engine-ready-20261111-1. Base 7087ff6. One fresh Sol xhigh read-only review authorized after complete implementation and measurement. local/emulator-5556 only; own device_open binding required, genuine instrumentation runner preferred; no Pixel or homepage edits. Endpoint audit precedes claims; unavoidable mismatch goes to parent.
