# EPUB engines on one Android emulator

User request, 2026-11-10: run new tests in emulator shell apps for KOReader versus WebView versus the Bookfin EPUB reader, and use them in the homepage comparison.

## Scope and ownership

Minimal shell apps isolate each real engine from library, account, network, and audio work. Use current production Bookfin EPUB code, pinned epub.js in the emulator Android WebView, and the actual pinned KOReader crengine library. Label the last as KOReader engine in a test shell, not the complete KOReader app. Do not substitute an unrelated CoolReader build. Keep app package IDs separate from Bookfin and from each other. The benchmark owner records the inputs and schedule; each engine adapter owns loading, navigating and reporting completion through its real rendering path. One results tool validates and summarizes raw samples.

The benchmark ticket owns research harnesses, scripts, public evidence, methodology and its ticket. The homepage writer owns index.html and marketing evidence. The parent integrates, publishes, and closes tickets. No production renderer tuning in this comparison: discovered bugs become separate tickets.

## Comparable work

Use the same exact EPUB bytes and record SHA256. Include ordinary prose, a long section, and an illustrated or structured book from the existing public corpus. Record size, section count, chosen locations and sources. Match viewport dimensions, device pixel ratio, font file/size, line spacing, margins, theme and pagination as far as supported; disclose remaining differences. Confirm representative rendered pages contain the requested text and images before treating a timing as valid.

Measure fresh-book open, cached reopen, sequential page turns, chapter crossing and a font-size change. Define fresh explicitly: app/document/engine caches are empty; Android filesystem caches are not falsely claimed flushed. Record first process start separately from opening a book after the shell is ready. Define cached state and preparation time for each engine. Keep whole-book pagination costs visible even if one engine eagerly performs them and another lays out incrementally.

For each metric, use the same start and completion meaning. Prefer engine request to the completed frame containing the requested content; do not confuse loaded/relocated callbacks or scheduled paint with a displayed frame. If instrumentation cannot establish equivalent frame completion, report the available narrower boundary consistently and identify it, with separate presentation evidence. Never subtract unrelated clocks or fold fixed waiting delays into engine speed. Retain sample order, timestamps, operation, cache state, engine, book, expected/actual destination, completion boundary and errors.

## Execution

Run through pinned Nix tools. Build optimized release shells; if a necessary instrumentation mode differs, disclose and justify before comparing. Record commits, engine versions, WebView package/version, emulator ABI/API/RAM/CPU/display/GPU/refresh rate, host load and graphics backend. Run one engine at a time, no concurrent heavy builds during timed runs. Rotate engine order over repeated rounds. Keep warmups explicit and excluded. Aim for at least 10 independent fresh opens and 30 repeated operations per comparable cell; report actual counts and all exclusions/failures. Use per-book median and p90 with a documented percentile method; avoid an unsupported single overall speed ratio.

Known device input problem: boo-kdc6. Use local emulator-5556/bookfin-api36 only after device_open establishes an owned T3 session. Do not reuse/close emulator-5554 or any other session, and never touch Pixel. Every launch/relaunch/input/screenshot uses the returned device-bound agent-device command; screenshots inspected through device_screenshot. Follow the host failure rule. Builds, installation, logs and real project test runners may use normal tools. Do not disguise adb UI commands as a test runner. Automated operations inside the purpose-built benchmark shell are legitimate benchmark workload, not a replacement UI driver. Public dev servers are forbidden; any necessary fixture transfer server binds loopback only.

## Verification and reporting

Use behavior tests for result validation, grouping, percentiles, missing/failed samples and boundary mismatches before implementing that logic. Reuse the existing reader benchmark paths where appropriate instead of a second renderer. Check the shell output and save representative genuine captures. Retain source provenance, reproducible commands, compact raw results and analysis. A fresh reviewer assesses benchmark fairness, completion timing, engine identity, correctness validation and conclusions as well as code quality. No fabricated result when a build or device operation fails.

The homepage table uses only reviewed comparable new results. State Android emulator context; do not extrapolate timings to Pixel or to other platforms. Older host trial timings stay historical research. Cross-platform architecture claims remain distinct from performance measurements.
