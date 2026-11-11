# EPUB engines timed through their drawing: November 11, 2026

This rerun times each EPUB engine from the moment that its own code receives
a request until it has drawn the requested page. The original window-copy
comparison, its raw evidence, and its frozen references remain unchanged.
Results are in the
[README section](../marketing/epub-renderer/README.md#rerun-timed-through-each-engines-drawing).
Ticket `boo-pc6x` and the plan `docs/plans/epub-engine-ready-comparison.md`
record the request and the decisions.

## The rule for the interval

The user asked that work which the emulator makes disproportionately slow
or fast be excluded from every engine in the same way. Software
rasterization on the host CPU is the example. The lead classified each
step and reported the result. KOReader draws its page on the CPU on a
phone too, and pinned crengine decodes images inside that drawing. The
user then decided that every engine's headline interval runs through its
real drawing:

- Bookfin (Flutter) and WebView draw on a real GPU. The headline run uses
  an emulator that renders on the host Mac's GPU, not SwiftShader.
- KOReader draws on the CPU, through `drawCurrentPage`.
- Window copy, PixelCopy, and display scheduling after rasterization stay
  outside every interval. Content checks still run after timing.

The parent and the user then excluded the idle wait for the next frame.
Only frame-based engines have that wait, and it depends on the display
refresh rate. A Pixel 8 at 120 Hz halves it. The drawn page keeps the
frame's own work, and no result column includes the wait. Raw timestamps
stay in the evidence.

The earlier SwiftShader run, which ended before any rasterization, remains
a secondary diagnostic. A host-GPU emulator is not a phone GPU. Its GPU is
an Apple M1 Max, reached through the emulator's OpenGL ES translator, which
sends every guest GPU command to the host.

## Emulator configurations

Both configurations are private AVDs of this ticket on `emulator-5558`.
Each copies the `config.ini` of the original `bookfin-api36` AVD. They run
Android 16 (API 36) and WebView 133.0.6943.137 on four ARM64 virtual CPUs
with 2 GiB RAM. The display has 1080 × 2400 pixels at density 2.625 and
60 Hz. The Pixel 7
cutout overlay (`com.android.internal.emulation.pixel_7`) is on, as on
`bookfin-api36`. Without it the status bar is shorter, the page moves on
the screen, and its pixels differ.

| Configuration | AVD | Guest GL renderer string | Role |
| --- | --- | --- | --- |
| Host GPU | `bookfin-bench-gpu` | `Android Emulator OpenGL ES Translator (Apple M1 Max), OpenGL ES 3.0 (4.1 Metal - 91.7)` | Headline drawn-page run, and a pre-raster run |
| SwiftShader | `bookfin-bench-sym` | `Android Emulator OpenGL ES Translator (ANGLE (Google, Vulkan 1.2.0 (SwiftShader Device (LLVM 10.0.0) …)))` | Pre-raster diagnostic run |

The host-GPU AVD differs only in `hw.gpu.enabled = yes` and
`hw.gpu.mode = host`. The emulator ran with `-gpu auto`, which selected
the host GPU for this AVD and SwiftShader for the other. The Bookfin shell
logs `Using the Impeller rendering backend (OpenGLES).` It loads
`libGLESv2_emulation.so` and no Vulkan driver. WebView composites through
Android's HWUI renderer, `debug.hwui.renderer = skiagl`.

The SwiftShader AVD reproduces all 63 frozen reference pages pixel for
pixel. On the host GPU, 58 of 63 pages are identical. Five differ only in
anti-aliasing or illustration sampling: the two White Rabbit pages, one
Moby-Dick section rule, and two WebView Moby-Dick pages by less than one
pixel value. Their text and locations are the same. The host-GPU run uses
its own reference set, `evidence/symmetric-20261111/references-gpu.json`,
made from separate calibration jobs with the same source, OCR and image
checks. The lead viewed the two changed illustration pages beside the
frozen references. `image-reviews-gpu.json` records that review.

## Where each step runs

| Step | Bookfin | WebView | KOReader | Emulator-skewed | Drawn page | Prepared page (diagnostic) |
| --- | --- | --- | --- | --- | --- | --- |
| Shell to engine hop | none, Dart calls the pager | Java `evaluateJavascript` to JavaScript | Java executor and JNI to Lua | no, shell work | excluded | excluded |
| Parse, style, layout, shaping, pagination | CPU | CPU | CPU | no | included | included |
| Image decode | CPU worker | CPU, `HTMLImageElement.decode()` | CPU, inside `drawCurrentPage` | no | included | included, KOReader only through drawing |
| Upload of decoded images to the GPU | inside Flutter's decode future | at raster time | none | yes | included | Bookfin only |
| Display-list recording | `ui.Picture` | Blink paint | none | no | included | Bookfin only |
| Rasterization | GPU, Impeller OpenGL ES | GPU, Chromium compositor | CPU, `drawCurrentPage` | Bookfin and WebView yes, KOReader no | included | KOReader only |
| Wait for the next frame before the drawing frame | vsync | vsync | none | depends on refresh rate | excluded, measured per sample | not reached |
| Composition, display, window copy | Android | Android | Android `ImageView` | yes | excluded | excluded |

Pinned crengine `b32a88ffbbf505cf2ea5208c1a49002d70d3609f` decodes images
in `LVImageSource::Decode` with a drawing callback
(`crengine/src/lvdrawbuf.cpp:902`). `NodeImageProxy::Decode` opens the
image source again for each drawing (`lvtinydom.cpp`). No cache of decoded
images and no Lua binding separate decoding from drawing.

Flutter 3.47.4 decodes an image on a worker thread. It then uploads it to
a GPU texture and generates mipmaps before the decode future completes
(`ImageDecoderImpeller::UnsafeUploadTextureToPrivate`). With OpenGL ES the
upload waits until its commands are scheduled.

## Interval endpoints

Every interval starts at `engine_start_ns`. At that time, the engine's own
code receives the request. All endpoints are converted to Android
`SystemClock.elapsedRealtimeNanos` nanoseconds.

### Start

```dart
        final startSource = Timeline.now;
        final start = _androidTime(startSource);
```

```js
async function execute(operation, eventId) {
    const engineStart = performance.now();
```

```lua
function perform(operation, event_id)
    local engine_start = clock_ns()
```

where

- `startSource` = Dart's monotonic Timeline clock in microseconds, read
  just before the shell calls the Bookfin pager.
- `_androidTime` = converts Timeline microseconds to Android nanoseconds
  with the offset measured at process start (see Clocks).
- `engineStart` = WebView's `performance.now()` in milliseconds, read when
  the page's JavaScript starts the command.
- `clock_ns` = `clock_gettime(CLOCK_BOOTTIME)` in nanoseconds, which is
  the Android elapsed-realtime clock itself.

The shell dispatch time, `start_ns`, stays in each row. The hop from the
Java shell into WebView or KOReader is outside the engine intervals.

### Shell readiness

Each shell sends its first request only after it reports ready. A GPU
shell reports ready only after it drew its own empty page. Thus the
one-time setup of its first frame stays outside every interval. The
Flutter shell starts its work from a callback after its first frame:

```dart
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_run()));
```

The WebView shell waits until Android reports that it drew the shell
page:

```java
        @JavascriptInterface public void shellReady() {
            runOnUiThread(() -> web.postVisualStateCallback(0, new WebView.VisualStateCallback() {
                @Override public void onComplete(long requestId) {
                    shellDrawn = SystemClock.elapsedRealtimeNanos();
                    BenchmarkActivity.this.ready();
```

where

- `addPostFrameCallback` = runs its function once, after Flutter built and
  painted the shell's first frame.
- `_run` = reads the clocks, reports shell ready, and sends the requests.
- `shellReady` = the call from the shell page's JavaScript after it read
  the book manifest and measured its clock offset.
- `shellDrawn` = the Android time of the shell page's first drawn frame,
  stored as `shell_drawn_ns`.
- `ready` = stores `shell_ready_ns` and sends the first request.

The KOReader shell reports ready after its Lua setup. KOReader draws no
GPU frame inside its interval. The device test fails a WebView job whose
`shell_drawn_ns` is missing or later than `shell_ready_ns`.

### Drawn page (headline)

The drawn page runs from engine entry to the end of preparation, plus the
work of the frame that draws the page. The idle wait between the end of
preparation and the start of that frame is left out. Collection subtracts
it for each sample:

```python
def frame_wait(row):
    """Nanoseconds from the end of preparation until the frame that draws the
    page starts. Zero when that frame began before preparation ended, as a
    Flutter frame can: preparation then ends inside the frame's work."""
    if row["engine"] == "bookfin":
        frame = row["drawn_frame"]["buildStart_us"] * 1000 + row["phase_clock"]["offset_ns"]
    elif row["engine"] == "webview":
        frame = row["frame_start_ns"]
    else:
        return 0
    return max(0, frame - row["preparation_ns"])
```

```python
        idle = frame_wait if end == "drawn_ns" else (lambda row: 0)
        durations = sorted((row[end] - row[start] - idle(row)) / 1000000 for row in samples)
```

where

- `row` = one accepted measured sample.
- `drawn_frame["buildStart_us"]` = Flutter's `FramePhase.buildStart` of the
  frame that first showed the page, in Timeline microseconds.
- `phase_clock["offset_ns"]` = the measured offset from the engine clock to
  Android's clock.
- `frame_start_ns` = the Android time at which the WebView renderer started
  the first frame after preparation.
- `preparation_ns` = the end of preparation, defined below under Prepared
  page.
- `start`, `end` = `engine_start_ns` and `drawn_ns` for this interval.
- `durations` = the drawn-page times in milliseconds.

So the drawn page equals the prepared page plus the frame's work. The
frame's work runs to the drawn endpoint from the later of two moments: the
end of preparation and the frame's start. In 9 of 36 Bookfin fresh opens of
the first run, the frame began up to 14.8 ms before preparation ended. A
sum of the whole frame and the whole preparation counts that overlap
twice. KOReader has no frame clock, so
nothing is subtracted.

#### Bookfin

Bookfin records each frame after its layer tree went to the engine:

```dart
    SchedulerBinding.instance.addPersistentFrameCallback((_) {
      if (mounted) {
        _painted.add((us: Timeline.now, picture: _pager?.shown.value?.picture));
      }
    });
```

```dart
    final painted = _painted[index].us;
    final after = index == 0 ? startSource : _painted[index - 1].us;
    List<ui.FrameTiming> matching() => [
      for (final timing in _timings)
        if (timing.timestampInMicroseconds(ui.FramePhase.buildStart) > after &&
            timing.timestampInMicroseconds(ui.FramePhase.buildStart) <=
                painted &&
            timing.timestampInMicroseconds(ui.FramePhase.buildFinish) <=
                painted)
          timing,
    ];
```

where

- `_painted` = one entry for each frame since the request: the Timeline
  time after the frame was composited, and the page picture that the
  pager showed then.
- `index` = the first frame whose shown picture is the requested page's
  picture, with that page's images decoded.
- `after` = the Timeline time of the frame before it, or the request time.
- `_timings` = Flutter's `FrameTiming` reports since the request.
- `matching()` = the timings of frames that began building after `after`
  and finished building before `painted`. Exactly one must match.

The page's render object reads `pager.shown.value` during each paint. A
change of that value makes the render object ask for a repaint
(`lib/reader/epub/viewport.dart:402`). The callback runs after the
renderer's own frame callback, so the recorded picture is the one that
frame painted. A measured step whose page was already shown before the
request fails.

The frame's work starts at `FramePhase.buildStart`. At that time, the UI
thread begins the frame after its vsync. It ends at `FramePhase.rasterFinish`,
which Flutter records after the frame's layer tree was drawn and submitted
to the surface (`Rasterizer::DoDraw`). The GPU can still be executing
those commands. Collection excludes a Bookfin row with any of these
faults:

- the build start is not after engine entry,
- the build start is after the raster finish,
- the raster finish is not the drawn endpoint.

#### WebView

The page's JavaScript reports preparation, then asks for the next two
animation frames:

```js
function reportFrame(eventId, describe) {
    requestAnimationFrame(vsync => {
        const start = performance.now();
        requestAnimationFrame(nextVsync => {
            setTimeout(() => Probe.frame(JSON.stringify({preparation_event_id:eventId,
                frame_start_source_ms:start, frame_start_ns:androidTime(start),
                frame_vsync_source_ms:vsync, frame_vsync_ns:androidTime(vsync),
                next_frame_vsync_source_ms:nextVsync, next_frame_vsync_ns:androidTime(nextVsync), ...describe()})));
        });
    });
}
```

where

- `vsync` = the frame time that Chromium passes to the callback, the
  vsync time of the frame.
- `start` = the `performance.now()` value at the renderer's first
  animation-frame callback in the first frame after preparation.
- `nextVsync` = the vsync time of the frame after it.
- `androidTime` = converts page milliseconds to Android nanoseconds with
  the offset that the shell measured at start.
- `describe` = reads the page text for the content checks. It runs only
  after both frames, as does the bridge call.

After the shell's Java side receives the preparation report, it requests
the visual-state callback. `Probe.ready` returns only after the UI thread
posted that request:

```java
        @JavascriptInterface public void ready(String raw) throws InterruptedException {
            long ready = SystemClock.elapsedRealtimeNanos();
            CountDownLatch requested = new CountDownLatch(1);
            runOnUiThread(() -> {
...
                requested.countDown();
            });
            if (!requested.await(5, TimeUnit.SECONDS)) BenchmarkActivity.this.failed(new IllegalStateException("The drawn-page callback was not requested"));
```

```java
                    web.postVisualStateCallback(ready, new WebView.VisualStateCallback() {
                        @Override public void onComplete(long requestId) {
                            try {
                                metadata.put("drawn_ns", SystemClock.elapsedRealtimeNanos());
```

where

- `ready` = the Android time at which the JavaScript bridge received the
  preparation report.
- `requested` = released after the UI thread called
  `postVisualStateCallback`.
- `onComplete` = the method that Android calls after the WebView's DOM
  state at the request is ready to draw. `drawn_ns` is read there.

Chromium 133 queues a `QueueReportTimeSwapPromise` for the next main frame
(`WidgetCompositor::CreateQueueSwapPromise`). In Android WebView's
synchronous compositing mode, the answer comes at the activation of that
frame's layer tree (`QueueReportTimeSwapPromise::DidActivate`). A tree
activates once the tiles that it needs on screen are rasterized. WebView
draws inside Android's own frame. If the page's frame commits too late for
Android's draw at its vsync, the page is drawn and answered after the next
vsync. The time also includes the answer's trip to Android's UI thread.

Collection excludes a WebView row with any of these faults:

- the frame start is missing,
- the frame start is before preparation or not before the drawn endpoint,
- its conversion does not reproduce the stored nanoseconds.

#### KOReader

KOReader's drawn page is its prepared page:

```lua
    local operation_returned = clock_ns()
    document:drawCurrentPage(shown.buffer, true, false, true, false)
    local preparation = clock_ns()
```

where

- `operation_returned` = after navigation, `renderDocument()` and
  `getCurrentPage()`, before drawing.
- `shown.buffer` = an RGBA page buffer allocated once at shell start.
- `preparation` = after crengine laid out the page's text, decoded its
  images and drew every pixel on the CPU. `drawn_ns` equals this time.

### Prepared page (diagnostic)

The prepared page ends before any GPU rasterization:

- Bookfin: `PageSource.picture(page, scale: devicePixelRatio)` returned a
  recorded `ui.Picture` with the page's images decoded.
- WebView: the epub.js operation resolved, `document.fonts.ready`
  resolved, `decode()` resolved for every image that overlaps the 360 × 640
  reader, the views expanded, `rendition.currentLocation()` ran, and
  `getBoundingClientRect()` forced layout.
- KOReader: `drawCurrentPage` returned, as above. KOReader's interval
  before drawing ends at `operation_returned`.

## Asymmetries that remain

1. Bookfin and WebView ignore the wait for the next frame only before
   their drawing frame. Waits that an engine schedules inside its own
   preparation stay. epub.js runs its work queue on animation frames
   (`src/utils/queue.js`). Bookfin runs pagination steps that are not
   urgent between frames (`PageSource.scheduleBetweenFrames`). These waits
   depend on the display refresh rate.
2. WebView reaches the screen through Android's frame. When the page's
   frame commits too late for Android's draw at its vsync, Android answers
   after the next vsync. In the headline run, 127 of 468
   accepted WebView samples were answered after a vsync that followed the
   start of the page's frame. Those values keep part of that wait. Chromium
   gives the page no signal for the end of its frame's raster, so the wait
   cannot be measured apart from the work.
3. The frames start at nearly the same point. Flutter's build start is the
   UI thread's start of the frame. WebView's start is its first
   animation-frame callback, after the main thread handled any input.
4. The endpoints differ. Bookfin ends at the submission of its GPU
   commands. WebView ends after the page's tiles were rasterized, plus the
   trip of the answer to Android's UI thread. KOReader ends after its last
   pixel is on the CPU.
5. A host GPU is not a phone GPU. The M1 Max is faster than a phone GPU,
   but each command crosses the emulator's translator to the host.
6. Whole-book work still differs, as in the original comparison. KOReader
   paginates the whole book on open and size change. Bookfin finishes its
   page map in the background. WebView lays out one chapter.
7. Page boundaries and illustration sizes differ between engines. Only one
   timed page has an image in Bookfin and WebView, `turn2` of Alice.

## Drawing facts from the headline run

These facts come from the accepted samples of `sym-drawn3`. They describe
the drawn page and are not result columns.

| Fact | Bookfin | WebView | KOReader |
| --- | --- | --- | --- |
| Median frame wait left out, per book (prose, long, illustrated) | 13.2, 10.5, 12.5 ms | 13.7, 10.6, 7.2 ms | none |
| Frame work after the later of preparation and frame start, median / p90 | 3.6 / 12.4 ms | on time: 0.8 / 2.7 ms. After a later vsync: 13.9 / 18.5 ms | none, drawing is in preparation |
| Frames that began before preparation ended | 14 of 468 | 0, a frame cannot start while the page's JavaScript runs | none |
| Median GPU raster (`rasterFinish` minus `rasterStart`), per book | 2.6, 2.8, 2.2 ms | not exposed | none |
| Median CPU drawing (`drawCurrentPage`), per book | none | none | 1.8, 2.0, 2.1 ms |

WebView answers after a later vsync, by action:

- fresh open: 26 of 36,
- cached reopen: 50 of 108,
- page turn: 29 of 108,
- chapter turn: 22 of 108,
- size change: 0 of 108.

`results-drawn3-gpu/facts.json` holds the facts per book,
and `results-drawn3-gpu/webview-late-answers.txt` holds the answers by
action.

## Clocks

| Engine | Event clock | Conversion to Android nanoseconds |
| --- | --- | --- |
| Bookfin | Dart `Timeline.now` and `FrameTiming`, integer microseconds, both monotonic | Nine platform-clock round trips at process start. The shortest sets the offset, native time minus the local midpoint. The uncertainty is half that round trip plus 1 µs. Each sample checks that its frame timing lies between two of its own Timeline readings |
| WebView | `performance.now()`, milliseconds | The same nine round trips through a synchronous Java bridge. The uncertainty adds the observed timer step, 100 µs. The drawn endpoint is read on Java's own clock |
| KOReader | `CLOCK_BOOTTIME`, nanoseconds | None, it is Android's elapsed-realtime clock |

Each subtracted frame wait is the difference of two readings on one engine
clock: Timeline microseconds for Bookfin and page milliseconds for WebView.
The conversion offset cancels in that difference. For WebView, only the
100 µs timer step remains.

The median WebView hop from Java dispatch to the JavaScript start is about
0.9 ms. Its smallest value, 0.29 ms, is larger than the conversion
uncertainty, 0.25 ms.

## Content checks and sample selection

Content checks are unchanged from the original method. Each timed capture
must match the pixels of an independent calibration page for its engine,
book, case and configuration. Host collection then compares its location,
visible text, text size, book digest and reference provenance. Rows that
fail any check, preparation rows, and warmups never enter a cell. Each
interval also rejects a row with any of these faults:

- a stale event identity or a wrong scope,
- a missing endpoint or endpoints out of order,
- a clock conversion that does not reproduce the stored nanoseconds.

Delaying the window copy changes only
the copy endpoint, never an engine interval. The tests in
`test_preparation.py` cover these rules.

## Runs

Each run uses the original balanced schedule: 12 rounds and 108 fresh
process jobs, one engine at a time. Each job has one fresh open and three
of each warm action. No build or other heavy command of this ticket ran
during a timed schedule. Other agents shared the host.

For the headline run, `run.py` measures each job only while the host is
quiet:

1. Before a job starts, it waits until the one-minute host load is under 8.
2. During the job, it reads the one-minute load every second.
3. If any reading is 8 or more, it moves the job's evidence to
   `rejected-load/` and measures the job again at the same place in the
   schedule.

`host-load.jsonl` records every attempt. Collection marks a job without an
accepted attempt as incomplete. The one-minute load is an average, so it
reacts to a short spike with a delay. The earlier runs had no record per
job.

| Run | Configuration | Run prefix | Evidence | Jobs passed | Measured samples accepted | Host load |
| --- | --- | --- | --- | ---: | ---: | --- |
| Drawn page (headline) | Host GPU | `sym-drawn3` | `measured-drawn3-gpu`, `results-drawn3-gpu` | 108 | 1,404 | every job under 8, highest reading 7.3, no job measured again |
| Drawn page, stopped | Host GPU | `sym-drawn2` | `measured-drawn2-gpu` | 20 of 108 | not collected | 4.4 at start, then about 30 from another agent's test run |
| Drawn page, superseded | Host GPU | `sym-drawn` | `measured-drawn-gpu`, `results-drawn-gpu` | 108 | 1,404 | 4.3 before, 5.8 after |
| Prepared page | Host GPU | `sym-gpu` | `measured-gpu`, `results-gpu-prepared` | 108 | 1,404 | 5.4 before, 10.6 after |
| Prepared page | SwiftShader | `sym-sw` | `measured-swiftshader`, `results-swiftshader` | 108 | 1,404 | 7.2 before, 13.9 after |

The `sym-drawn2` run used the same shells as the headline run. At about
12:15 local time, another agent started a full `flutter test` run, and the
one-minute load reached about 30 on 10 cores by 12:20. The run had no
record per job, so the lead stopped it after 20 jobs and did not use it.
The two prepared-page runs ended with loads above 8. They are diagnostics
only.

Evidence paths are under `tool/research/epub_engines/evidence/symmetric-20261111/`.
Round-zero PNG copies whose pixels equal a committed reference PNG were
removed after collection. `png-duplicates-removed.tsv` lists each one with
its file hash, pixel hash and reference.

The commands, from the repository root inside `nix develop`:

```sh
python3 tool/research/epub_engines/run.py --prefix sym-drawn3 --serial emulator-5558 --output tool/research/epub_engines/evidence/symmetric-20261111/measured-drawn3-gpu
python3 tool/research/epub_engines/collect.py tool/research/epub_engines/evidence/symmetric-20261111/measured-drawn3-gpu tool/research/epub_engines/evidence/symmetric-20261111/references-gpu.json --output tool/research/epub_engines/evidence/symmetric-20261111/results-drawn3-gpu
python3 tool/research/epub_engines/tables.py tool/research/epub_engines/evidence/symmetric-20261111/results-drawn3-gpu/summary.json drawn prepared
```

`collect.py` keeps each cell in integer nanoseconds and exact fractions
until the last step. A median halfway between two tenths of a millisecond
thus rounds up, as the rounding rule states. `exact-rounding-check.py`
recomputes all 1,050 published rounded values of the four result folders
from the accepted samples, apart from `results.py`. It found no mismatch.
Before this fix, three per-book medians of the WebView prepared page were
0.1 ms too low in the diagnostic tables. No headline value changed.

`png-dedup-1.py` and `png-dedup-2.py` removed the PNG copies listed in
`png-duplicates-removed.tsv`. Collection gave the same samples before and
after each removal.

`run.py` runs from `tool/research/epub_engines` with relative output paths.
`collect.py` writes `summary.json`, `facts.json` and the certified
`samples.jsonl`. The summary keeps each interval's cells, exclusions and
equal-book means separately.

## The superseded first drawn-page run

The first drawn-page run, `sym-drawn`, passed every check. But its WebView
shell reported ready from JavaScript, before the WebView drew any frame.
The WebView's first-frame setup thus fell inside its fresh open. The
Flutter shell already did that setup before its interval.

The evidence is the time from preparation to the drawn page. For WebView
fresh opens, its median was 233 ms, against 12 to 17 ms for the other
WebView actions. For the prose and long books, the drawn page came about
500 ms after engine start, whatever the preparation time. The illustrated
book prepares for longer than that, and its drawn page followed within
about 13 ms.

The lead then made the WebView shell draw its page before it reports
ready, as described under Shell readiness. One measured WebView job per
book (`experiment-shell-drawn`) gave 17.9, 23.0 and 18.5 ms from
preparation to the drawn page on fresh open. The host load was high
during that check, about 22 to 32.

The `sym-drawn` interval also included the wait for the next frame. The
parent and the user then excluded that wait, as described under Drawn
page. `sym-drawn` rows have no WebView frame start, so the current
collection of `results-drawn-gpu` excludes its WebView rows from the drawn
page. Its Bookfin and KOReader cells use the current interval. The
headline run `sym-drawn3` repeats the full schedule with both shell
changes. The raw `sym-drawn` evidence stays unchanged.

Three short WebView checks guided the second change. Each ran one measured
job per book and passed the device test.

| Check | Shell | What it showed |
| --- | --- | --- |
| `experiment-frame-wait` | Frame start reported, page text read before the visual-state request | In 9 of 39 samples, Android answered 10 ms or more after the page's frame started |
| `experiment-webview-answer` | Visual-state request before JavaScript yields, page text read after the frames | 8 of 39 such samples remained |
| `experiment-webview-vsync` | Vsync times added | 5 of 39 answers came after a later vsync. In 4 of them, the page's frame started 6.7 ms or more after its vsync |

## Bugs found in the earlier partial work

- The KOReader shell passed the event identity through `JSONObject.quote`,
  which writes `\/`. Lua rejects that escape, so every KOReader job of
  that version failed (`red-device-koreader-lua-quoting.txt`).
- An early version of this ticket's repeat-draw buffer was not referenced
  from Lua after setup. The garbage collector freed it, and KOReader
  crashed (`device-koreader-freed-buffer-crash.txt`).
