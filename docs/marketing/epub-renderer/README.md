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
KOReader draws on the CPU, as it does on a phone.

A vsync is the display's signal to start the next frame. The interval
leaves out only the idle wait from the end of preparation until the vsync
of the frame that draws the page. Collection measures that wait for each
sample. Only
frame-based engines have that wait, and it depends on the display refresh
rate. Anything after that vsync stays in. If preparation ends inside a
running frame, that frame draws the page, and nothing is left out.

The emulator for this run rendered on the host Mac's GPU, an Apple M1 Max,
through the emulator's OpenGL ES translator. A host-GPU emulator is not a
phone GPU. The [method](../../research/epub-engine-drawn-page-method.md)
gives the details and the evidence.

### Drawn page on the host GPU

Each cell is the equal-book-weight mean in milliseconds, with the rule
above. Each engine has 12 fresh opens and 36 samples of each other action
per book, from 108 fresh process jobs of run `sym-drawn4`.

| Action | Bookfin | WebView | KOReader |
| --- | ---: | ---: | ---: |
| Fresh open | 370.3 | 359.7 | 117.9 |
| Cached reopen | 46.9 | 284.9 | 17.1 |
| Page turn | 7.8 | 51.9 | 2.3 |
| Chapter turn (visited) | 4.5 | 47.1 | 3.0 |
| Size change | 40.6 | 64.7 | 68.9 |

Per book, each cell shows median / p90 (sample count) in milliseconds. The
p90 is the sample at rank ⌈0.9 n⌉ in ascending order.

| Interval | Action | prose | long | illustrated |
| --- | --- | ---: | ---: | ---: |
| Bookfin | Fresh open | 214.2 / 242.5 (12) | 300.1 / 315.4 (12) | 588.8 / 606.3 (12) |
| Bookfin | Cached reopen | 36.6 / 41.1 (36) | 42.2 / 55.0 (36) | 58.0 / 65.9 (36) |
| Bookfin | Page turn | 6.3 / 8.2 (36) | 6.6 / 8.9 (36) | 7.6 / 18.8 (36) |
| Bookfin | Chapter turn (visited) | 4.2 / 7.2 (36) | 4.0 / 5.9 (36) | 3.8 / 5.7 (36) |
| Bookfin | Size change | 37.3 / 49.7 (36) | 47.3 / 60.7 (36) | 25.0 / 52.1 (36) |
| WebView | Fresh open | 186.6 / 204.9 (12) | 233.5 / 266.2 (12) | 614.5 / 681.2 (12) |
| WebView | Cached reopen | 121.2 / 154.5 (36) | 175.9 / 236.9 (36) | 530.7 / 576.1 (36) |
| WebView | Page turn | 52.0 / 66.5 (36) | 49.2 / 55.3 (36) | 52.5 / 67.2 (36) |
| WebView | Chapter turn (visited) | 43.7 / 54.4 (36) | 41.3 / 57.5 (36) | 49.6 / 63.6 (36) |
| WebView | Size change | 66.7 / 69.4 (36) | 66.6 / 69.7 (36) | 65.5 / 68.5 (36) |
| KOReader | Fresh open | 102.5 / 111.8 (12) | 177.6 / 189.2 (12) | 75.3 / 84.8 (12) |
| KOReader | Cached reopen | 13.8 / 15.5 (36) | 15.8 / 17.6 (36) | 21.6 / 23.7 (36) |
| KOReader | Page turn | 2.0 / 2.5 (36) | 1.9 / 2.2 (36) | 2.2 / 4.2 (36) |
| KOReader | Chapter turn (visited) | 1.7 / 2.1 (36) | 1.7 / 2.1 (36) | 5.3 / 6.1 (36) |
| KOReader | Size change | 65.8 / 68.1 (36) | 115.2 / 118.2 (36) | 24.5 / 28.0 (36) |

