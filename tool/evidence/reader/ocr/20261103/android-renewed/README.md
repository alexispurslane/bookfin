# Renewed offline Android OCR measurements

## Result and limits

The user explicitly renewed Android authorization for this bounded attempt on November 3, 2026. All three remaining engines completed fresh-install offline recognition. Engine, language, and distribution decisions remain with the parent and user. This evidence does not implement production optical character recognition (OCR), which converts page images into text.

English-best and Latin-fast each recognized seven pinned scans twice on their first run. Bundled ML Kit did the same without device networking or a model download. The prior English-fast comparison remains the two retained reports under `../../20261102/android-device/`. Those reports contain 28 recognitions. English-fast ran again only to establish a local previous report and measure cancellation/departure recovery after this attempt's fresh install.

This attempt retains 12 distinct completed reports and 168 recognitions. Partial canceled work is not included in that count. Two Latin-fast departure attempts completed before Back reached the app. Those are valid completed reports, not cancellation failures or stale publications. The final Latin-fast departure occurred during active work and preserved the previous report.

| Engine | Fresh offline run | Active-run cancellation and previous-report preservation | Leave/reopen and later successful run |
| --- | --- | --- | --- |
| English-fast | Already measured previously; local lifecycle seed also completed | Observed, with unchanged report after cancellation | Active-run departure preserved report; reopening and new run completed |
| English-best | 14 recognitions completed | Observed, with unchanged report after cancellation | Active-run departure preserved report; reopening and new run completed |
| Latin-fast | 14 recognitions completed | Observed, with unchanged report after cancellation | Final active-run departure preserved report; reopening and new run completed |
| Bundled ML Kit Latin | 14 recognitions completed | Not proved during active work; Cancel arrived after the run completed | Completed-run departure/reopen and later successful run observed; active-run departure not proved |

ML Kit completes this workload in 2.710–3.295 seconds. The next separately inspected command arrived after completion. No queued UI action, shell UI runner, delayed mutation, or replacement binding was used to manufacture an in-flight result. Follow-up `t6-h28u` records the remaining research measurement gate. No actual native interruption is claimed for any engine. Cancellation lets the current native page finish before subsequent queued work runs.

## Exact source, artifacts, and conditions

Probe source: `838d8a4a0b6f2a55f0042df042ab5f5b97df51df`. The original `bookfin-source-838d8a4.tar.gz` SHA-256 is `d723f7bc35de18ef92ec727957dd591a8d42690a9eb58602c124f5009feae0a7`. SHA-256 identifies exact file bytes. The archive was extracted into this checkout's ignored `.cache/ocr-android-renewed/` directory, not the builder checkout. Its research documentation, engine/lifecycle source, scorer, and tests were read without modification. The artifact manifest and full exact hashes also remain in the previous evidence directory. `conditions/artifacts.txt` repeats actual hashes and permission inspection for the four installed engines.

The bound device was T3 host `local`, `emulator-5554`, an ARM64 API 36 emulator named `bookfin-api36`. It is not a physical phone. This attempt used one fresh binding, `t3-c5bb6c7c6c32544633e60c52`. Every launch, Back action, tap, screenshot, and settings change used its returned device-bound command. `device_screenshot` inspected the screen. No other session was reused.

| Condition | Observed value or scope |
| --- | --- |
| Fingerprint | `google/sdk_gphone64_arm64/emu64a:16/BE2A.250530.026.F3/13894323:userdebug/dev-keys` |
| Display | 1080 × 2400 pixels; density 420 |
| Guest RAM | 2,021,944 KiB total; initial available RAM 621,788 KiB |
| Battery | AC powered; 100%; 25 °C |
| Initial host load | 4.22 / 4.31 / 3.53 over 1 / 5 / 15 minutes; shared host, not isolated |
| Before first launch | No owned probe package/process existed before installation; each private `files` directory was absent after installation |
| Device network | Airplane on, Wi-Fi off, mobile data off; `Active default network: none` before first launch and after all measurements |
| Permissions | No installed probe requests Internet or network-state permission; ML Kit requests only its own signature-level receiver permission |
| Audio | Media already muted; effective stream volume zero before, throughout measured endpoint checks, and after cleanup; no host audio changes |

