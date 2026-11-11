# EPUB engine shells: blocked build checkpoint

This section preserves the first checkpoint. The resumed implementation and test-runner method are in `epub-engine-method.md`. The original device reservation was released by its owner. A later repeated launch failure stopped manual device driving. Genuine AndroidJUnitRunner workload tests now execute all three engines. Do not treat the historical zero-sample files as the resumed dataset.

This is not a completed engine comparison. There are no new Android timing samples to publish. Do not use this checkpoint for a homepage speed claim. The settled measurement protocol remains `docs/plans/epub-engine-comparison.md`.

The work happened on November 10, 2026, in New York. The device launch failed at November 11, 2026, 00:23:26 UTC. These are the same local evening, not two runs on different days.

## Device blocker

T3 `device_open` returned a binding for local `emulator-5556`, named `bookfin-api36`. The first launch through that binding returned:

```text
Error (DEVICE_IN_USE): Device is already in use by session "t3-130af3b15755d2b73cadb1b2".
```

The diagnostic request is `835ee79910b0df20`. The exact diagnostic records are in `tool/research/epub_engines/evidence/device-launch.ndjson`. The full error and ownership limits are in `evidence/device-blocker.txt`, relative to that directory.

The owner must release that session before this task can continue. No other session was reused or closed. No alternate input driver, subsequent launch, input, screenshot, or device-close was attempted. The earlier gesture failure in `boo-kdc6` remains untested. Neither `emulator-5554` nor Pixel was used. The first minimal WebView smoke APK installed before the launch failed; the final probe APKs have not been launched.

## What is built

Each shell has its own Android package. Each APK uses the release build type. The shell signing key is a disposable research key under the ignored project cache, not a production key. Native library code in the bridge is compiled with `-O3`. The Android minimum API is 35 because the pinned NDK does not provide API 36 startup objects. The intended execution device remains API 36.

| Shell | Package | Real engine path | Build evidence |
|---|---|---|---|
| Bookfin | `dev.bookfin.bench.bookfin_epub_shell` | Production `loadReadingDocument`, `EpubPager`, `EpubViewport`, admitted-book cache, and `BookPageMaps` | `evidence/bookfin-build.txt` |
| Android WebView | `dev.bookfin.bench.epub.webview` | Android `WebView`, epub.js 0.3.93, and JSZip 3.10.1 | `evidence/native-build.txt` |
| KOReader engine in a shell | `dev.bookfin.bench.epub.koreader` | KOReader v2026.07.1 ARM64 release binary, through its actual Lua `cre` module | `evidence/native-build.txt` |

Bookfin's production code is unchanged from `6ba37d9a4a23be07f857d369da73115fedcc53fb`. The Git tree ID for `lib/reader/epub` is `b295e5a39618a94e183099a5fd2fbe532b36fd18`. The shell does not start catalog, account, audio, or record controllers. It does not register the production app's unrelated Flutter plugins.

The native dependency derivation is `tool/research/epub_engines/sources.nix`. It pins the download bytes for KOReader, epub.js, JSZip, and Gradle. The source checkout remains in the bound worktree; no checkout was created, switched, or reset. No production reader or homepage code changed.

### KOReader identity and interface

The upstream release is `https://github.com/koreader/koreader/releases/tag/v2026.07.1`. Its ARM64 APK SHA-256 is `89cecbe06eacd2ff7d91e37152d6beeb52809f2ca38060b6515ed8b00d152412`.

The release's `base` commit is `6e4bc81af4e04f78d81677a323a780a71b29702a`. Its `thirdparty/kpvcrlib/crengine` submodule commit is `b32a88ffbbf505cf2ea5208c1a49002d70d3609f`. The checkpoint had mistaken the containing `thirdparty/kpvcrlib` tree hash, `74bd5a1e2b924bced7513f39562f8fb95d7138e5`, for that submodule commit. The actual pinned release binary is unchanged.

Before writing the bridge, the upstream build and interface were inspected in `koreader-base/cmake/crengine/CMakeLists.txt`, `koreader-base/cre.cpp`, and `koreader/crengine/CMakeLists.txt`. The Android release exports `luaopen_cre` from `libkoreader-monolibtic.so` and ships `libluajit.so`. The shell calls that module's font registration, document loading, pagination, navigation, and drawing functions. It copies the engine's color render buffer into an Android bitmap. It does not substitute another CoolReader build or implement its own text layout.