Data: [summary JSON](../../../tool/research/epub_engines/evidence/symmetric-20261111/results-drawn4-gpu/summary.json)
and [accepted samples](../../../tool/research/epub_engines/evidence/symmetric-20261111/results-drawn4-gpu/samples.jsonl).

Each job ran only while the host was quiet. Before each job started, the
one-minute host load had to be under 8 on the Mac's 10 cores. During the
job, the runner read the load every second. A job with any reading of 8 or
more is set aside and measured again at the same place in the schedule.
Four jobs of this run were measured again for that reason
([load record](../../../tool/research/epub_engines/evidence/symmetric-20261111/measured-drawn4-gpu/host-load.jsonl)):

| Job | Highest load of each set-aside attempt |
| --- | --- |
| Round 4, illustrated book, Bookfin | 8.46 |
| Round 9, prose book, Bookfin | 11.79, then 8.14 |
| Round 9, illustrated book, WebView | 9.83 |
| Round 10, illustrated book, WebView | 8.06 |

Every accepted job stayed under 8. The highest reading was 7.86. One more
job, round 1 of the prose book in WebView, was measured again for another
reason. A device check required that WebView's end of preparation come
before the Java bridge call, on two different clocks, with no tolerance.
It failed by 0.018 ms, while that job's clock conversion was uncertain by
0.301 ms. The check now allows the conversion uncertainty. The engine
builds stayed the same, and only the test packages were reinstalled.

The whole balanced schedule of 108 jobs ran again because the shells
changed. The WebView shell now records the animation frame that runs at
the end of preparation. The previous run, `sym-drawn3`, did not. Its rule thus
removed that frame's own work from most WebView page turns and size
changes, and it is superseded. An earlier attempt, `sym-drawn2`, ran while
another agent's test run raised the host load to about 30. It stopped
after 20 jobs and is not used.

### Endpoints

| Engine | Start | End | Left out |
| --- | --- | --- | --- |
| Bookfin | Dart reads its clock, then calls the production pager | Flutter's `rasterFinish` of the first frame that shows the page with its images decoded | From the end of preparation to that frame's vsync (`vsyncStart`) |
| WebView | The page's JavaScript starts the epub.js command | Android's visual-state callback: the page's state at the request, after fonts, layout, and page images are ready, is ready to be drawn | From the end of preparation to the vsync of the frame that draws the page. If preparation ended inside a running animation frame, nothing |
| KOReader | Lua starts the command | `drawCurrentPage` returns with every pixel drawn on the CPU | Nothing, KOReader has no frame clock |

If the drawing frame's vsync came before preparation ended, nothing is
left out. The interval also excludes the hop from the Java shell into each
engine, composition, display, and the window copy. Content checks run
after timing, and only rows that pass them enter a cell.

### Remaining asymmetries

1. Waits that an engine schedules inside its own preparation stay. epub.js
   runs its work queue on animation frames. Inside WebView's preparation,
   the median number of frames is 6 for a fresh open and 5 for a cached
   reopen. It is 2 for a page or chapter turn and 3 for a size change. For
   Bookfin, the medians are 3, 1, 0, 0 and 1. These waits depend on the
   display refresh rate.
2. WebView draws inside Android's frame. In 373 of 468 WebView samples,
   Android answered after a vsync that followed the start of the drawing
   frame. These include all 284 samples whose preparation ended inside a
   running animation frame: Chromium handles the request after that frame,
   so the answer comes with the next frame. These samples keep the idle
   time from the end of the drawing frame's work to that later vsync.
   Chromium gives the page no time for the end of a frame's work. The time
   from the end of preparation to the later vsync is an upper bound of that
   idle time: median 11.9 ms, p90 14.8 ms. It also holds the rest of the
   frame's work.
3. The endpoints differ. Bookfin ends at the submission of its GPU
   commands. WebView ends at Android's report that the page is ready to be
   drawn, after its tiles were rasterized. That end includes the answer's
   trip to Android's UI thread. KOReader ends after its last pixel is on the CPU.
