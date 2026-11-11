---
id: boo-kf2g
status: in_progress
deps: []
links: []
created: 2026-11-11T00:13:41Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
---
# Measure three EPUB engines in minimal Android shell apps

Run fresh Android emulator measurements of Bookfin EPUB, epub.js in Android WebView, and KOReader crengine in minimal shell apps, as user requested for the homepage table. Same emulator, hashed public EPUBs, matched viewport/font/settings, release builds, explicit cache conditions and timing boundaries. Reuse current production Bookfin engine. Pin competitor versions. Run sequentially, preserve raw samples and rendered correctness evidence. Homepage claims await these results. No Pixel operations. Plan: docs/plans/epub-engine-comparison.md.

## Acceptance Criteria

All three real engines execute on the same emulator; repeatable raw measurements, honest timing boundaries, render verification, version/source/build metadata, cache definitions, sample counts and median/p90 summaries. Record blockers explicitly rather than substitute old host figures. Fresh independent read-only methodology/code review; parent integrates results and homepage table.


## Notes

**2026-11-11T00:14:43Z**

Started Sol xhigh ticket lead. taskId node:delegated-task:command%3Amcp%3Aff882773-a396-4499-bcf0-cd83fba58315%3Adelegate-task%3Asol-xhigh-20261110-boo-kf2g-epub-emulator-benchmark-1; childThreadId thread:delegated-task:command%3Amcp%3Aff882773-a396-4499-bcf0-cd83fba58315%3Adelegate-task%3Asol-xhigh-20261110-boo-kf2g-epub-emulator-benchmark-1; clientRequestId sol-xhigh-20261110-boo-kf2g-epub-emulator-benchmark-1. Review base 6ba37d9; one fresh Sol xhigh read-only reviewer authorized after build and measurement. Local emulator-5556 only, approved T3 binding required, no Pixel. Homepage boo-cldw depends on reviewed new benchmark results.