The monolithic library also contains other KOReader native dependencies. The shell does not start KOReader's Android activity, reader UI, plugins, or application state. A future result must say “KOReader engine in a shell,” not “KOReader app performance.” Upstream source is available at the exact release and commits above. The binaries are downloaded by the derivation, not committed to this repository. KOReader's GPL obligations still apply to distribution of a shell containing them.

## Corpus and settings

The three original public EPUB files were copied from the existing public corpus cache. Every file's SHA-256 was checked against `tool/reader/epub_corpus.json`. The copies are identical across the shells. No personal library, account, or server was opened.

`evidence/corpus.json` records original source URLs, full hashes, byte counts, section counts, each section's text length and image count, and the selected section. A section index counts from zero in the EPUB's spine, which is its reading-order list.

| Role | Public book | Bytes | Sections | Selected section index | Selected section text characters | Images in selected section |
|---|---|---:|---:|---:|---:|---:|
| Prose | Standard Ebooks, Pride and Prejudice | 831959 | 65 | 4 | 9532 | 0 |
| Long chapter | Standard Ebooks, Moby-Dick | 1165503 | 145 | 59 | 44804 | 0 |
| Illustrated | Standard Ebooks, Alice's Adventures in Wonderland, Tenniel | 18398869 | 20 | 5 | 11220 | 3 |

The requested viewport is 360 by 640 logical pixels. The requested font is the same `SourceSerif4.ttf`, at an 18 logical-pixel body size. The alternate size is 20. The font's hash is in the corpus manifest. Bookfin's production line spacing is 1.65. The WebView probe requests the same spacing. KOReader requests 165 percent spacing and rounds its physical-pixel font size to an integer. Paper and text colors match Bookfin's cream theme.

These requests are not proof that the resulting layouts match. Publication styles, embedded fonts, line breaking, margins, image sizing, and KOReader's integer font sizes still need on-device inspection. No conclusion about speed or fidelity is supported yet.

## Probe events are not benchmark samples

The controls exercise open, reopen, next page, next section, and font-size change paths. A next-section jump is not a measured chapter crossing. A measured chapter crossing must turn from the preceding section's last page to the following section's first page. Reopen does not yet establish the protocol's prepared cache state.

The shells save diagnostic `unverified_probe` events and a cropped Android `PixelCopy` image. `PixelCopy` reads pixels from the Android window. It does not validate that the pixels contain the requested text, image, or destination. The shared capture code therefore sets `presentation_verified` to false.

Flutter raster timing, WebView's visual-state callback, and Android's frame-commit callback only gate diagnostic capture. None is reported as the time a correct page reached the display. The Android request and capture timestamps use the same monotonic clock, but this checkpoint does not summarize their difference as engine performance.

The Bookfin open probe currently opens the default page and then seeks the selected section. It is not yet a comparable selected-location fresh-open workload. The KOReader probe finds a contents heading, while WebView uses a section href. Their destination checks are not yet calibrated. These are explicit remaining harness tasks, not successful timing cells.

The result tool accepts only a separately validated `verified_window_capture` sample. It requires a matching destination, nonblank content, matching reference and capture hashes, explicit content and presentation verification, a known cache state, and valid timestamps from one clock. It rejects duplicates and excludes invalid rows and warmups with reasons. The empty `evidence/samples.jsonl` contains no synthetic measurements. `evidence/summary.json` has no cells and reports `complete: false`.

For future valid cells, median is the middle duration, or the mean of the two middle durations. The p90 value is the element at one-based rank `ceil(0.9 * count)` in sorted durations. Durations are reported in milliseconds. A complete sample matrix is not by itself proof that the protocol was followed.

`evidence/schedule.json` is an unexecuted balanced schedule. It assigns 12 process runs to each engine/book pair, 108 runs total. Each engine appears four times in each order position for each book. This is a workload plan, not an actual sample count.

## Reproduce the build checkpoint

Run from the repository root on the local Mac. The root Nix flake supplies Flutter, Java, Android SDK, and NDK. The separate derivation supplies the pinned competitor artifacts and Gradle. It does not change the user's shell profile or globally install a toolchain.

```sh
nix develop --command bash -c 'mkdir -p .cache/epub-engines; nix build --impure --no-link --print-out-paths --expr '\''let project = builtins.getFlake (toString ./.); pkgs = import project.inputs.nixpkgs { system = builtins.currentSystem; }; in import ./tool/research/epub_engines/sources.nix { inherit pkgs; }'\'' > .cache/epub-engines/source-path.txt'
```