4. The WebView frame watcher sees only frames that ran an animation-frame
   callback. All 82 WebView samples that leave out a wait ended their
   preparation 9.6 ms or more after the previous vsync. The samples that
   ended inside a running frame did so a median 5.2 ms after its vsync.
5. KOReader paginates the whole book on open and size change. Bookfin
   completes its page map in the background. WebView lays out one chapter.
6. Page boundaries and illustration sizes differ between engines.

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

Host GPU, the headline run `sym-drawn4`:

| Action | Bookfin | WebView | KOReader | KOReader before drawing |
| --- | ---: | ---: | ---: | ---: |
| Fresh open | 347.0 | 344.8 | 117.9 | 115.7 |
| Cached reopen | 41.0 | 270.1 | 17.1 | 14.3 |
| Page turn | 2.2 | 33.3 | 2.3 | 0.2 |
| Chapter turn (visited) | 0.3 | 35.5 | 3.0 | 0.2 |
| Size change | 30.3 | 50.0 | 68.9 | 66.9 |

KOReader uses no GPU, but its fresh open differs between the two runs. The
SwiftShader run had no load record for each job, and its host load reached
13.9 by its end. Host load affects every engine. Per-book tables are in
[SwiftShader tables](../../../tool/research/epub_engines/evidence/symmetric-20261111/results-swiftshader/tables.md)
and [host-GPU tables](../../../tool/research/epub_engines/evidence/symmetric-20261111/results-drawn4-gpu/tables.md).

## Rerun on current main: November 12, 2026

This run repeats `sym-drawn4` with Bookfin's shell built from main at
`255da777`. Since `sym-drawn4`, main gained four changes to the open:

- the open quick wins (`boo-yjq6`),
- admission and MOBI conversion when a download completes, and a kept
  last page that a reopen draws in its first frame (`boo-sy2d`),
- the reader font for all text (`boo-iv7q`),
- a book's own font only for characters that the reader font lacks
  (`boo-3huo`).

The run id is `rerun1`. Ticket `t1-m4cp` records the work. The books,
the actions, the endpoints, the rule for the frame wait, the load guard
and the equal-book-weight means are those of `sym-drawn4`. The WebView
and KOReader rows keep their definitions. Their release and test
packages are the same files, byte for byte, as in `sym-drawn4`.

### Summary

Each cell is the equal-book-weight mean in milliseconds. "n/a" marks a
row that the engine does not have.

| Action | Bookfin | WebView | KOReader |
| --- | ---: | ---: | ---: |
| Fresh open, no preparation | 195.5 | 355.3 | 127.9 |
| Fresh open, prepared at download | 65.4 | n/a | n/a |
| Preparation at download (background) | 150.0 | n/a | n/a |
| Cached reopen, kept page | 9.6 | n/a | n/a |
| Cached reopen, true page | 31.2 | 289.0 | 17.4 |
| Page turn | 8.2 | 52.5 | 2.6 |
| Chapter turn (visited) | 4.2 | 47.8 | 3.1 |
| Size change | 35.6 | 64.8 | 70.0 |

The rows of Bookfin mean this:

- Fresh open, no preparation: the cold path of `sym-drawn4`. Nothing
  about the book is kept, so the open admits the whole book.
- Fresh open, prepared at download: the first open after a download, as
  the app now does it. The admitted book is kept, but no page map and no
  kept page exist yet.
- Preparation at download: the time from the call of
  `prepareDownloadedBook` to its return. The app runs it in a worker when
  a download completes. It is not on the path of any open.
- Cached reopen, kept page: the time to the first frame that draws the
  kept page. This is the page that the person sees first.
- Cached reopen, true page: the time to the first frame that draws the
  laid-out page, as in `sym-drawn4`. In every reopen of this run, the
  kept page and the true page were the same page (`KeptPage.depicts`).

Compared with `sym-drawn4`:

| Action | Bookfin before | Bookfin now | WebView before | WebView now | KOReader before | KOReader now |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Fresh open, no preparation | 370.3 | 195.5 | 359.7 | 355.3 | 117.9 | 127.9 |
| Fresh open, prepared at download | n/a | 65.4 | n/a | n/a | n/a | n/a |
| Cached reopen, first drawn page | 46.9 | 9.6 (kept page) | 284.9 | 289.0 | 17.1 | 17.4 |
| Cached reopen, true page | 46.9 | 31.2 | 284.9 | 289.0 | 17.1 | 17.4 |
| Page turn | 7.8 | 8.2 | 51.9 | 52.5 | 2.3 | 2.6 |
| Chapter turn (visited) | 4.5 | 4.2 | 47.1 | 47.8 | 3.0 | 3.1 |
| Size change | 40.6 | 35.6 | 64.7 | 64.8 | 68.9 | 70.0 |

WebView and KOReader did not change. Their differences show the noise
between two runs on a shared host: 0.1 to 10.0 ms.

### Per book

Each cell shows median / p90 (sample count) in milliseconds. The p90 is
the sample at rank ⌈0.9 n⌉ in ascending order.

| Engine | Action | prose | long | illustrated |
| --- | --- | ---: | ---: | ---: |
| Bookfin | Fresh open, no preparation | 153.4 / 192.5 (12) | 202.9 / 241.7 (12) | 198.2 / 257.6 (12) |
| Bookfin | Fresh open, prepared at download | 64.2 / 80.9 (12) | 62.3 / 82.9 (12) | 52.3 / 83.8 (12) |
| Bookfin | Preparation at download (background) | 107.3 / 171.5 (12) | 152.0 / 161.6 (12) | 156.9 / 184.6 (12) |
| Bookfin | Cached reopen, kept page | 9.2 / 11.5 (36) | 9.7 / 12.5 (36) | 7.9 / 10.3 (36) |
| Bookfin | Cached reopen, true page | 26.6 / 32.8 (36) | 34.2 / 40.8 (36) | 26.5 / 31.4 (36) |
| Bookfin | Page turn | 6.0 / 8.8 (36) | 6.8 / 8.6 (36) | 8.5 / 20.5 (36) |
| Bookfin | Chapter turn (visited) | 4.1 / 6.0 (36) | 4.0 / 5.2 (36) | 4.0 / 5.8 (36) |
| Bookfin | Size change | 24.6 / 45.5 (36) | 43.2 / 54.3 (36) | 24.4 / 42.4 (36) |
| WebView | Fresh open | 183.2 / 229.9 (12) | 256.6 / 266.3 (12) | 621.5 / 648.1 (12) |
| WebView | Cached reopen | 120.9 / 153.5 (36) | 183.6 / 217.0 (36) | 545.6 / 599.7 (36) |
| WebView | Page turn | 52.9 / 67.1 (36) | 49.0 / 54.6 (36) | 52.0 / 67.0 (36) |
| WebView | Chapter turn (visited) | 43.7 / 54.0 (36) | 43.9 / 66.5 (36) | 49.1 / 62.6 (36) |
| WebView | Size change | 66.8 / 71.7 (36) | 63.7 / 69.1 (36) | 66.2 / 69.8 (36) |
| KOReader | Fresh open | 110.0 / 152.5 (12) | 178.0 / 199.4 (12) | 71.4 / 77.6 (12) |
| KOReader | Cached reopen | 12.9 / 14.5 (36) | 15.5 / 17.4 (36) | 21.1 / 27.6 (36) |
| KOReader | Page turn | 2.0 / 2.3 (36) | 1.9 / 2.7 (36) | 2.5 / 4.5 (36) |
| KOReader | Chapter turn (visited) | 1.8 / 2.1 (36) | 1.7 / 2.0 (36) | 5.2 / 6.0 (36) |
| KOReader | Size change | 67.5 / 69.9 (36) | 116.5 / 120.8 (36) | 24.8 / 27.7 (36) |

