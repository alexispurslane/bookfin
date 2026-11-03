# Partial Android OCR probe measurements

## Result and stop boundary

This is research evidence, not production OCR acceptance or an engine/language choice. Device work stopped after the second bound-device command timeout. No replacement binding was opened. Only the baseline and English-fast apps were installed. The other three engines have no Android measurements in this attempt.

All five APK hashes and the matching source archive hash match the manifest from documentation commit `562dec23c11bce782b13935e49b2b126a94ea325`. Probe source is `838d8a4a0b6f2a55f0042df042ab5f5b97df51df`. The retained `artifact-manifest.json` is that unchanged upstream manifest: its original `androidInstalled` and `androidBenchmarked` flags describe the builder milestone, not this later partial attempt. `summary.json` describes this attempt.

| Probe | Observed Android work | Acceptance limit |
| --- | --- | --- |
| baseline | Fresh offline launch; Run control disabled; package/private directory storage measured | No recognition engine; no recognition attempted |
| englishFast | Fresh offline run and same-process repeat; seven exact scans, two passes each; 28 page recognitions scored | Cancellation/leave/reopen partially observed; no completed recovery run |
| englishBest | APK hash and actual APK permission list checked | Never installed or launched |
| latinFast | APK hash and actual APK permission list checked | Never installed or launched |
| mlkit | APK hash and actual APK permission list checked | Never installed or launched; terms review remains separate |

## Device conditions

- Device lane: T3 host `local`, `emulator-5554`, Android API 36, ARM64, `sdk_gphone64_arm64`. Exact system fingerprint is in `conditions/offline-start.txt`. This is an emulator, not a physical phone.
- Display: 1080 by 2400 pixels, density 420. Guest memory reports 2,021,944 KiB total RAM. The shared host and existing guest processes were not isolated or reset. Battery reported AC power, 100%, and 25 degrees Celsius.
- Local date was November 2, 2026, America/New_York. Raw reports and diagnostic logs use UTC timestamps on November 3, 2026. Fresh recognition ran 01:21:30.083–01:21:44.650 UTC; repeat ran 01:27:47.552–01:28:01.910 UTC.
- Before either fresh install was first launched: airplane mode on, Wi-Fi off, mobile data off. Connectivity readback said `Active default network: none`. Per-app prelaunch readbacks retain these values. Neither installed probe had previous data; the initial package listing contained no probe apps. The English-fast `files` directory did not exist before first launch; that expected readback failure is retained.
- Actual APK permissions were inspected with pinned Android `aapt`. All five lack both Internet and network-state permissions. Only ML Kit requests its own signature-level dynamic-receiver permission. No device model download or network-first launch occurred. Host-side Nix dependency fetching is not device networking.
- Media audio was already muted and stayed muted. Its effective stream volume was zero at the initial readback and after cleanup. No host audio setting changed. No normal Bookfin app/data, acceptance port, server, or service was changed.
- The first report is fresh app data and first process initialization, not flushed filesystem caches or a rebooted emulator. The repeat uses the same process. Both apps remained foreground during completed measurements. Device interaction and screenshots used only the returned bound `agent-device` command; `device_screenshot` inspected the screen.

## Initialization, memory, and page timings

Android reports identify `Tesseract4Android 4.9.0 / 5.5.1 / eng`. The documented host experiment used Tesseract 5.5.3 and Leptonica 1.87.0; Android packages Leptonica 1.85.0. Do not compare their timings as the same engine build or as a phone prediction.

Initialization includes model copying and engine initialization together. This probe does not measure model copying separately. Each run recopies the 4,113,088-byte English model, including the repeat.

PSS means proportional-set process memory: shared memory pages count in proportion to the processes that share them. KiB means 1,024 bytes. Java used memory and native allocated memory are reported in bytes. Values below are maxima of 100-millisecond samples, not exact peaks, per-page deltas, or a production memory budget. Sampling itself has overhead.

