---
id: boo-kf2g
status: closed
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

**2026-11-11T00:55:32Z**

Checkpoint77dcde7 reports three release probes built,17 host harness tests and2649 app tests passed,21 skipped; no timing samples or review yet. Parent verified blocked device session t3-130af3b15755d2b73cadb1b2 belongs to this parent thread through device_open. Closed it via its bound agent-device close (exit0, Closed confirmed), then device_close local/emulator-5556 shutdown=false. No other session or Pixel touched. Resumed same Sol xhigh lead to finish comparable workload runner, content verification, actual repeated measurements and one fresh review/fix. New taskId node:delegated-task:command%3Amcp%3Aff882773-a396-4499-bcf0-cd83fba58315%3Athread-send%3Asol-xhigh-boo-kf2g-resume-owned-emulator-released-20261110-1; clientRequestId sol-xhigh-boo-kf2g-resume-owned-emulator-released-20261110-1. Checkpoint not integrated; original review base and scope retained. Numeric homepage table remains pending.

**2026-11-11T01:14:27Z**

Lead reports own binding established, then KOReader launch and prescribed debug retry failed Activity not started, unable to resolve Intent. Read-only package inspection diagnosed missing installed KOReader/Bookfin APKs; KOReader subsequently installed. Parent did not authorize overriding host stop-after-retry rule. Directed completion of installation/package verification and genuine Android instrumentation/integration benchmark test-runner path if feasible, which host expressly permits; no adb am start/input, alternate UI driver or wrapper circumvention. Continue independent harness work if unavailable. Lead reports22 workload tests passing but no actual samples/reviewer yet.

## Build checkpoint, 2026-11-10 local / 2026-11-11 UTC

Implementation lead works in the bound `t3/measure-epub-engines` worktree from base `6ba37d9a4a23be07f857d369da73115fedcc53fb`. Ticket remains in progress; no comparison is complete.

Built three isolated optimized release APKs under `tool/research/epub_engines/`. Bookfin uses the unchanged production loader, pager, viewport, and cache paths. WebView uses pinned epub.js 0.3.93 and JSZip 3.10.1. The KOReader shell uses the real ARM64 v2026.07.1 release engine through its Lua `cre` module, not another CoolReader build. Pinned source artifacts and Gradle come from a small isolated Nix derivation. Public corpus files and the shared font are hashed. APK hashes are in `evidence/build-artifacts.json`.

The first approved launch failed at 2026-11-11T00:23:26Z: `DEVICE_IN_USE`, held by session `t3-130af3b15755d2b73cadb1b2`. T3 had returned a binding, but agent-device refused ownership when launching the smoke shell. Exact diagnostic request `835ee79910b0df20` is preserved in `evidence/device-launch.ndjson`. The other session was not reused or closed. No input driver bypass, subsequent UI operation, emulator-5554 use, or Pixel use occurred. The earlier boo-kdc6 gesture error remains untested.

Useful work continued without driving the held device. Host validation and balanced-order tests pass: 17 Python tests, with meaningful red/green logs. The isolated Flutter analyzer passes. Project tests pass: 2649 passed, 21 skipped. Project analysis reports 76 issues in untouched acceptance and standalone research tools; its failure is recorded, not repaired out of scope. No coverage or mutation job ran.

There are zero on-device timing samples. `evidence/samples.jsonl` is empty; `evidence/summary.json` has no timing cells and `complete: false`. The 108-run balanced schedule is unexecuted. Probe events are explicitly unverified and cannot be used for homepage claims.

Resume requirements: release the existing device session through its owner, obtain a fresh approved binding, validate all three engines' actual rendered destinations and images, finish the comparable cache/workload runner and completion calibration, execute balanced measurements, then launch the one authorized fresh reviewer and resolve findings. The reviewer has not been launched because the required implementation and measurements are not complete. There are no open product design forks. No production reader, homepage, library, account, or server changes were made.

Checkpoint details, limits, source identity, reproduction commands, and remaining work: `docs/research/epub-engine-shells.md`. Evidence directory: `tool/research/epub_engines/evidence/`.

## Resumed implementation, November 10 local / November 11 UTC

The parent released its own prior device reservation. A fresh T3 binding succeeded. A missing installed KOReader APK then caused both the launch and prescribed diagnostic retry to fail. Manual launches/input remain stopped under the host rule. The parent authorized genuine AndroidJUnitRunner tests of the internal shell workloads. All three release shells now complete real operation-sequence tests on emulator-5556. No alternate external UI driver is used.

