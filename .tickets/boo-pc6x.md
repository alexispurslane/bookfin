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

**2026-11-11T13:53:53Z**

Endpoint audit found no equivalent pre-raster page-image endpoint in pinned KOReader: images decode during Draw. Parent selected Option A to preserve the user-requested exclusion of drawing: report genuine non-equivalent milestones plus limited layout/navigation and retained reference-copy intervals. No equal-work ranking or homepage replacement from readiness diagnostics. Option B matched raster output would add drawing to the requested interval and is outside this run. Lead continues fresh 108-job schedule, post-timing correctness validation, one review and fixes. Branch t3/rerun-epub-preparation-benchmark; worktree t3-d6d84f15.

**2026-11-11T14:38:31Z**

Sol lead stopped: Codex usage limit. Its partial work is commit 403629c6 on t3/rerun-epub-preparation-benchmark. User restated the goal: exclude emulator-skewed work (for example software rasterization) symmetrically from all engines, keep work that costs the same on emulator and phone. Plan section 'Revised goal' replaces the Option A scope. New lead: Claude Opus 5.5 xhigh.

**2026-11-11T15:41:47Z**

Claude lead: classification reported to parent. User decision (2026-11-11): headline interval runs from engine entry through each engine's real drawing; Bookfin/WebView on a host-GPU emulator (Apple M1 Max via emulator GL translator), KOReader through drawCurrentPage; SwiftShader pre-raster numbers kept as a labeled diagnostic. Own AVDs bookfin-bench-sym (SwiftShader, reproduces all 63 frozen references) and bookfin-bench-gpu (host GPU, separate 63-page reference set) on emulator-5558. Fixed WIP bugs: Lua received JSON '\/' escapes (every KOReader job failed); persistent scratch buffer freed by GC.

**2026-11-11T16:15:01Z**

The first drawn-page run (sym-drawn) counted the WebView's first-frame setup in its fresh open: preparation-to-drawn median 233 ms against 12-17 ms for other WebView actions, while the Flutter shell does that setup before it reports ready. The WebView shell now reports ready only after a visual-state callback for its own page; the device test asserts shell_drawn_ns <= shell_ready_ns (red: red-device-shell-drawn-webview.txt). One measured WebView job per book then gave 17.9-23.0 ms on fresh open (experiment-shell-drawn). The full schedule runs again as sym-drawn2.

**2026-11-11T17:16:26Z**

Parent and user decision: the drawn-page interval leaves out the idle wait for the next frame and keeps the frame's own work; no with-wait column is reported. Bookfin: drawn page = raster finish - engine entry - max(0, build start of the drawing frame - preparation); max() because 9 of 36 Bookfin fresh opens finish preparation inside the frame (build start up to 14.8 ms earlier), so adding (raster finish - build start) to preparation would count that overlap twice. WebView: the shell reports the renderer's first main-frame start after preparation (requestAnimationFrame) and subtracts the same max(0, frame start - preparation). Probe.ready now returns only after the UI thread requested the visual-state callback, and the page-text extraction moved after the timed frames. Remaining WebView asymmetry, counted per sample: when the page's frame misses Android's draw for its vsync, Android answers after the next vsync (5 of 39 experiment samples). Red logs: red-frame-wait-tests.txt, red-device-frame-wait-webview.txt, red-webview-answer-tests.txt, red-webview-vsync-tests.txt.