| Measurement | Fresh run | Same-process repeat |
| --- | ---: | ---: |
| Initialization including model copy, ms | 356.795334 | 107.698917 |
| Completed report duration, ms | 14,567 | 14,358 |
| Initial process PSS, KiB | 52,935 | 76,548 |
| Sampled maximum process PSS, KiB | 269,055 | 274,751 |
| Sampled maximum native allocated bytes | 216,281,600 | 218,108,864 |
| Sampled maximum Java used bytes | 4,345,328 | 2,475,216 |
| Memory samples | 147 | 145 |

Each cell below is recognition milliseconds / decode-plus-recognition milliseconds, rounded to one decimal. Pass 1 is not relabeled steady state. Initialization is outside these page timings. Exact unrounded timings for every pass are in `measurements.csv` and the raw reports.

| Exact scan | Fresh pass 1 | Fresh pass 2 | Repeat pass 1 | Repeat pass 2 |
| --- | ---: | ---: | ---: | ---: |
| raven-1873-page-9 | 751.1 / 1123.0 | 634.7 / 794.8 | 831.5 / 999.9 | 647.0 / 802.5 |
| raven-1873-page-9-poem-crop | 207.8 / 216.7 | 205.4 / 214.8 | 213.1 / 223.3 | 219.2 / 228.4 |
| raven-1873-page-10 | 1898.8 / 2037.8 | 1905.9 / 2039.5 | 2015.3 / 2158.5 | 1925.2 / 2070.6 |
| nist-cloud-page-5 | 895.4 / 919.1 | 865.6 / 888.3 | 892.4 / 913.8 | 870.6 / 894.0 |
| census-notice-page-1 | 2707.8 / 2743.2 | 2723.9 / 2754.2 | 2703.3 / 2734.0 | 2718.1 / 2754.0 |
| generated-english | 108.8 / 115.4 | 106.8 / 113.4 | 107.0 / 113.7 | 105.2 / 111.6 |
| generated-french | 105.5 / 111.5 | 103.8 / 110.2 | 105.4 / 111.6 | 104.3 / 110.5 |

## Recognition quality and independent image inspection

The tester opened all seven original scan images, including both full historical pages, the historical crop, NIST, the three-column Census page, and the generated English/French fixtures. The tester independently read the three visible crop lines and checked the exact bundled reference against the image, not the old PDF text layer:

```text
Once upon a midnight dreary, while I pondered, weak and weary,
Over many a quaint and curious volume of forgotten lore—
While I nodded, nearly napping, suddenly there came a tapping,
```

Capitalization is normalized by the supplied scorer, so the displayed small-cap `ONCE` is not a score difference. The image has a large dropped initial O. The recognized text omits it (`NCE`) and changes the comma after `dreary` to a period. Those are the two measured crop edits. No crop reference was changed.

Both actual reports passed the unchanged `score_android.py` with exact scan/reference bytes extracted from the verified baseline APK. Its manifest equals the reports manifest; each image and reference hash is checked by the scorer. Its SHA-256 is `2ba3612694b438d1f48e0e53e3b45eefff4262636424dc887998840b6581aa49`, identical in source archive and documentation commit. `quality.py` SHA-256 is `a26a9a81f443827ea543183df2dad664b706d71dfa738412f2fb2d4ae1ac53ed`, also identical. Source and scan extraction stayed in this checkout ignored `.cache/ocr-android-acceptance/`; the builder checkout was only read.

Word/character errors count substitutions, insertions and deletions after Unicode composition, case normalization and whitespace collapsing. Accents and punctuation remain significant. All four passes produced identical recognized text and the same scores:

| Referenced image | Word edits / reference words, each pass | Character edits / reference characters, each pass |
| --- | ---: | ---: |
| Historical poem crop | 2 / 31 | 2 / 182 |
| Generated English | 0 / 37 | 0 / 209 |
| Generated French | 6 / 40 | 7 / 214 |

Qualitative full-page inspection found the following, without assigning accuracy percentages:

- Raven page 9 retains the three poem lines but loses the dropped O. The decorative title becomes `ite Waven.` and an extraneous `f` appears before it. Artwork is not a reliable text boundary.
- Raven page 10 retains stanza sequence in this sample but produces margin/handwriting noise (`COA`, `558%`) and visible mistakes such as `cach` for `each` and `Donbting` for `Doubting`.
- NIST produces readable headings and paragraphs in their visible sequence. There is no independent whole-page transcription, so it remains unscored.
- Census output proceeds through the left, middle, then right column in this sample, including the continuation from the middle column into `advisory body` at the right-column top. This spot check is not an arbitrary-column/table reading-order guarantee. The terminal output was bounded; the complete retained raw report was also checked through its per-sample text.
- Generated English matches its exact input after normalization. Generated French loses or changes accents and misreads `où` as `ott`. These generated fixtures do not establish historical-page accuracy or broad language support.