The shared workload now opens the selected source chapter directly, waits for explicit pagination/cache preparation, reopens from a different visible chapter, performs actual page turns and actual chapter-boundary turns, and retains the source place during font changes. Calibration tests caught a wrong KOReader font-change destination and an unapplied paper color. Both wiring errors are fixed. The original checkpoint also mislabeled a containing source-tree hash as the crengine submodule commit. The pinned release APK is unchanged; the correct crengine commit is now recorded.

The common boundary is request-to-independent-reference window copy, not physical display latency. Separate calibration PNGs require successful workload assertions, source text, OCR text, and illustrated-page review before promotion. Device and host bind each timed record to the frozen reference manifest. Source, raw sequence, copy attempts, cache state, first-process facts, and whole-book pagination remain explicit. Final balanced timing runs and the one authorized fresh review are still pending at this implementation commit. See `docs/research/epub-engine-method.md`.

## Completed measurements, November 10 local / November 11 UTC

After all release and test APK builds and installations finished, the genuine instrumentation runner executed 108 sequential jobs in 12 balanced rounds. Each engine occupied each order position four times per book. All 108 workload tests passed. Host validation certified 1,404 measured samples across all 45 engine/book/operation cells, with no rejected measured samples or incomplete jobs. Each engine/book has 12 independent fresh opens and 36 samples of each other operation. The 1,080 preparation rows remain in raw evidence but outside timing cells.

The run lasted from 2026-11-11 02:33:51 to 02:43:24 UTC, or November 10 from 21:33:51 to 21:43:24 in New York. The one-minute host load rose from 1.77 to 11.19. The report discloses this noise, the window-copy boundary and capture overhead, instrumentation, Flutter texture composition, unequal full-pagination scope, warm chapter crossings, and visible layout/image-size differences. It makes no universal engine ranking or physical-phone claim.

Results, actual counts, metadata, limits, and reproduction commands: `docs/research/epub-engine-results.md`. Certified samples and all 45 timing cells: `tool/research/epub_engines/evidence/results/`. Raw schedules, commands, test assertions, preparation rows, and timed page captures: `tool/research/epub_engines/evidence/measured/`. Independent source/OCR/image-checked references and calibration evidence remain alongside them.

Final checks pass through Nix: 34 host harness tests; application analysis scoped to `lib test integration_test`; isolated shell analysis; Dart formatting; and `tool/bookfin test`, including native checks and 2649 passing Flutter tests, with 21 skipped. The earlier root-wide analyzer's 76 unrelated diagnostics remain recorded. No coverage, mutation, production renderer, homepage, private library, or server changes occurred. The single authorized fresh read-only review remains pending. This ticket stays in progress for parent integration.

## Fresh review and resolution

The single authorized read-only `codex` / `gpt-6.1-sol` / `xhigh` reviewer inspected original base `6ba37d9` through complete built/evidence HEAD `9f51a8f`. Original verdicts: correctness changes required; fulfillment changes required; design pass. The reviewer independently reconciled all 45 timing cells, nine startup summaries, counts, APK/corpus/font hashes, 63 reference images, and representative captured pages. No numerical discrepancy was found. Review and preserved original verdicts: `docs/research/epub-engine-review.md`.

Finding C1: failed non-draft calibration wrote its candidate output before refusing publication. Two meaningful failing tests reproduced replacement of accepted output and creation of rejected output. The publisher now rejects before writing. Seven calibration tests and all 37 host harness tests pass through Nix. Explicit draft behavior and successful publication remain tested. The accepted manifest, raw samples, metrics, engine code, and timing implementation are unchanged, so no device rerun is needed. Evidence: `tool/research/epub_engines/evidence/review-c1-*.txt`.

All review findings are resolved. No second review ran, and the original verdicts were not rewritten as passes. No unresolved product fork remains. This ticket is ready for parent integration, not closed. Homepage integration, merging, pushing, and ticket closure remain the parent's work.

**2026-11-11T11:12:03Z**

Parent integration inspected code diff, methodology, numerical results and fresh review resolution. Ticket-only conflict resolved preserving both histories. All37 harness tests pass through Nix on merged tree; parent reran collector against raw measured records and accepted references: all45 cells and diagnostic facts reproduce exactly,108 jobs complete,1080 preparation rows excluded. Reference digest unchanged. No application code differs from the tested base, so no duplicate full Flutter or device run is justified. Ready to close after this merge; homepage table is boo-cldw. Original review verdicts and evidenced C1 resolution preserved.
