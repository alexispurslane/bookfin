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
refresh rate. A Pixel 8 at 120 Hz halves it. The rule, for Bookfin and
WebView alike:

- The drawn page leaves out the time from the end of preparation until the
  vsync of the frame that draws the page. Only that wait is display
  cadence.
- Anything after that vsync stays in. A frame that starts late after its
  vsync keeps that delay, because it is engine or thread time.
- If preparation ends inside a running frame, that frame draws the page,
  and nothing is left out.

The drawn page thus keeps all of the drawing frame's own work. No result
column includes the wait. Raw timestamps stay in the evidence.

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
| Wait from the end of preparation to the drawing frame's vsync | vsync | vsync | none | depends on refresh rate | excluded, measured per sample | not reached |
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

The drawn page runs from engine entry to the drawn endpoint. Collection
subtracts, for each sample, the idle wait from the end of preparation
until the vsync of the frame that draws the page:

```python
def drawing_frame(row):
    """The vsync time and the start of the frame that draws the page, in
    Android nanoseconds, or None for KOReader, which draws without frames.
    Bookfin's is the first frame that showed the page. WebView's is the
    animation frame that was running when preparation ended, if one was;
    otherwise the first frame after preparation."""
    if row["engine"] == "bookfin":
        frame, offset = row["drawn_frame"], row["phase_clock"]["offset_ns"]
        return frame["vsyncStart_us"] * 1000 + offset, frame["buildStart_us"] * 1000 + offset
    if row["engine"] == "webview":
        if row.get("running_frame_vsync_ns") is not None:
            return row["running_frame_vsync_ns"], row["running_frame_start_ns"]
        return row["frame_vsync_ns"], row["frame_start_ns"]
    return None


def frame_wait(row):
    ...
    frame = drawing_frame(row)
    return 0 if frame is None else max(0, frame[0] - row["preparation_ns"])
```

```python
    "drawn_page": {"start": "engine_start_ns", "end": "drawn_ns", "engines": ENGINES, "scopes": DRAWN_SCOPES,
                   "less": frame_wait, "check": _invalid_drawing,
                   "boundary": "engine_start_ns_to_drawn_ns_less_wait_until_drawing_frame_vsync"},
```

```python
        durations = sorted(row[end] - row[start] - less(row) for row in samples)
```

where

- `row` = one accepted measured sample.
- `drawn_frame["vsyncStart_us"]` = Flutter's `FramePhase.vsyncStart` of the
  frame that first showed the page: "The timestamp of the vsync signal
  given by the operating system", in Timeline microseconds.
- `drawn_frame["buildStart_us"]` = Flutter's `FramePhase.buildStart` of
  that frame, the time at which the UI thread starts to build it.
- `phase_clock["offset_ns"]` = the measured offset from the engine clock to
  Android's clock.
- `running_frame_vsync_ns`, `running_frame_start_ns` = the vsync time and
  the first callback time of the WebView animation frame that was running
  when preparation ended. If preparation ended between frames, both are
  null.
- `frame_vsync_ns`, `frame_start_ns` = the vsync time and the first
  callback time of the first WebView animation frame after preparation.
- `preparation_ns` = the end of preparation, defined below under Prepared
  page.
- `frame[0]` = the vsync time of the frame that draws the page.
- `less` = the function that the interval declares to subtract, here
  `frame_wait`. The other intervals subtract nothing.
- `start`, `end` = `engine_start_ns` and `drawn_ns` for this interval.
- `durations` = the drawn-page times in integer nanoseconds.

If the drawing frame's vsync came before the end of preparation, nothing is
subtracted. A Flutter frame can begin before preparation ends, and a WebView
preparation can end inside an animation frame. KOReader has no frame
clock, so nothing is subtracted. The time from the vsync to the frame's
start stays in: it is the time that the engine's thread needed to begin
the frame. The test `test_a_frame_that_starts_late_after_its_vsync_keeps_that_delay`
holds this rule for both engines.

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