The four whole-page images have no independently transcribed full truth. Their scored `quality` stays null. No score was fabricated from a PDF text layer. Larger-model, Latin-model and ML Kit quality comparisons remain unavailable.

## Measured installed-directory storage

`storage/` retains `pm path`, package-directory `du -ak`, and app-private `run-as ... du -ak` readbacks. This measures allocated directory blocks, including bundled APK assets and the private model copy. It is not the Settings StorageStats total: system-managed compilation/profile storage outside these directories was not measured. Directory rounding, reports and empty cache directories are included. Do not present these numbers as complete installed-device storage.

| App | Package directory, KiB | Private directory, KiB | Measured sum, KiB | APK logical bytes |
| --- | ---: | ---: | ---: | ---: |
| baseline | 13,200 | 24 | 13,224 | 13,501,906 |
| englishFast after report | 24,632 | 4,108 | 28,740 | 25,217,465 |

The measured directory difference is 15,516 KiB. English-fast includes the 4,113,088-byte model in its APK and another 4,113,088-byte private copy. Its private copy occupies 4,024 KiB of allocated blocks; reports and directory overhead explain the rest of the private total. Native libraries are loaded directly from the APK; the reported ARM64 extraction directories are empty. Nothing was inferred for the other installed-size candidates.

## Cancellation, leave/reopen, and tool failures

The lifecycle test is incomplete and does not pass acceptance. The retained sequence is:

1. A third English-fast run reached the visible `Recognizing census-notice-page-1 pass 1…` status. The Cancel press changed the UI to its cancellation message and enabled Run. Native completion at the instant of the press was not separately instrumented; the current-page drain is the probe contract, not a measured native interrupt.
2. The semantic Run press targeted y=87 after the layout changed and did nothing. The second wait consequently remained on the cancellation message. A coordinate Run press was submitted while that wait was pending; the device command queue executed it only after the wait ended.
3. A queued leave/reopen sequence then ran because that command batch used semicolons rather than fail-fast chaining. It left while the new run showed Raven page 9 pass 1, reopened to the initial research UI, waited 3.5 seconds and still showed that initial UI. The old report remained byte-identical to the completed repeat, both then and in the final pre-cleanup readback. The final queued semantic Run press also did nothing.
4. Once the second timeout was returned and observed, measurement stopped. Only report/log readback and cleanup followed. No completed recovery run was obtained. Own-process logs have no fatal exception or native crash in the captured interval, but this is not a guarantee beyond that interval or an acceptance pass.

The first wait failed at 01:25:51.167 UTC with `wait timed out for selector: text="initializationMs"`. It used an exact-text selector against a field inside the entire JSON TextView, although the fresh report had completed. The tool advised retrying with `--debug`; a fresh debug snapshot and wait on the new Run reference succeeded. Diagnostic ID: `mw005pgq-05b70d3e`.

The second wait failed at 01:30:13.361 UTC with `wait timed out for selector: text="Recognizing census-notice-page-1 pass 1…"`. The visible surface remained the cancellation message because the semantic Run press had not started a run. Diagnostic ID: `mw00f6nm-1f6c6368`. This repeated device-command failure triggered the stop rule, even though neither timeout demonstrates an OCR engine failure.

The start/failure diagnostic events are retained in `lifecycle/*-wait-diagnostic-excerpt.ndjson`; repetitive intermediate snapshots are omitted. Complete local diagnostic file SHA-256 values are `1e4cb56b278299524e3a29561c2ab800a0091cfd8c665e64aea32e67b9a626d5` (first) and `b4524a5a5e9cfb637d404597ea4fcd46954b103c3490ff402dd6b7af6254585b` (second). An earlier help query reported `Unknown command: keypress`; no keypress operation was attempted. Settings UI and audio readback confirmed the existing mute instead.