Supply a public corpus directory containing the three pinned files. The file names are `se-pride-and-prejudice.epub`, `se-moby-dick.epub`, and `se-alices-adventures-in-wonderland.epub`. The existing corpus fetcher can obtain them along with the rest of the corpus:

```sh
nix develop --command python3 tool/reader/fetch_epub_corpus.py
nix develop --command bash -c 'python3 tool/research/epub_engines/prepare.py --corpus .cache/epub-corpus/books --sources "$(cat .cache/epub-engines/source-path.txt)"'
nix develop --command bash tool/research/epub_engines/build.sh
```

If an upstream EPUB changed, hash validation must fail. Do not replace a pinned hash to make an old and new run appear comparable. This checkpoint used already cached files whose hashes match the corpus manifest. No fixture server was started.

Build outputs are ignored rather than committed:

- `tool/research/epub_engines/bookfin/build/app/outputs/flutter-apk/app-release.apk`
- `tool/research/epub_engines/native/app/build/outputs/apk/webview/release/app-webview-release.apk`
- `tool/research/epub_engines/native/app/build/outputs/apk/koreader/release/app-koreader-release.apk`

After the existing owner releases the emulator, call T3 `device_open` again for host `local` and device `emulator-5556`. Use only the command returned by that call for launches, input, and screenshots. Each shell accepts `epubbench://run?book=prose`, `book=long`, or `book=illustrated`. Inspect genuine captures with T3 `device_screenshot`. If ownership or input fails again, follow the host error rule; do not bypass it.

## Checks and remaining work

The host-side Python tests cover validation, grouping, percentiles, warmups, invalid samples, duplicate IDs, missing round data, balanced order, corpus descriptions, and repeated materialization of read-only Nix files. The red and green logs are separate files under `evidence/`. The final combined Python run passes 17 tests. These tests use synthetic records only inside their test functions; none enter the sample file.

Text logs retain the tools' original whitespace. The evidence directory's Git attributes disable whitespace warnings for those captures, without relaxing checks on source files.

The isolated Flutter shell analyzer passes. The root project analyzer reports 76 issues in untouched acceptance and research tools, including obsolete `DiskCatalog` signatures and missing generated research files. It reports no issue in the new shell. Its output is retained rather than changing those unrelated files. `nix develop --command bash tool/bookfin test` passes: 2649 Flutter tests pass and 21 are skipped. The command and its exact exit state are in `evidence/project-tests.txt` and `evidence/project-test-status.txt`.

`evidence/environment.txt` records build-time host, SDK, emulator, WebView, and graphics facts. Reading these platform facts did not launch or drive an app. They are not metadata for an executed benchmark. `evidence/build-artifacts.json` records the three release APK paths, byte counts, and hashes. Its on-device status is blocked for each engine.

The attempted API 36 minimum build failed because the pinned NDK has no API 36 `crtbegin_so.o` or `crtend_so.o`. The failure is retained in `evidence/bookfin-api36-link-failure.txt`. Setting the shell minimum API to 35 resolves that build failure; it does not change the intended API 36 emulator. Initial compile and analyzer findings in the new shell were fixed before the successful release builds.

The following work remains before this task can pass:

1. Obtain approved ownership of `emulator-5556` and run smoke checks of every real engine. Confirm selected text and illustrated content, rather than only a load callback.
2. Finish one comparable operation runner, including exact selected-location fresh opens, true chapter crossings, explicit cache resets and preparation, first-process-start records, and whole-book pagination records.
3. Calibrate intended destinations and correct image/text captures. Choose and document one equivalent completion boundary. Keep render work separate from presentation if equivalent display completion cannot be established.
4. Execute the balanced schedule after all builds finish. Preserve every raw sample, failure, exclusion, cache state, round, and destination. Report actual counts and per-book median/p90 only for valid comparable cells.
5. Start the one authorized fresh read-only reviewer after complete implementation and measurements. Preserve its three verdicts and resolve findings with evidence. The reviewer was not launched at this blocked checkpoint.

There are no user-visible design forks at this checkpoint. The device ownership blocker is not a request to change the settled product design. Ticket `boo-kf2g` remains in progress for the parent to resume and integrate. No merge, push, PR publication, ticket closure, production optimization, coverage run, or mutation run occurred.