All four original APKs installed successfully while offline. No existing data or previous installation was reused. Nix fetched host development dependencies, not device models. Processes from earlier probes remained resident while later probes ran. Work was sequential, but neither guest nor host caches, load, or other applications were isolated. A fresh run means fresh app data and first engine creation, not a reboot or flushed filesystem cache.

The research Run button still overlaps the system status bar, as tracked in `te-bkuv`. Initial and reopened accessibility rectangles were inspected for each app. Run was at x=24..1056, y=24..150. The visibly exposed lower edge at (540,140) started the runs. Cancel was at x=24..1056, y=150..276. Fresh references or inspected coordinates were used. The source geometry was not patched. `screenshots/englishBest-initial.png` and saved UI trees retain this evidence.

## Initialization, memory, and timing

PSS means proportional-set process memory: shared memory counts in proportion to the processes that share it. KiB means 1,024 bytes. Java used memory and native allocated memory are in bytes. Maximum values are samples at 100-millisecond intervals, not exact peaks. Sampling adds overhead.

Initialization includes Tesseract model copying and engine creation together. The probe recopies its bundled model on every run. Model copying has no separate timer. ML Kit engine creation does not include all lazy work during its first recognition. Thus its small repeat initialization value is not a total model-startup cost.

The table compares fresh reports only. English-fast is the retained earlier attempt. Values are rounded to three decimals for time. Exact values, baseline PSS, all sample counts, and every supplemental report are in `summary.json`, `report-table.md`, and the raw reports.

| Engine and observation | Initialization ms | Full report ms | Sampled maximum PSS KiB | Sampled maximum native bytes | Sampled maximum Java bytes |
| --- | ---: | ---: | ---: | ---: | ---: |
| English-fast, retained previous fresh | 356.795 | 14,567 | 269,055 | 216,281,600 | 4,345,328 |
| English-best, renewed fresh | 467.225 | 32,717 | 281,440 | 231,172,816 | 2,422,032 |
| Latin-fast, renewed fresh | 1,063.776 | 21,377 | 358,416 | 306,220,784 | 2,385,168 |
| Bundled ML Kit, renewed fresh | 196.940 | 3,295 | 280,438 | 221,315,232 | 11,123,760 |

Latin-fast's later sampled PSS reached 414,998 KiB. This is retained, not hidden behind its smaller fresh value. Repeated initialization, cancellation, heap reuse, sampling, and shared-memory changes prevent attributing that observation to a leak from these samples alone.

`measurements.csv` separates recognition time from total asset-reading/decoding/recognition time for every pass. `decodeAndInputOverheadMs` subtracts recognition time from that total. It includes asset reading, bitmap decoding, and small measurement bookkeeping. It is not a separately timed pure bitmap-decoder measurement. Initialization is outside both page timers. Pass 1 is not relabeled steady state.

Android Tesseract reports identify Tesseract4Android 4.9.0 with Tesseract 5.5.1 and bundled Leptonica 1.85.0. The prior host investigation used Tesseract 5.5.3 and Leptonica 1.87.0. The ML Kit candidate uses bundled Latin text-recognition 16.0.1. Neither cross-version host times nor these emulator observations predict physical-device or release-build performance.

## Recognition quality and image inspection

All seven exact images were opened independently in this attempt. The three visible poem lines match the unchanged reference transcription, including the dropped initial O and the em dash after `lore`. Each report passed the unchanged pinned scorer with the exact images and reference bytes extracted from the baseline APK. No full historical page, NIST page, or Census page was scored without a full independent transcription.

The scorer composes Unicode, ignores case, and collapses whitespace. Punctuation and accents remain significant. A word edit is an insertion, deletion, or substitution relative to the reference words. The table gives word edits / reference words for each pass of each fresh report. Supplemental reports retain the same scores.

| Engine | Historical three-line crop | Generated English | Generated French |
| --- | ---: | ---: | ---: |
| English-fast, previous | 2 / 31 | 0 / 37 | 6 / 40 |
| English-best | 4 / 31 | 0 / 37 | 6 / 40 |
| Latin-fast | 4 / 31 | 0 / 37 | 0 / 40 |
| Bundled ML Kit | 6 / 31 | 0 / 37 | 4 / 40 |