Every cell has the sample count of `sym-drawn4`: 12 fresh opens and 36
of each other action per book and engine. The run has 144 accepted jobs
and 1,440 accepted samples. No measured sample was excluded. Data:
[summary JSON](../../../tool/research/epub_engines/evidence/rerun-20261112/results-rerun1/summary.json),
[accepted samples](../../../tool/research/epub_engines/evidence/rerun-20261112/results-rerun1/samples.jsonl),
[facts](../../../tool/research/epub_engines/evidence/rerun-20261112/results-rerun1/facts.json)
and [tables](../../../tool/research/epub_engines/evidence/rerun-20261112/results-rerun1/tables.md).

### What changed in the method

1. The Bookfin shell opens a book as the reading session on main does.
   The pager starts with this phone's last page settings (`expected`), as
   the app's pager does after the phone showed one page. In all 180 opens,
   these settings equaled the settings that the viewport presented.
2. A cached reopen first closes the open book, so the viewport shows the
   paper. It then reads the page kept at the saved place beside the load.
   The viewport draws the kept page until the pager shows its first page.
   The kept page is written in the unmeasured step after the fresh open,
   when an open at the saved place shows that page (`opensAtShown`). All
   36 processes per book kept their page, and all 108 reopens drew it.
3. Each round and book has a fourth process: Bookfin with its book
   prepared at download. It calls `prepareDownloadedBook`, rests 500 ms,
   and runs only the fresh open. That process takes each of the four
   places in a book's group three times. The three standard processes
   keep the ids and order of `sym-drawn4`. This adds 36 jobs, for 144.
4. The kept page has the same rule for the frame wait as the drawn page.
   Its interval runs from engine entry to Flutter's `rasterFinish` of the
   first frame that drew the kept page. It leaves out the time from the
   hand-over of the kept page to the viewport until that frame's vsync.
5. The emulator is a new private AVD, `bookfin-bench-rerun`, on
   `emulator-5562`. Its `config.ini` copies `bookfin-bench-gpu`, with the
   same system image, WebView 133.0.6943.137, host GPU renderer string and
   Pixel 7 cutout overlay. Bookfin's pages matched the `sym-drawn4`
   references pixel for pixel, so no new calibration ran.

The host tests in `test_rerun.py` and `test_protocol.py` cover the new
rows. Collection of the `sym-drawn4` samples with the changed code gives
every one of its cells and means again.

### Host load

Each job used the load guard of `sym-drawn4`. The run went from 14:13 to
15:31 UTC. Before each accepted job, the one-minute load was 5.0 to 7.99
on the Mac's 10 cores. The highest reading during an accepted job was
7.99. Eighteen jobs were set aside, after 22 attempts with a reading of 8
or more, and measured again at the same place
([load record](../../../tool/research/epub_engines/evidence/rerun-20261112/measured-rerun1/host-load.jsonl)).
One job, round 7 of the illustrated book in Bookfin, was busy in three
attempts, so the runner stopped. The run went on from that job with
`--start 88`.

### Asymmetries that changed

1. Only Bookfin has a kept page and a preparation at download. A WebView
   or KOReader reopen draws its true page first. KOReader keeps its
   parsed book and its layout in a cache file, which its reopen uses.
2. The prepared open follows the preparation in the same process, after
   500 ms. Its file cache is warm, and its worker code already ran. In
   the app, the open can come in a later process.
3. The preparation at download ran on a quiet emulator. In the app, it
   runs beside the download and other work.
4. Bookfin's cached reopen, true page, is the app's new path: it reads and
   draws the kept page inside the interval. In `sym-drawn4`, the old page
   stayed on screen until the new pager existed. The endpoint is the
   same.
5. WebView's answer after a later vsync: 385 of 468 samples, against 373
   in `sym-drawn4`. Its preparation ended inside a running frame in 285
   samples, against 284. Bookfin's median number of frames inside
   preparation is now 2 for a fresh open, against 3, and is unchanged
   for the other actions.

The other asymmetries of `sym-drawn4` remain as listed there.

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