The subtraction ends at the frame's `FramePhase.vsyncStart`. The UI
thread begins to build the frame at `FramePhase.buildStart`, at or after
that vsync. The drawn page ends at `FramePhase.rasterFinish`, which
Flutter records after the frame's layer tree was drawn and submitted to
the surface (`Rasterizer::DoDraw`). The GPU can still be executing those
commands. Collection excludes a Bookfin row with any of these faults:

- the vsync or the build start is missing,
- the vsync is after the build start,
- the build start is not after engine entry,
- the build start is after the raster finish,
- the raster finish is not the drawn endpoint.

The shell also counts the frames that painted inside preparation:

```dart
        final preparationSource = Timeline.now;
        // The frames that painted since the request ran inside preparation.
        final framesInPreparation = _painted.length;
```

where

- `preparationSource` = the end of preparation, in Timeline microseconds.
- `framesInPreparation` = the number of frames that painted between the
  request and the end of preparation, stored as `frames_in_preparation`.

#### WebView

Before epub.js loads, the shell page wraps `requestAnimationFrame`. At
load, epub.js keeps its own reference to that function
(`this.tick=n.requestAnimationFrame` in `epub.min.js`), so the wrapper must
come first:

```js
const frameWatch = {running: null, count: 0};
(() => {
    const request = window.requestAnimationFrame.bind(window);
    window.requestAnimationFrame = callback => request(vsync => {
        if (!frameWatch.running || frameWatch.running.vsync !== vsync) {
            const frame = {vsync, start: performance.now()};
            frameWatch.running = frame;
            frameWatch.count++;
            setTimeout(() => { if (frameWatch.running === frame) frameWatch.running = null; });
        }
        callback(vsync);
    });
})();
```

```js
    const preparation = performance.now();
    const running = runningFrame();
```

where

- `request` = the browser's own `requestAnimationFrame`.
- `vsync` = the frame time that Chromium passes to each callback of a
  frame, the vsync time of the frame. All callbacks of one frame get the
  same value, so a new value starts a new frame.
- `frameWatch.running` = the frame whose callbacks run now, with its vsync
  and the `performance.now()` value at its first callback. A task after
  the frame clears it. Tasks run after the frame's rendering, so a
  preparation that ends after the frame but before that task still names
  the frame. Then nothing is subtracted, which can only keep idle time in.
- `frameWatch.count` = the number of frames that ran at least one callback.
  The shell stores the count between engine entry and the end of
  preparation as `frames_in_preparation`.
- `runningFrame()` = the running frame's vsync and start in page
  milliseconds and Android nanoseconds, or nulls between frames. They are
  stored as `running_frame_vsync_ns` and `running_frame_start_ns`.

epub.js runs its work queue and its location report in animation-frame
callbacks. So a page turn or a size change often ends its preparation
inside a frame. That frame's style, layout and paint then draw the page.

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
- `start` = the `performance.now()` value at the first animation-frame
  callback in the first frame after preparation. The wrapper's own
  callback runs before it in the same frame.
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
- `onComplete` = the method that Android calls once the WebView's DOM
  state at the request is ready to be drawn in the WebView's next draw, as
  Android documents it. `drawn_ns` is read there.

The WebView endpoint is thus "ready to be drawn", not "drawn". Chromium 133
queues a `QueueReportTimeSwapPromise` for the next main frame
(`WidgetCompositor::CreateQueueSwapPromise`). In Android WebView's
synchronous compositing mode, the answer comes at the activation of that
frame's layer tree (`QueueReportTimeSwapPromise::DidActivate`). A tree
activates once the tiles that it needs on screen are rasterized. WebView
draws inside Android's own frame. If the page's frame commits too late for
Android's draw at its vsync, the answer comes after the next vsync. The
time also includes the answer's trip to Android's UI thread.

If preparation ended inside a running frame, the request reaches the
renderer while that frame's JavaScript still runs. Chromium handles it
after the frame, so the answer comes with the next frame. These samples
keep the time from the end of the drawing frame's work to the next vsync.
Chromium gives the page no time for the end of a frame's work, so that
idle part cannot be measured apart. Asymmetry 2 counts these samples.