These tiny references do not establish broad language accuracy. ML Kit's French output retains the accents but removes the spaces before the colon and question mark. Those two character deletions produce four word edits under the fixed whitespace-token scorer. The score is not relabeled as four misspelled French words.

The new reports were also inspected qualitatively against the opened full images:

- English-best omits the dropped O, changes punctuation, and confuses I with T/IT in the crop. Its historical full page includes stray text from decorative material and margin marks.
- Latin-fast also omits the dropped O. It adds a colon near `weak`, reads decorative title material poorly, and converts some historical punctuation and letters incorrectly.
- ML Kit moves the crop's `ONCE` to the end, omits the full-page decorative title, and reads `upon` as `npon`. Its historical output also includes handwritten library-mark fragments.
- NIST prose is largely readable on inspection. English-best reads the final Roman numeral as `IIL`; Latin-fast reads it as `M`. These observations are not quantified full-page accuracy scores.
- Census text from both Tesseract candidates follows the three columns on inspection but still includes character errors. ML Kit interleaves the left-column title and middle-column body, including the broken fragment `Ceneand programs.`. Local recognition does not solve reading order.

## Lifecycle chronology and command boundary

`lifecycle/device-events.ndjson` records exact host command times. Reports record guest wall-clock times. These are evidence of order, not sub-millisecond synchronized clocks. UI snapshots and byte comparisons provide the direct report-preservation checks.

| Engine | Cancellation/departure evidence, UTC November 3 | Completed recovery |
| --- | --- | --- |
| English-best | Active run started 12:50:19; Cancel 12:50:33; previous fresh report unchanged. New active run 12:51:03; Back 12:51:16; reopen returned research screen and unchanged report. | New report started 12:52:20.069, completed 12:52:51.273, 14 recognitions |
| Latin-fast | Active run started 12:56:09; Cancel 12:56:26; previous fresh report unchanged. Two later runs finished before Back. Final active run started 13:01:37; Back 13:01:46; previous completed report unchanged after reopen. | New report started 13:02:46.097, completed 13:03:06.593, 14 recognitions |
| English-fast | Active run started 13:09:43; Cancel 13:09:51; local seed report unchanged. New active run 13:10:18; Back 13:10:26; local seed report unchanged after reopen. | New report started 13:11:11.099, completed 13:11:25.274, 14 recognitions |
| Bundled ML Kit | Second report completed 13:05:23.125 before Cancel 13:05:54. Next report completed 13:06:41.595 before Back 13:06:51. No active-work preservation claim. | Reopen returned research screen; subsequent report 13:07:45.700–13:07:48.466 completed all 14 recognitions |

For the three Tesseract candidates, canceled generations did not replace the previous report or repopulate the cancellation UI. Reopening after active-run departure returned the research screen. Subsequent runs produced new complete reports. No engine-close crash was observed. The bounded owned-process logs contain no fatal exception, fatal signal, or ANR marker. ANR means Android's application-not-responding error. The logs are not proof that no possible crash exists.

One device command was refused before dispatch:

```text
Error (COMMAND_FAILED): Ref @e2 needs a complete snapshot — the current frame only authorizes its emitted refs
Hint: Capture a fresh interactive snapshot (snapshot -i) or use a stable selector, then retry.
Diagnostic ID: mw0paozz-ccc8a277
```

The refusal followed a settled diff that did not authorize the old Cancel reference. The exact advice was followed once: capture a fresh interactive snapshot, inspect it, then retry the reference. That retry succeeded. The diagnostic is retained. No command timeout occurred in this attempt, no failed retry was ignored, and no replacement binding was opened. This refusal is not an OCR-engine failure. The attempt ended after the bounded measurements and cleanup, not after an engine-failure classification.

## Package and private storage

Values below are allocated directory storage from `du`, in KiB. Package storage includes the installed package directory. Private storage includes the owned app directory visible through `run-as`. These sums exclude storage outside those paths, system-managed compilation/profile data, and complete Android StorageStats accounting. They are not complete installed-app totals or changes to production Bookfin size.

