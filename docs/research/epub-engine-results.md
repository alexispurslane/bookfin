# EPUB engines on bookfin-api36

The new run completed on November 10, 2026, from 21:33:51 to 21:43:24 in New York. That is November 11, 02:33:51 to 02:43:24 UTC. All 108 instrumented workload tests passed. Host collection certifies 1,404 measured samples in 45 complete engine/book/operation cells. It excludes 1,080 preparation rows from timing cells. There are no failed measured jobs or rejected measured samples.

## What these measurements mean

These are release engine shells on one Android emulator, not complete reader applications or physical-phone results. The boundary is engine request to completion of an independently checked Android window copy. It includes PixelCopy overhead, rendering, scheduling, content extraction, and any earlier failed copy attempts. It is not physical display latency or pure engine CPU time.

Read `epub-engine-method.md` before comparing numbers. In particular, KOReader eagerly paginates the whole book, Bookfin can backfill pagination, and WebView lays out chapters lazily. Font changes also do different amounts of total pagination. The three engines do not produce identical pages or equal illustration sizes. Bookfin uses Flutter texture composition for the shared capture boundary. AndroidJUnitRunner runs in each target process.

The emulator has Android 16/API 36, four ARM64 virtual CPUs, 2 GiB RAM, a 1080 by 2400 display, density 2.625, and a 60 Hz refresh rate. Its graphics path uses software SwiftShader through the Android Emulator OpenGL translator. The cropped reading viewport is 945 by 1680 physical pixels, or 360 by 640 logical pixels. Android WebView is 133.0.6943.137. The host is a 10-core ARM64 Mac with 64 GiB RAM. Results do not predict physical-phone performance.

The harness started no parallel heavy build or test during the timed schedule. Host load was not constant or zero. The one-minute load average rose from 1.77 before the schedule to 11.19 after it. Memory remained 49% free at both snapshots. These observations limit precision. The balanced order reduces order bias but does not prove a quiet host or remove all host noise. No run is removed because its time is inconvenient.

## Operation results

Each value is median / p90 in milliseconds at the window-copy boundary. The p90 uses nearest rank, `ceil(0.9 × count)`, without interpolation. Fresh opens have 12 samples per engine and book. Every other row has 36 samples per engine and book, from three operations in each of 12 independent processes. The three operations within a process are not 36 independent process starts. Every engine occupies each order position four times per book.

| Book | Operation | Count per engine | Bookfin | WebView + epub.js | KOReader engine in shell |
| --- | --- | ---: | ---: | ---: | ---: |
| Pride and Prejudice | Fresh open | 12 | 503.9 / 554.1 | 550.4 / 562.0 | 252.0 / 321.5 |
| Pride and Prejudice | Cached reopen | 36 | 109.0 / 136.8 | 180.6 / 251.2 | 67.4 / 90.7 |
| Pride and Prejudice | Sequential page turn | 36 | 58.9 / 68.6 | 66.0 / 114.8 | 61.4 / 74.4 |
| Pride and Prejudice | Warm chapter crossing | 36 | 58.4 / 75.5 | 89.8 / 98.7 | 67.2 / 78.7 |
| Pride and Prejudice | Font size 18 to 20 | 36 | 109.7 / 129.1 | 57.9 / 71.6 | 109.0 / 114.8 |
| Moby-Dick | Fresh open | 12 | 621.4 / 651.0 | 549.7 / 564.3 | 326.3 / 370.3 |
| Moby-Dick | Cached reopen | 36 | 107.4 / 127.6 | 239.5 / 307.6 | 67.0 / 80.7 |
| Moby-Dick | Sequential page turn | 36 | 58.8 / 66.6 | 62.2 / 73.6 | 67.4 / 78.3 |
| Moby-Dick | Warm chapter crossing | 36 | 59.0 / 66.3 | 91.3 / 110.6 | 66.6 / 74.9 |
| Moby-Dick | Font size 18 to 20 | 36 | 118.0 / 176.2 | 70.3 / 82.1 | 158.6 / 162.5 |
| Alice's Adventures in Wonderland | Fresh open | 12 | 700.3 / 825.5 | 682.9 / 749.9 | 183.2 / 216.0 |
| Alice's Adventures in Wonderland | Cached reopen | 36 | 131.7 / 142.1 | 540.3 / 635.3 | 72.2 / 80.3 |
| Alice's Adventures in Wonderland | Sequential page turn | 36 | 58.0 / 76.8 | 70.4 / 83.1 | 66.1 / 77.1 |
| Alice's Adventures in Wonderland | Warm chapter crossing | 36 | 58.1 / 61.1 | 79.7 / 97.4 | 60.0 / 76.3 |
| Alice's Adventures in Wonderland | Font size 18 to 20 | 36 | 111.5 / 125.0 | 77.3 / 90.7 | 75.7 / 79.1 |

