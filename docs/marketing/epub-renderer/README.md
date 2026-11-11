# EPUB section: implementation sources and measurement status

The homepage section describes the production EPUB reader, not the former
WebView reader or the early native-renderer trial. Sources were checked against
Bookfin commit `0f12f5eac34870f4b7d199fdc5509fa24690177b` on November 10, 2026.
This note supports ticket `boo-cldw`.

## What the implementation supports

| Homepage claim | Source and scope |
| --- | --- |
| EPUB layout and drawing run in Flutter. | [`layoutSection` in `layout.dart`](../../../lib/reader/epub/layout.dart#L3155) lays out prepared EPUB sections. [`drawPage` in `paint.dart`](../../../lib/reader/epub/paint.dart#L23) draws paragraphs, images, and decorations through `dart:ui`. [`screen.dart`](../../../lib/reader/screen.dart#L531) opens the production `EpubViewport`. |
| There is no WebView fallback for EPUB. | The production reader routes EPUB to [`EpubViewport`](../../../lib/reader/epub/viewport.dart#L38). The current [`pubspec.yaml`](../../../pubspec.yaml) has no WebView dependency. References to epub.js in the EPUB source document compatibility with old saved places or the former reader, not an active browser fallback. The older recommendation in `docs/research/native-epub.md` is superseded. |
| Size, Cream/Night, selection, and Copy belong to the shared reader. | [`EpubViewport`](../../../lib/reader/epub/viewport.dart#L38) receives size and Night settings. Its [`ReaderCopyArea`](../../../lib/reader/epub/viewport.dart#L148) handles selection and reports selected text. [`screen.dart`](../../../lib/reader/screen.dart#L531) connects these controls to the reading session and clipboard. |
| Links and footnotes work within the reader. | [`_followLink`](../../../lib/reader/screen.dart#L215) opens a recognized note in the reader's note sheet. Other links go to their destination in the book. This does not promise that every publisher's link or note is recognized. |
| Touch, keyboard, and trackpad turn pages. | [`EpubViewport`](../../../lib/reader/epub/viewport.dart#L133) handles page-turn keys and uses `PageSwipes`. [`page_swipes.dart`](../../../lib/reader/page_swipes.dart#L15) handles touch, trackpad pan, and horizontal scroll. |
| EPUB uses one shared Flutter implementation across platforms. | The [platform model](../../plans/platforms.md#the-platform-model) identifies Flutter EPUB drawing separately from platform-specific services. The same `lib/reader/epub/` implementation is used, rather than a separate EPUB engine for each platform. |

The portability claim applies to the EPUB reader, not to the whole app being
pure Dart or to every platform already having a released app. PDF, OCR, audio,
and storage have native dependencies or platform services.

The [platform survey](../../plans/platforms.md#survey-per-platform) records
Android as the primary target and a working macOS EPUB implementation. iOS,
Linux, and Windows app ports are not generally delivered. The homepage says
this beside the shared-implementation claim, not only in this note.

## Other rendering approaches

| Table row | Verified source | Meaning |
| --- | --- | --- |
| Android WebView | [Android Developers: Build web apps in WebView](https://developer.android.com/develop/ui/views/layout/webapps/webview) | WebView embeds web content in an Android app. It is not itself an EPUB package reader. A reader must supply the EPUB content as HTML and CSS. This row does not call headless desktop Chromium an Android WebView measurement. |
| KOReader | [KOReader's production `credocument.lua`, pinned to `c3e5f750b4e7a1b5afc5f6b62bdf6a004e28e518`](https://github.com/koreader/koreader/blob/c3e5f750b4e7a1b5afc5f6b62bdf6a004e28e518/frontend/document/credocument.lua#L71) | The document provider is `crengine`. Line 104 loads `libs/libkoreader-cre`. Lines 1614–1616 register EPUB formats with this provider. Bookfin's [native EPUB research](../../research/native-epub.md#situation-check) also identifies it as the Cool Reader engine. No speed follows from its implementation language. |

These sources establish the rendering approaches. They do not establish a speed
ranking, identical features, or identical support for every EPUB stylesheet.

## Completed same-emulator measurements

The homepage shows one table of arithmetic mean times across three books:
*Pride and Prejudice*, *Moby-Dick*, and *Alice’s Adventures in Wonderland*.
For each engine and action, first average the measured elapsed times within
each book, then average those three book means. Each book has equal weight.
Round only the final result to one decimal millisecond. This is not an average
of medians or p90 values.

The [aggregate data](averages.json) records each book’s sample count, total
elapsed nanoseconds, mean, and the final equal-weight mean. Its source hash
identifies the unchanged [raw samples](../../../tool/research/epub_engines/evidence/results/samples.jsonl).
Only samples accepted by the existing benchmark validator enter the average.
There are 12 fresh opens and 36 samples of each other action per book and engine,
for 1,404 measured samples across 108 process runs. Equal sample counts mean
that pooling all three books gives the same arithmetic mean. The three warm
samples within a process are not independent process starts.

The original per-book median and p90 results remain in the
[full results](../../research/epub-engine-results.md), with the
[method](../../research/epub-engine-method.md),
[review](../../research/epub-engine-review.md), and
[summary JSON](../../../tool/research/epub_engines/evidence/results/summary.json).
No benchmark was rerun for this editorial change.

### Measurement scope

All three engines ran in small optimized release apps on the same Android 16
emulator on November 10, 2026. The emulator had four virtual ARM64 CPUs, 2 GiB
RAM, software graphics, and a 360 × 640 logical-pixel reading area. The measured
interval starts at the reading request and ends at a matching Android window
copy. It includes rendering, scheduling, content checks, and screenshot capture.
It is not pure engine CPU time, whole-app startup, or a physical Pixel measurement.

Fresh opens clear the test app’s book caches, but not Android’s file cache.
Cached reopens follow cache preparation. “Chapter turn (visited)” means turning
from the last page of one chapter into a chapter already visited in that run.
KOReader paginates the whole book during open and size changes. Bookfin can
finish pagination in the background. WebView lays out chapters as needed.
Page boundaries and illustration sizes differ.

Software graphics, Flutter texture composition, instrumentation, and changing
host load limit the comparison. The table does not establish an overall winner
or equal rendering quality. Historical desktop and headless-browser studies
are not included.

## Rerun timed through each engine's drawing

The table above includes Android's window copy and software graphics. A
fresh run on November 11, 2026, used a different interval. It starts at
the moment that the engine's own code receives the request. It ends after
the engine drew the requested page. Bookfin and WebView draw on the GPU.
KOReader draws on the CPU, as it does on a phone. The idle wait for the
next display frame before the drawing frame is left out, measured for each
sample. Only frame-based engines have that wait, and it depends on the
display refresh rate. The emulator for this run rendered on the host Mac's
GPU, an Apple M1 Max, through the emulator's OpenGL ES translator. A
host-GPU emulator is not a phone GPU. The
[method](../../research/epub-engine-drawn-page-method.md) gives the
details and the evidence.

### Drawn page on the host GPU

Each cell is the equal-book-weight mean in milliseconds, with the rule
above. Each engine has 12 fresh opens and 36 samples of each other action
per book, from 108 fresh process jobs.

| Action | Bookfin | WebView | KOReader |
| --- | ---: | ---: | ---: |
| Fresh open | 371.7 | 360.3 | 119.3 |
| Cached reopen | 45.2 | 284.3 | 17.6 |
| Page turn | 6.6 | 39.1 | 2.4 |
| Chapter turn (visited) | 3.2 | 41.1 | 3.1 |
| Size change | 34.5 | 50.2 | 68.8 |

Per book, each cell shows median / p90 (sample count) in milliseconds. The
p90 is the sample at rank ⌈0.9 n⌉ in ascending order.

| Interval | Action | prose | long | illustrated |
| --- | --- | ---: | ---: | ---: |
| Bookfin | Fresh open | 221.7 / 249.0 (12) | 295.2 / 311.2 (12) | 596.7 / 617.6 (12) |
| Bookfin | Cached reopen | 34.1 / 40.6 (36) | 41.1 / 52.0 (36) | 55.9 / 71.8 (36) |
| Bookfin | Page turn | 5.0 / 6.7 (36) | 5.3 / 6.7 (36) | 6.4 / 14.7 (36) |
| Bookfin | Chapter turn (visited) | 3.0 / 4.7 (36) | 3.0 / 4.4 (36) | 2.6 / 4.1 (36) |
| Bookfin | Size change | 33.8 / 42.0 (36) | 43.7 / 52.4 (36) | 20.8 / 46.1 (36) |
| WebView | Fresh open | 179.5 / 192.4 (12) | 240.2 / 248.5 (12) | 612.2 / 858.5 (12) |
| WebView | Cached reopen | 116.1 / 148.6 (36) | 174.7 / 186.9 (36) | 541.8 / 596.5 (36) |
| WebView | Page turn | 39.9 / 48.5 (36) | 36.7 / 40.0 (36) | 37.0 / 65.1 (36) |
| WebView | Chapter turn (visited) | 31.3 / 40.1 (36) | 37.9 / 49.3 (36) | 53.2 / 65.6 (36) |
| WebView | Size change | 52.8 / 56.0 (36) | 51.2 / 55.4 (36) | 51.0 / 55.1 (36) |
| KOReader | Fresh open | 104.4 / 120.8 (12) | 181.3 / 190.8 (12) | 77.0 / 83.5 (12) |
| KOReader | Cached reopen | 13.5 / 15.9 (36) | 15.6 / 17.8 (36) | 22.0 / 24.6 (36) |
| KOReader | Page turn | 1.9 / 2.5 (36) | 2.0 / 2.3 (36) | 2.4 / 4.4 (36) |
| KOReader | Chapter turn (visited) | 1.7 / 2.1 (36) | 1.8 / 2.2 (36) | 5.5 / 6.5 (36) |
| KOReader | Size change | 66.1 / 69.3 (36) | 114.9 / 117.8 (36) | 24.5 / 28.7 (36) |

Data: [summary JSON](../../../tool/research/epub_engines/evidence/symmetric-20261111/results-drawn3-gpu/summary.json)
and [accepted samples](../../../tool/research/epub_engines/evidence/symmetric-20261111/results-drawn3-gpu/samples.jsonl).

Each job ran only while the host was quiet. Before each job started, the
one-minute host load had to be under 8 on the Mac's 10 cores. During the
job, the runner read the load every second. A job with any reading of 8 or
more is set aside and measured again at the same place in the schedule. In
this run, no job was measured again: the highest reading during a job was
7.3 ([load record](../../../tool/research/epub_engines/evidence/symmetric-20261111/measured-drawn3-gpu/host-load.jsonl)).
The whole balanced schedule of 108 jobs ran again for two reasons. First,
the shells changed to leave out the frame wait. Second, another agent's
test run raised the host load to about 30 during the previous attempt,
`sym-drawn2`. That attempt kept no load record for each job. It stopped
after 20 jobs and is not used.

### Endpoints

| Engine | Start | End | Left out before the drawing frame |
| --- | --- | --- | --- |
| Bookfin | Dart reads its clock, then calls the production pager | Flutter's `rasterFinish` of the first frame that shows the page with its images decoded | From the end of preparation to that frame's `buildStart` |
| WebView | The page's JavaScript starts the epub.js command | Android's visual-state callback, requested after fonts, layout, and page images are ready | From the end of preparation to the renderer's first frame after it |
| KOReader | Lua starts the command | `drawCurrentPage` returns with every pixel drawn on the CPU | Nothing, KOReader has no frame clock |

If a frame began before preparation ended, nothing is left out. The
interval also excludes the hop from the Java shell into each engine,
composition, display, and the window copy. Content checks run after
timing, and only rows that pass them enter a cell.

### Remaining asymmetries

1. Waits that an engine schedules inside its own preparation stay. epub.js
   runs its work queue on animation frames. Bookfin runs pagination steps
   that are not urgent between frames.
2. WebView draws inside Android's frame. In 127 of 468 WebView samples,
   Android answered after a vsync that followed the start of the page's
   frame. The frame missed Android's draw at its own vsync. Those samples
   keep part of the wait for the next vsync: their frame work has a median
   of 13.9 ms, against 0.8 ms for the other 341. Chromium gives the page no
   timestamp that separates this wait from the frame's work.
3. Bookfin ends at the submission of its GPU commands. WebView ends after
   its tiles were rasterized, plus the answer's trip to Android's UI
   thread. KOReader ends after its last pixel is on the CPU.
4. KOReader paginates the whole book on open and size change. Bookfin
   completes its page map in the background. WebView lays out one chapter.
5. Page boundaries and illustration sizes differ between engines.

### Diagnostic: prepared page, before GPU rasterization

These tables are secondary. They end before any GPU rasterization:
Bookfin at a recorded picture with decoded images, WebView at layout,
fonts and decoded page images, KOReader after `drawCurrentPage`. The last
column ends KOReader before it draws. The first table is from the
software-graphics emulator (SwiftShader). The second is from the headline
host-GPU run.

SwiftShader, run `sym-sw`:

| Action | Bookfin | WebView | KOReader | KOReader before drawing |
| --- | ---: | ---: | ---: | ---: |
| Fresh open | 580.6 | 397.5 | 186.0 | 183.2 |
| Cached reopen | 59.1 | 344.9 | 17.7 | 14.5 |
| Page turn | 1.8 | 39.7 | 2.4 | 0.2 |
| Chapter turn (visited) | 0.3 | 61.9 | 3.0 | 0.2 |
| Size change | 38.4 | 33.6 | 73.5 | 71.0 |

Host GPU, the headline run `sym-drawn3`:

| Action | Bookfin | WebView | KOReader | KOReader before drawing |
| --- | ---: | ---: | ---: | ---: |
| Fresh open | 352.6 | 350.3 | 119.3 | 117.0 |
| Cached reopen | 41.8 | 274.9 | 17.6 | 14.8 |
| Page turn | 2.2 | 35.1 | 2.4 | 0.2 |
| Chapter turn (visited) | 0.3 | 36.9 | 3.1 | 0.2 |
| Size change | 28.5 | 49.5 | 68.8 | 66.9 |

KOReader uses no GPU, but its fresh open differs between the two runs. The
SwiftShader run had no load record for each job, and its host load reached
13.9 by its end. Host load affects every engine. Per-book tables are in
[SwiftShader tables](../../../tool/research/epub_engines/evidence/symmetric-20261111/results-swiftshader/tables.md)
and [host-GPU tables](../../../tool/research/epub_engines/evidence/symmetric-20261111/results-drawn3-gpu/tables.md).

## Homepage organization and checks

The Reader chapter now contains the EPUB implementation, shared controls, and
one benchmark table. PDF reflow has its own chapter and before/after comparison.
The reflow picture follows the site theme: Cream at size 24 or Night at size 28,
both from the same page. Capture provenance remains linked next to the images.
History explains its shared audiobook and ebook actions beside the real capture.

The original hero, Why copy, Shelf, Player, installation instructions, and visual
style remain intact. Detailed benchmark qualifications belong in this note,
with the averaging rule and main limitations beside the homepage table.
[Verification](verification.json) records the numeric, markup, asset, and layout
checks for this revision. No application source or measurement evidence changed.