| Engine | APK bytes | Package directory KiB | Private directory KiB | Limited-scope sum KiB | Copied private model bytes |
| --- | ---: | ---: | ---: | ---: | ---: |
| Size-only baseline, previous | 13,501,906 | 13,200 | 24 | 13,224 | 0 |
| English-fast | 25,217,465 | 24,632 | 4,108 | 28,740 | 4,113,088 |
| English-best | 36,504,975 | 35,656 | 15,128 | 50,784 | 15,400,601 |
| Latin-fast | 110,489,194 | 107,904 | 87,380 | 195,284 | 89,384,811 |
| Bundled ML Kit | 29,187,843 | 28,516 | 140 | 28,656 | No copied model in private files |

ML Kit creates private data-transport database and preference files. Only names and directory sizes were inspected. No contents, telemetry transmission, absence of telemetry code, or terms compliance is inferred. Its model remains bundled in the package, not absent merely because no private model copy appears.

## Cleanup and remaining gates

Only the four owned probe packages were uninstalled. The size-only baseline was not installed again. Readback found no owned probe packages or processes after uninstall. Original airplane/Wi-Fi/mobile-data values were restored to 0/1/1 through the same bound command. Media remained muted with effective stream volume zero. `conditions/cleanup.txt` records this before binding release. Release uses `shutdown:false`, leaving the emulator running. No normal Bookfin package, data, port, server, or acceptance route was changed. No app build, normal application acceptance suite, hardening job, child agent, ticket closure, or production engine choice occurred.

Remaining gates are explicit:

- `t6-h28u`: prove active-work ML Kit cancellation, stale-publication rejection, and active-run departure with separately inspected device actions.
- `te-bkuv`: fix research-only Run/Cancel system-bar geometry before relying on semantic Run presses.
- Measure complete Android StorageStats totals only if the parent requires complete installed accounting.
- Parent/user engine and language selection, physical-device/release measurements, and distribution/terms review remain separate. ML Kit Latin terms are unresolved. Tesseract/wrapper/model Apache-2.0 notices and separate native-library notices do not constitute clearance.
- Production reflow/search, page positions, cache and synchronization acceptance remain outside this probe evidence.

## Reproduction and inventory

`raw/` contains untouched private reports. `scored/` contains the pinned scorer output. `lifecycle/` contains UI snapshots, prior-report readbacks, command chronology, and the single command diagnostic. `conditions/`, `storage/`, and `screenshots/` retain the bounded observations. `derive.py` derives `summary.json`, `measurements.csv`, and `report-table.md` without changing raw reports or scoring rules. `SHA256SUMS` covers every evidence file except itself.

The source archive and APKs remain at `/Users/alexispurslane/.t3/worktrees/bookfin/t3-6bcb40a5/.cache/artifacts/ocr-20261102/`. Exact scan bytes are recoverable from the hash-identified baseline APK's `assets/scans/` directory. The prior evidence already retains the unchanged manifest and three reference files. No scans or references were regenerated for this attempt.

Every raw report passed `score_android.py` from the exact source archive. The archive's five scorer-integrity tests and five normalization/quality tests also passed through its pinned Nix development shell. These ten tests are not Android lifecycle acceptance or mutation testing. Evidence validation additionally checks raw/scored text and timing identity, unique completed timestamps, 14 recognitions per report, previous-report equality, and file hashes.

From this checkout root, after extracting the source and exact scans into the stated ignored directory:

```sh
nix develop path:$PWD/.cache/ocr-android-renewed/bookfin/tool/research/ocr --command python3 .cache/ocr-android-renewed/bookfin/tool/research/ocr/score_android.py tool/evidence/reader/ocr/20261103/android-renewed/raw/mlkit-fresh.json .cache/ocr-android-renewed/scans tool/evidence/reader/ocr/20261103/android-renewed/scored/mlkit-fresh.json
nix develop path:$PWD/.cache/ocr-android-renewed/bookfin/tool/research/ocr --command python3 tool/evidence/reader/ocr/20261103/android-renewed/derive.py
```

where

- `$PWD` is this prepared checkout root.
- `nix develop` runs the command with pinned host tools; `path:` includes extracted ignored files.
- `python3` is the development shell's Python interpreter.
- `score_android.py` reads an actual private report, exact scans, and references, then writes the named scored report.
- `derive.py` reads all retained scored reports and derives the evidence tables without executing an OCR engine.

Raw text captures keep their original whitespace. Authored documentation and the analysis script are checked separately from those bytes.