Collection excludes a WebView row with any of these faults:

- the vsync or the start of the frame after preparation is missing,
- that frame starts before its vsync, before preparation, or not before
  the drawn endpoint,
- a running frame has only one of its two times,
- a running frame starts before its vsync or after preparation,
- a conversion does not reproduce the stored nanoseconds.

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

1. Bookfin and WebView leave out the wait for the next frame only before
   their drawing frame. Waits that an engine schedules inside its own
   preparation stay. epub.js runs its work queue on animation frames
   (`src/utils/queue.js`). Bookfin runs pagination steps that are not
   urgent between frames (`PageSource.scheduleBetweenFrames`). These waits
   depend on the display refresh rate. The table under Drawing facts
   counts the frames inside preparation for each action.
2. WebView reaches the screen through Android's frame. In the headline
   run, Android answered 373 of 468 accepted WebView samples after a vsync
   that followed the start of the drawing frame. These include all 284
   samples whose preparation ended inside a running frame, and 89 of the
   other 184. These samples keep the idle time from the end of the drawing
   frame's work to that later vsync. Chromium gives the page no time for
   the end of a frame's work, so that idle time cannot be measured apart.
   Its upper bound is the time from the end of preparation to the later
   vsync, which also holds the rest of the frame's work: median 11.9 ms,
   p90 14.8 ms.
3. After the vsync, the two frame clocks start at different points.
   Flutter's build start is the UI thread's start of the frame. WebView's
   frame start is its first animation-frame callback, after the main
   thread handled any input. Both delays after the vsync stay in, so this
   affects only the facts below, not the drawn page.
4. The endpoints differ. Bookfin ends at the submission of its GPU
   commands. WebView ends at Android's report that the page is ready to be
   drawn, after its tiles were rasterized. That end includes the answer's
   trip to Android's UI thread. KOReader ends after its last pixel is on the CPU.
5. The WebView frame watcher sees only frames that ran an animation-frame
   callback. If preparation ends inside a frame without such a callback,
   the rule leaves out the rest of that frame's work. All 82 WebView
   samples that leave out a wait ended their preparation 9.6 ms or more
   after the previous vsync, median 13.9 ms. Samples that ended inside a
   running frame did so a median 5.2 ms after its vsync. The wait left out
   in those 82 samples has a median of 2.7 ms and a maximum of 7.1 ms.
6. A host GPU is not a phone GPU. The M1 Max is faster than a phone GPU,
   but each command crosses the emulator's translator to the host.
7. Whole-book work still differs, as in the original comparison. KOReader
   paginates the whole book on open and size change. Bookfin finishes its
   page map in the background. WebView lays out one chapter.
8. Page boundaries and illustration sizes differ between engines. Only one
   timed page has an image in Bookfin and WebView, `turn2` of Alice.

## Drawing facts from the headline run

These facts come from the accepted samples of `sym-drawn4`. They describe
the drawn page and are not result columns.

| Fact | Bookfin | WebView | KOReader |
| --- | --- | --- | --- |
| Median wait left out, per book (prose, long, illustrated) | 11.5, 8.4, 10.3 ms | 0, 0, 0 ms | none |
| Samples that leave out a wait | 445 of 468 | 82 of 468 | none |
| Drawing frame's start after its vsync, median / p90 | 1.5 / 6.4 ms | 3.4 / 11.0 ms | none |
| Time after the later of preparation and the drawing vsync, median / p90 | 5.4 / 18.1 ms | 14.9 / 22.7 ms | none, drawing is in preparation |
| Median GPU raster (`rasterFinish` minus `rasterStart`), per book | 2.6, 2.9, 2.2 ms | not exposed | none |
| Median CPU drawing (`drawCurrentPage`), per book | none | none | 1.8, 1.9, 2.2 ms |

Frames inside preparation, and WebView's frames and answers, per action:

| Action | Bookfin frames inside preparation, median / most | WebView frames inside preparation, median / most | WebView samples that ended inside a running frame | WebView answers after a later vsync |
| --- | --- | --- | ---: | ---: |
| Fresh open | 3 / 3 | 6 / 7 | 6 of 36 | 26 of 36 |
| Cached reopen | 1 / 2 | 5 / 6 | 20 of 108 | 62 of 108 |
| Page turn | 0 / 1 | 2 / 2 | 96 of 108 | 107 of 108 |
| Chapter turn | 0 / 0 | 2 / 2 | 54 of 108 | 70 of 108 |
| Size change | 1 / 2 | 3 / 3 | 108 of 108 | 108 of 108 |

Bookfin counts every frame that painted. WebView counts every frame that
ran an animation-frame callback. `results-drawn4-gpu/facts.json` holds the
facts per book, `results-drawn4-gpu/frames.json` the counts per action, and
`results-drawn4-gpu/webview-answer-gaps.txt` the answer times by action.

## Clocks

| Engine | Event clock | Conversion to Android nanoseconds |
| --- | --- | --- |
| Bookfin | Dart `Timeline.now` and `FrameTiming`, integer microseconds, both monotonic | Nine platform-clock round trips at process start. The shortest sets the offset, native time minus the local midpoint. The uncertainty is half that round trip plus 1 µs. Each sample checks that its frame timing lies between two of its own Timeline readings |
| WebView | `performance.now()`, milliseconds | The same nine round trips through a synchronous Java bridge. The uncertainty adds the observed timer step, 100 µs. The drawn endpoint is read on Java's own clock |
| KOReader | `CLOCK_BOOTTIME`, nanoseconds | None, it is Android's elapsed-realtime clock |

Each subtracted frame wait is the difference of two readings on one engine
clock: Flutter's vsync time and the Timeline for Bookfin, the animation
frame time and `performance.now()` for WebView. The conversion offset
cancels in that difference. For WebView, only the 100 µs timer step
remains.

The hop from Java dispatch to the engine's start is a fact, not part of
any interval (`bridge-hop-check.txt` in the result folder). For WebView,
its median is 0.86 ms and its smallest value 0.236 ms. Each sample's
conversion uncertainty is 0.101 to 0.351 ms. In 1 of 468 WebView samples,
the hop, 0.293 ms, is smaller than that sample's uncertainty, 0.351 ms.
KOReader needs no conversion. Its median hop is 0.23 ms.

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

Some endpoints are on Android's clock: dispatch, the bridge call after
preparation, WebView's drawn page and the window copy. The others are on
the engine's clock. Two times on one clock must be in exact order. A time
on the engine's clock and a time on Android's clock must be in order
within the sample's conversion uncertainty. A smaller crossing comes from
the conversion, not from the engine. The device test uses the same rule.

Delaying the window copy changes only
the copy endpoint, never an engine interval. The tests in
`test_preparation.py` cover these rules.

## Runs

Each run uses the original balanced schedule: 12 rounds and 108 fresh
process jobs, one engine at a time. Each job has one fresh open and three
of each warm action. No build or other heavy command of this ticket ran
while a timed schedule ran. The one rebuild during `sym-drawn4` ran while
that run was stopped, as described below. Other agents shared the host.

For the headline run, `run.py` measures each job only while the host is
quiet:

1. Before a job starts, it waits until the one-minute host load is under 8.
2. During the job, it reads the one-minute load every second.
3. If any reading is 8 or more, it moves the job's evidence to
   `rejected-load/` and measures the job again at the same place in the
   schedule.

`host-load.jsonl` records every attempt. Collection marks a job without an
accepted attempt as incomplete, and it keeps none of its rows. The
one-minute load is an average, so it reacts to a short spike with a delay.
The runs before `sym-drawn3` had no record per job.