These are observations at the stated boundary, not an overall engine ranking. The results do not support one universal speed ratio. The differing page layouts, eager pagination, texture composition, instrumentation, and software graphics remain part of the comparison.

## Startup, pagination, and copy facts

Every engine/book pair has 12 distinct Android process-start timestamps. The first-copy column uses each process's actual start-to-first-verified-copy interval. It is not the sum of two medians. Both startup columns include AndroidJUnitRunner and are diagnostic shell facts, not normal application launch times.

| Book | Engine | Process to shell ready, median ms | Process to first verified copy, median ms |
| --- | --- | ---: | ---: |
| Prose | Bookfin | 1008.2 | 1497.1 |
| Prose | WebView | 993.2 | 1542.3 |
| Prose | KOReader | 373.4 | 695.7 |
| Long | Bookfin | 1030.7 | 1647.3 |
| Long | WebView | 763.0 | 1315.3 |
| Long | KOReader | 586.8 | 889.5 |
| Illustrated | Bookfin | 1212.5 | 1918.2 |
| Illustrated | WebView | 897.4 | 1563.8 |
| Illustrated | KOReader | 624.7 | 816.4 |

At fresh-open completion, whole-book pagination is complete in 0/12 Bookfin opens, 0/12 WebView opens, and 12/12 KOReader opens for every book. After the separate preparation command, it is complete in 12/12 Bookfin and KOReader runs. Bookfin also reads the completed map from disk. KOReader closes and reopens to save and reuse its real cache. WebView does not create a whole-book page map here.

| Book | Bookfin preparation to adapter-ready, median ms | KOReader preparation to adapter-ready, median ms |
| --- | ---: | ---: |
| Prose | 1889.3 | 50.4 |
| Long | 2611.4 | 51.7 |
| Illustrated | 367.2 | 41.5 |

This preparation table is diagnostic. It is not another equivalent frame-completion comparison. Bookfin waits for remaining background pagination and persistence. KOReader's preparation follows an already eager full layout. WebView's preparation command is intentionally not whole-book pagination. Do not add medians to invent a full-book completion time.

The median duration of the final PixelCopy request is 12.9 to 15.7 ms across engine/book pairs. Maximum copy attempts are 3 for Bookfin, 2 for KOReader, and up to 24 for WebView. Earlier attempts and their hash checks remain inside the primary operation duration. Each raw sample retains its own copy duration and attempts. PNG storage is outside the ending timestamp. Timed PNGs are retained for round zero, while other rounds retain the matching pixel hashes and full metadata. Storage can change the gap between operations, during which real prefetch can continue.

## Evidence map

All paths below are relative to `tool/research/epub_engines/evidence/`.

| Evidence | Path |
| --- | --- |
| Hashed public books, selected sections, font, and versions | `corpus.json` |
| Release and instrumentation APK hashes | `build-artifacts-final.json` |
| Pinned KOReader library identity | `engine-source-identity.json` |
| Host, emulator, WebView, GPU, display, and tool facts | `environment-final.txt` |
| Separate accepted calibration workloads | `calibration-reviewed/` |
| Reviewed seven-case page sheets | `reference-sheets/` |
| Illustrated-page observations bound to pixel hashes | `image-reviews.json` |
| Frozen source/OCR/image-checked references | `references.json` |
| Executed schedule, exact commands, test outcomes, and raw records | `measured/` |
| Certified per-sample records | `results/samples.jsonl` |
| All median/p90/count cells and exclusions | `results/summary.json` |
| First-process, pagination, and capture facts | `results/facts.json` |
| Host load around the timed schedule | `benchmark-load-before.txt`, `benchmark-load-after.txt` |

