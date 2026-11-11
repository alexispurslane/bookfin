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

## Build checkpoint, 2026-11-10 local / 2026-11-11 UTC

Implementation lead works in the bound `t3/measure-epub-engines` worktree from base `6ba37d9a4a23be07f857d369da73115fedcc53fb`. Ticket remains in progress; no comparison is complete.

Built three isolated optimized release APKs under `tool/research/epub_engines/`. Bookfin uses the unchanged production loader, pager, viewport, and cache paths. WebView uses pinned epub.js 0.3.93 and JSZip 3.10.1. The KOReader shell uses the real ARM64 v2026.07.1 release engine through its Lua `cre` module, not another CoolReader build. Pinned source artifacts and Gradle come from a small isolated Nix derivation. Public corpus files and the shared font are hashed. APK hashes are in `evidence/build-artifacts.json`.

The first approved launch failed at 2026-11-11T00:23:26Z: `DEVICE_IN_USE`, held by session `t3-130af3b15755d2b73cadb1b2`. T3 had returned a binding, but agent-device refused ownership when launching the smoke shell. Exact diagnostic request `835ee79910b0df20` is preserved in `evidence/device-launch.ndjson`. The other session was not reused or closed. No input driver bypass, subsequent UI operation, emulator-5554 use, or Pixel use occurred. The earlier boo-kdc6 gesture error remains untested.

Useful work continued without driving the held device. Host validation and balanced-order tests pass: 17 Python tests, with meaningful red/green logs. The isolated Flutter analyzer passes. Project tests pass: 2649 passed, 21 skipped. Project analysis reports 76 issues in untouched acceptance and standalone research tools; its failure is recorded, not repaired out of scope. No coverage or mutation job ran.

There are zero on-device timing samples. `evidence/samples.jsonl` is empty; `evidence/summary.json` has no timing cells and `complete: false`. The 108-run balanced schedule is unexecuted. Probe events are explicitly unverified and cannot be used for homepage claims.

Resume requirements: release the existing device session through its owner, obtain a fresh approved binding, validate all three engines' actual rendered destinations and images, finish the comparable cache/workload runner and completion calibration, execute balanced measurements, then launch the one authorized fresh reviewer and resolve findings. The reviewer has not been launched because the required implementation and measurements are not complete. There are no open product design forks. No production reader, homepage, library, account, or server changes were made.

Checkpoint details, limits, source identity, reproduction commands, and remaining work: `docs/research/epub-engine-shells.md`. Evidence directory: `tool/research/epub_engines/evidence/`.