| Run | Configuration | Run prefix | Evidence | Jobs passed | Measured samples accepted | Host load |
| --- | --- | --- | --- | ---: | ---: | --- |
| Drawn page (headline) | Host GPU | `sym-drawn4` | `measured-drawn4-gpu`, `results-drawn4-gpu` | 108 | 1,404 | every accepted job under 8, highest reading 7.86, four jobs measured again |
| Drawn page, superseded | Host GPU | `sym-drawn3` | `measured-drawn3-gpu`, `results-drawn3-gpu` | 108 | 1,404 | every job under 8, highest reading 7.3 |
| Drawn page, stopped | Host GPU | `sym-drawn2` | `measured-drawn2-gpu` | 20 of 108 | not collected | 4.4 at start, then about 30 from another agent's test run |
| Drawn page, superseded | Host GPU | `sym-drawn` | `measured-drawn-gpu`, `results-drawn-gpu` | 108 | 1,404 | 4.3 before, 5.8 after |
| Prepared page | Host GPU | `sym-gpu` | `measured-gpu`, `results-gpu-prepared` | 108 | 1,404 | 5.4 before, 10.6 after |
| Prepared page | SwiftShader | `sym-sw` | `measured-swiftshader`, `results-swiftshader` | 108 | 1,404 | 7.2 before, 13.9 after |

In `sym-drawn4`, four jobs reached a load of 8 or more and were measured
again at their place in the schedule. Their set-aside attempts are in
`measured-drawn4-gpu/rejected-load/`:

| Job | Highest load of each set-aside attempt | Accepted attempt |
| --- | --- | --- |
| `sym-drawn4-round-04-illustrated-bookfin` | 8.46 | 7.61 |
| `sym-drawn4-round-09-prose-bookfin` | 11.79, 8.14 | 7.25 |
| `sym-drawn4-round-09-illustrated-webview` | 9.83 | 7.86 |
| `sym-drawn4-round-10-illustrated-webview` | 8.06 | 7.57 |

Job 16, `sym-drawn4-round-01-prose-webview`, failed a device check and
stopped the run. The check required that WebView's end of preparation
come before the Java bridge call. These two times are on different
clocks, and the check allowed no tolerance. The failure was 0.018 ms,
against a conversion uncertainty of 0.301 ms in that job. Host collection
had the same zero tolerance. The lead changed both to the rule under
Content checks, with host tests first. The lead rebuilt and reinstalled
only the three test packages. The three engine packages on the emulator
kept their hashes (`installed-app-apks-during-drawn4.txt`). The failed
attempt is in `measured-drawn4-gpu/rejected-check/`. The run went on from
job 16 with `--start 15`. One accepted sample needs the new rule:
`sym-drawn4-round-04-prose-webview/9`, whose end of preparation is 0.030 ms
after the bridge call, against an uncertainty of 0.301 ms.