The Run-control geometry issue is tracked as `te-bkuv`. `englishFast-complete-ui.json` records y=24..150 for Run and its center at y=87. `screenshots/englishFast-fresh-complete.png` shows its overlap with the system status bar. Semantic and y=125 presses did not change the report; the visible lower edge at y=140 started the repeat. This research-only UI should be corrected or explicitly accommodated in an authorized continuation. A future batch must stop immediately when any device command fails, rather than execute queued mutations afterward.

## Cleanup and remaining limits

Cleanup restored the original airplane/Wi-Fi/mobile-data values to 0/1/1 with the same bound command. English-fast was closed with the bound command. Only the two owned research packages were uninstalled. Readback found no remaining probe packages or processes before T3 released the binding with `shutdown:false`. The emulator remains running. Final audio readback says `Muted: true` and `streamVolume:0`. `conditions/cleanup.txt` records the checks. No new binding was used to continue after failure.

Remaining work requires another explicitly authorized device attempt: complete the three unmeasured engine candidates; obtain complete cancellation/new-run/leave/reopen/recovery evidence for each engine; and measure Android StorageStats totals if complete installed storage accounting is needed. Do not merge a production stack merely to repeat these separate APK measurements.

The three Tesseract candidates package distinct model scopes; this English-only observation does not select one or promise other-language accuracy. The documented Tesseract/wrapper/model Apache-2.0 notices and separate native-library notices still require distribution review. Bundled ML Kit Latin terms remain a separate, unresolved product decision. No licensing clearance, absence of telemetry code, broad language support, production OCR, PDF/MOBI behavior, reflow/search integration, cache migration, or synchronization acceptance follows from this partial evidence.

## Evidence inventory and reproducibility

- `raw/`: untouched actual fresh/repeat JSON reports and fresh-run process log.
- `scored/`: outputs of the exact supplied scorer; untranscribed pages remain unscored.
- `inputs/`: exact bundled manifest and three references; scan PNG bytes remain recoverable from the hash-identified baseline APK.
- `conditions/`, `storage/`, `lifecycle/`, `screenshots/`: raw bounded observations, failures, cleanup and screen evidence.
- `summary.json`, `measurements.csv`, `latency.html`: derived summaries; raw reports are authoritative. `SHA256SUMS` identifies every retained evidence file except itself.

Verification also reran the archive five scoring-integrity tests and five normalization/quality tests through the research Nix shell: all ten passed. These existing tests do not substitute for actual device execution or establish lifecycle acceptance. No production implementation, mutation-testing job, or whole-application acceptance suite was run.

Raw device text captures retain their original trailing spaces and final blank lines. A whole-diff whitespace check reports those capture bytes; the focused whitespace check for authored ticket notes, this README, the summary JSON and derived CSV passes. Raw captures were not reformatted to hide those warnings.

Scoring commands used the archive research Nix shell and scorer, with no source edits:

```sh
nix develop path:$PWD/.cache/ocr-android-acceptance/bookfin/tool/research/ocr --command python3 .cache/ocr-android-acceptance/bookfin/tool/research/ocr/score_android.py tool/evidence/reader/ocr/20261102/android-device/raw/englishFast-fresh.json .cache/ocr-android-acceptance/scans tool/evidence/reader/ocr/20261102/android-device/scored/englishFast-fresh.json
nix develop path:$PWD/.cache/ocr-android-acceptance/bookfin/tool/research/ocr --command python3 .cache/ocr-android-acceptance/bookfin/tool/research/ocr/score_android.py tool/evidence/reader/ocr/20261102/android-device/raw/englishFast-repeat.json .cache/ocr-android-acceptance/scans tool/evidence/reader/ocr/20261102/android-device/scored/englishFast-repeat.json
```

where

- `$PWD` = this prepared checkout root, not the builder checkout.
- `nix develop` = run the command in the pinned research development environment; `path:` includes the extracted ignored source files.
- `python3` = the Python interpreter from that environment.
- `score_android.py` = the unchanged scorer from the hash-verified source archive.
- The first argument is an actual exported raw report; the second is the exact APK scan/reference directory; the third is a new scored-output file.