The original `summary.json`, `samples.jsonl`, and `build-artifacts.json` describe the blocked checkpoint. They are not this run's results. Failed calibration attempts remain separate from the accepted calibration and measured data.

## Reproduce the workload

Use this worktree's pinned Nix shell. First materialize the pinned sources, public corpus, and assets with the commands in the build-reproduction section of `epub-engine-shells.md`. That historical section's source and asset commands remain valid. Do not follow its obsolete launch instructions. The current host rule stops manual launches and input.

Do not use manual activity commands or another UI driver. The accepted execution path is the genuine `EngineWorkloadTest` Android instrumentation test. The test starts a release shell, executes all 23 internal workload steps, and asserts destinations, page changes, chapter boundaries, font changes, paper color, and reference matches.

```sh
nix develop --command bash tool/research/epub_engines/build.sh
```

Install the three release APKs and their three release test APKs with `adb -s emulator-5556 install -r`. Exact installed paths are in `evidence/final-install.txt` and `evidence/ko-dpi-install.txt`. APK installation does not drive the UI.

To make a new independent calibration, use a new output directory and prefix:

```sh
nix develop --command python3 tool/research/epub_engines/run.py \
  --calibration --output /path/to/new-calibration --prefix new-calibration
nix develop --command python3 tool/research/epub_engines/calibrate.py \
  /path/to/new-calibration --output /path/to/references-draft.json --draft
```

Inspect the real calibration PNGs. Bind illustrated-page observations to their actual pixel hashes in an image-review JSON file. Promote only after source text, OCR text, workload assertions, stable repeated pixels, and image review pass:

```sh
nix develop --command python3 tool/research/epub_engines/calibrate.py \
  /path/to/new-calibration --output /path/to/references.json \
  --image-reviews /path/to/image-reviews.json
```

Copy that same frozen file to `/sdcard/Android/data/<package>/files/references.json` for each shell package with `adb push`. Package names are in `epub-engine-shells.md`. Use only the owned emulator and follow the current host rules. Build and install everything before timed work. Run no other heavy job alongside the schedule.

```sh
nix develop --command python3 tool/research/epub_engines/run.py \
  --output /path/to/new-measured --prefix new-measured
nix develop --command python3 tool/research/epub_engines/collect.py \
  /path/to/new-measured /path/to/references.json --output /path/to/new-results
```

The runner preserves the balanced 12-round order. It refuses to overwrite evidence and stops on failed real workload assertions. `--start` and `--limit` allow explicit continuation without replacing an earlier run. They do not make partial data complete. The collector keeps failures and preparation rows, excludes them from success cells, and reports incomplete jobs.

## Required verification

```sh
nix develop --command python3 -m unittest discover \
  -s tool/research/epub_engines -p 'test_*.py' -v
nix develop --command flutter analyze lib test integration_test
nix develop --command bash tool/bookfin test
nix develop --command bash -c \
  'cd tool/research/epub_engines/bookfin && flutter analyze lib'
```

The prior unscoped root analyzer failure remains in `evidence/project-analyze.txt`. Its 76 unrelated diagnostics are not silently converted into a pass. The final application analysis is scoped to `lib`, `test`, and `integration_test`, as directed by the parent.

The final checks pass: 34 host harness tests, application-scoped analysis, isolated shell analysis, Dart formatting, and `tool/bookfin test`. The project suite reports 2649 passed and 21 skipped. Native worker checks in that required command also pass. Exact logs and exits are `evidence/final-*.txt`. No coverage or mutation job ran. The one required fresh review remains pending at this results commit.
