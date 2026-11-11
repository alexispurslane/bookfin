# EPUB phase timing: November 11, 2026

This rerun answers which work precedes page preparation in each real engine.
It does not establish an equal-work engine ranking. The original window-copy
comparison, raw evidence, and frozen references remain unchanged.

The parent selected Option A from the existing instruction to exclude drawing.
This is not user approval that these endpoints are equivalent. Option B would
have added a matched raster-output measurement, including drawing, and was not
selected. No homepage comparison changes belong to this ticket.

## Endpoints and scope

All durations start at the shell's dispatch of the requested operation. Every
raw row retains the phase endpoints below. Nanoseconds are the stored time unit.
Reports divide elapsed nanoseconds by one million to show milliseconds.

| Engine | `operation_returned_ns` | `preparation_ns` | Work not excluded by the preparation endpoint |
| --- | --- | --- | --- |
| Bookfin | Requested pager operation returned and its shown page was obtained | Production `PageSource.picture` returned the recorded `ui.Picture`, with required page images decoded at display scale | Flutter picture recording, asynchronous pager work, widget scheduling needed to obtain layout, and the shell's 1 ms readiness polling |
| epub.js / WebView | Requested epub.js operation returned, before the shell waits for resources | Displayed contents' fonts and section images were awaited, views expanded, current location obtained, and document geometry read | epub.js request queues, its internal animation-frame scheduling, WebView dispatch, DOM/layout, and decoding of all images in displayed sections |
| KOReader | Navigation plus explicit `renderDocument` and current-page lookup finished, before page buffer allocation and `drawCurrentPage` | `drawCurrentPage` returned a complete native RGBA bitmap | Page buffer allocation, drawing, glyph/image raster work and image decoding inside drawing |

The operation-returned milestones are limited diagnostics, not a shared pure
layout boundary. Bookfin can already have recorded a draft picture or completed
image work. An epub.js operation return alone does not prove that relocation or
resources are ready. KOReader's pre-Draw milestone excludes image decoding that
is required to show the page. Neither KOReader milestone equals Bookfin's
recorded picture plus decoded images, or WebView's layout and decoded resources.

Bookfin's image scope is the requested page. WebView's image scope is the
displayed section, including images outside the requested page. KOReader eagerly
paginates the whole publication. These differences remain visible rather than
being hidden behind one shared endpoint name.

`engine_ready_ns` retains the old adapter boundary for diagnosis. Bookfin obtains
it through the platform clock after the shown-picture identity check. WebView
records it at entry to the Java readiness bridge. KOReader records it after Lua
has returned its metadata through JNI. These boundaries include different
diagnostic and bridge costs. None is silently substituted for `preparation_ns`.

`end_ns` retains the original reference-matching window-copy endpoint. Display
scheduling, Flutter texture composition, unsuccessful copies, PixelCopy and
diagnostic extraction can occur between preparation and that endpoint. A
requestAnimationFrame callback is never evidence of a rendered frame. No guessed
constant is subtracted from any duration.

## Clocks and dispatch

Android dispatch, bridge reception and copy timestamps use
`SystemClock.elapsedRealtimeNanos`, Android's monotonic clock including suspend.
The emulator stays awake during the schedule. The Android test runner still
polls each workload every 100 ms, outside the operation controller.

| Engine | Event clock | Conversion to Android elapsed nanoseconds | What remains in the interval |
| --- | --- | --- | --- |
| Bookfin | `Timeline.now`, in integer microseconds | Before timing, take nine platform-clock round trips. Keep the shortest. Offset is native time minus the midpoint of local send/receive times. Uncertainty is half that round trip plus 1 microsecond. Retain raw event microseconds, offset, round-trip time and uncertainty | Start is recorded locally just before dispatch, so no platform-clock request/response is inserted at either timed boundary. Pager/worker/widget scheduling remains. Platform delivery and later shown-picture polling are after preparation |
| WebView | `performance.now`, in milliseconds | Before timing, take nine synchronous Java clock round trips. Keep the shortest. Add the native-minus-local-midpoint offset and round to integer nanoseconds. Retain raw event milliseconds, offset, round-trip time and uncertainty. Uncertainty is half the selected round trip plus 1 microsecond | Start remains Java dispatch, so Java-to-WebView execution and engine queues remain inside. The end is saved before text extraction, JSON serialization and the asynchronous readiness bridge |
| KOReader | `clock_gettime(CLOCK_BOOTTIME)`, seconds and nanoseconds | Direct Android boot-time nanoseconds, with zero offset and no conversion. The FFI call itself still has a small cost | Start remains Java dispatch, so the executor queue and JNI entry remain inside. The end precedes copying pixels to a Lua string, extracting text, serializing metadata and copying to an Android Bitmap |