The `sym-drawn2` run used the same shells as `sym-drawn3`. At about 12:15
local time, another agent started a full `flutter test` run, and the
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
python3 tool/research/epub_engines/run.py --prefix sym-drawn4 --serial emulator-5558 --output tool/research/epub_engines/evidence/symmetric-20261111/measured-drawn4-gpu
python3 tool/research/epub_engines/run.py --prefix sym-drawn4 --serial emulator-5558 --start 15 --output tool/research/epub_engines/evidence/symmetric-20261111/measured-drawn4-gpu
python3 tool/research/epub_engines/collect.py tool/research/epub_engines/evidence/symmetric-20261111/measured-drawn4-gpu tool/research/epub_engines/evidence/symmetric-20261111/references-gpu.json --output tool/research/epub_engines/evidence/symmetric-20261111/results-drawn4-gpu
python3 tool/research/epub_engines/tables.py tool/research/epub_engines/evidence/symmetric-20261111/results-drawn4-gpu/summary.json drawn prepared
```

`collect.py` keeps each cell in integer nanoseconds and exact fractions
until the last step. A median halfway between two tenths of a millisecond
thus rounds up, as the rounding rule states. `exact-rounding-check.py`
recomputes all 1,400 published rounded values of the five result folders
from the accepted samples, apart from `results.py`. It applies to each
folder the drawn-page rule that its summary names. It found no mismatch.
Before this fix, three per-book medians of the WebView prepared page were
0.1 ms too low in the diagnostic tables. No headline value changed.

`png-dedup-1.py`, `png-dedup-2.py` and `png-dedup-3.py` removed the PNG
copies listed in `png-duplicates-removed.tsv`. Collection gave the same
samples before and after each removal (`results-after-png-removal.sha`).
The PNG copies of the two frame-watch checks, `experiment-frame-watch` and
`experiment-frame-watch-red`, were deleted without that list. Their rows
keep each capture's pixel hash, and no result uses them.

`run.py` runs from `tool/research/epub_engines` with relative output paths.
`collect.py` writes `summary.json`, `facts.json`, `frames.json` and the
certified `samples.jsonl`. The summary keeps each interval's cells,
exclusions and equal-book means separately.

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
page. `sym-drawn` rows have no WebView frame times, so `results-drawn-gpu`
excludes its WebView rows from the drawn page. Its Bookfin and KOReader
cells use the interval rule of the `sym-drawn3` collection.
The run `sym-drawn3` repeated the full schedule with both shell changes.
The raw `sym-drawn` evidence stays unchanged.

Three short WebView checks guided the second change. Each ran one measured
job per book and passed the device test.

| Check | Shell | What it showed |
| --- | --- | --- |
| `experiment-frame-wait` | Frame start reported, page text read before the visual-state request | In 9 of 39 samples, Android answered 10 ms or more after the page's frame started |
| `experiment-webview-answer` | Visual-state request before JavaScript yields, page text read after the frames | 8 of 39 such samples remained |
| `experiment-webview-vsync` | Vsync times added | 5 of 39 answers came after a later vsync. In 4 of them, the page's frame started 6.7 ms or more after its vsync |

## The superseded second drawn-page run

The run `sym-drawn3` passed every check and every load check. Its rule
subtracted the time from the end of preparation to the start of the first
WebView frame after preparation. The reviewer found that a WebView page
turn or size change usually ends its preparation inside an animation
frame. That frame draws the page, so the old rule removed its work.

The evidence is where preparation ended relative to the vsync before the
next frame (`preparation-after-vsync-drawn3.txt`):

| Action | Samples | Median end of preparation after that vsync | Within 8 ms | Median that the old rule subtracted |
| --- | ---: | ---: | ---: | ---: |
| Fresh open | 36 | 22.9 ms | 0 | 3.2 ms |
| Cached reopen | 108 | 17.4 ms | 5 | 4.5 ms |
| Page turn | 108 | 4.8 ms | 90 | 15.9 ms |
| Chapter turn | 108 | 12.8 ms | 23 | 7.8 ms |
| Size change | 108 | 4.5 ms | 105 | 14.1 ms |

The `sym-drawn3` shell did not record whether a frame was running, so its
rows cannot be collected with the current rule.

Two short checks proved the new shell fields before the run:

| Check | Packages | Result |
| --- | --- | --- |
| `experiment-frame-watch-red` | New device test, old shells, one Bookfin and one WebView job | Both failed the new assertion that the shell counts frames inside preparation |
| `experiment-frame-watch` | New device test and shells, one Bookfin, three WebView and one KOReader job | All passed. 23 of 39 measured WebView samples ended inside a running frame. Android answered 33 of 39 after a later vsync | The parent decided to
instrument the shell and run the whole schedule again. The raw
`sym-drawn3` evidence and its results stay unchanged.

Its Bookfin rule also ended the subtraction at `buildStart`, not at the
vsync. The current rule keeps the time from the vsync to the build start
in both engines.

## Bugs found in the earlier partial work

- The KOReader shell passed the event identity through `JSONObject.quote`,
  which writes `\/`. Lua rejects that escape, so every KOReader job of
  that version failed (`red-device-koreader-lua-quoting.txt`).
- An early version of this ticket's repeat-draw buffer was not referenced
  from Lua after setup. The garbage collector freed it, and KOReader
  crashed (`device-koreader-freed-buffer-crash.txt`).