Clock uncertainty is a bound on the calibration handshake, not a measurement of
all timer resolution or scheduling noise. WebView timer precision and normal
clock-call costs remain. The report retains uncertainty and raw timestamps;
small phase differences must not be treated as exact CPU costs. The conversion
is calibrated for each fresh process, not assumed to share an epoch across
engines or processes. Capture delay cannot alter recorded preparation time.

## Audited pinned sources

The Bookfin production source is unchanged from the original manifest's
`6ba37d9a4a23be07f857d369da73115fedcc53fb` through this ticket's base
`7087ff6ee33c7b897ec37058e7cb47720c059f39`. The shell imports that source; it does
not add a renderer. `lib/reader/epub/page_source.dart:521` establishes the picture
and decoded-image boundary. `lib/reader/epub/pager.dart:686` and `:720` show why
the earlier shown-page boundary need not include image completion.

| Pinned source | Relevant evidence |
| --- | --- |
| KOReader v2026.07.1, base `6e4bc81af4e04f78d81677a323a780a71b29702a`, `cre.cpp:707` | `renderDocument` calls the layout Render operation |
| Same base, `cre.cpp:3775` | `drawCurrentPage` resizes, renders, draws, then converts BGRA/inverted-alpha pixels to the RGBA buffer before returning |
| crengine `b32a88ffbbf505cf2ea5208c1a49002d70d3609f`, `crengine/src/lvdrawbuf.cpp:902` and `:1639` | Image decoding takes place inside image drawing. The pinned Lua methods expose no page display-list or decoded-page-image preparation endpoint |
| epub.js 0.3.93 npm archive, SHA-256 `180b33059ca15e2b4f129eb7fef6cae0bf6005c02af5194d13e5cb48378d538f` | `src/utils/queue.js:12` uses animation-frame scheduling; `src/rendition.js:689` schedules location reporting through that queue and another animation-frame callback |

The source retrieval paths, full file hashes and release/submodule identities
are retained in `evidence/preparation-20261111/source-audit.txt`. These are audits
of the already pinned release, not replacement engine builds.

## Eligibility and evidence preservation

The existing runner, balanced schedule and reference certification remain the
owners of execution and content checks. A new evidence directory and run prefix
prevent reuse or replacement of old samples. All three release and test APKs
must finish building and be verified installed before measurements start.

After the preparation timestamp, the engine stays on the same destination until
its reference-matching screenshot and raw metadata are stored. The Android test
checks the destination, operation sequence, page/chapter/font changes and pixels.
Host certification separately checks source-validated, OCR-validated and
image-reviewed references, visible text, location, source-book digest, settings,
pixel hash and the frozen reference manifest's digest. No timed capture certifies
itself. Original reference-publication safeguards remain in force.

Phase summaries additionally reject a missing or stale operation identity, a
wrong engine scope, missing or reversed endpoints, an invalid clock conversion,
or a phase after bridge reception/capture. Incorrect content cannot enter any
successful timing aggregate. Delayed capture changes only the retained copy
endpoint, not the preparation endpoint. Raw phase timestamps are never rewritten
by collection. Old rows without the new phase fields remain valid evidence for
the original copy metric but cannot become new preparation samples.

The schedule has twelve balanced rounds and 108 fresh process jobs. Each job
has one fresh open and three of each warm operation: cached reopen, page turn,
chapter crossing and font change. There are 1,404 measured operations plus 1,080
untimed cache/destination preparation steps. Counts, means, medians and nearest-
rank p90 remain separated by engine, book and operation. The summary mean for an
operation gives each of the three book means equal weight. Warm samples within
one process are not independent process starts. No physical-phone, equal-quality,
speedup-multiplier or universal-winner claim follows from these diagnostics.
