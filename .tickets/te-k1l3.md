---
id: te-k1l3
status: closed
deps: []
links: []
created: 2026-11-08T22:04:24Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-b2ey
---
# Draw the first scrub deck page after a book opens in under 0.3 s

Measured during tc-mxfp with tool/reader/deck_benchmark.dart, a profile build on an arm64 Android 36 emulator (SwiftShader software GPU, host load 9 to 14 on 10 cores). Deck pages in a section took a median of 3 ms (p90 4 to 6 ms), and first pages of a new section 17 to 21 ms. But the first deck page after the book opened took 35 to 587 ms, and the second up to 329 ms. The first Picture.toImage of the process alone took 70 to 288 ms. With one small toImage and a 2 s pause before the walk, every deck page took at most 21 ms. Find whether the cost is the raster thread's first toImage, the work around the newly opened page (neighbors, main run, next section), or both. A small toImage when the book opens, or when a scrub starts, can warm the raster path. Measure on the Pixel 8 (tc-ptuo was dropped, so measure here).

## Acceptance Criteria

On the Android emulator and on the Pixel 8, the first deck page of a scrub right after a book opens takes under 0.3 s, measured with tool/reader/deck_benchmark.dart.


## Notes

**2026-11-08T22:58:15Z**

Cause, measured on a disposable AVD (bookfin-k1l3, arm64 Android 36, 4 virtual CPUs, Impeller on OpenGLES with SwiftShader, host load 9 to 21 on 10 cores). The cost is not the book and not a first use of toImage. It is a window of about 1 s after the process starts. In that window the engine compiles its shader programs on the raster thread (Perfetto: about 70 ReactorGLES::React slices, 390 ms, ending about 100 ms after the first frame), and Android's start work in the same process (ART JIT, EmojiCompatInit, AudioService serviceCreate) competes for the 4 CPUs. The first raster snapshot (DoMakeRasterSnapshot, 398 ms) spent 287 ms in one untraced GL reactor operation and waited runnable for 186 ms. Evidence: with no book open, a toImage of a blank 1x1 picture took up to 190 ms in the first second after the first frame and 1 ms after it. A warm-up toImage right after the book opened (blank 1x1, or a strip of the shown page at the deck scale) took 11 to 260 ms, and the first deck page after it still took 116 to 562 ms over 10 runs, so a warm-up only moves the same wait. Opening the book 1 s or 3 s after the first frame, with no warm-up and with all the work around the shown page still running, gave a first deck page of 16 to 29 ms over 12 runs. So no change in the pager or the page source helps, and none was made.

Change: tool/reader/deck_benchmark.dart opens the book OPEN_AFTER_MS (default 3000) after the first frame is rasterized, as a book opens in a running app, and also prints the first six deck page times. OPEN_AFTER_MS=0 measures the cold start case.

Emulator results, 6 cold process starts each, first deck page: old benchmark (open at the first frame) 117, 190, 253, 273, 398, 496 ms. OPEN_AFTER_MS=0: 217, 328, 335, 379, 480, 496 ms (second page up to 343 ms). OPEN_AFTER_MS=1000: 16 to 18 ms (every page at most 13 ms in a section, 19 ms for a new section). OPEN_AFTER_MS=3000: 16 to 29 ms (at most 16 ms in a section, 20 ms for a new section).

Not met: the Pixel 8 was not measured, because this task's brief kept off the user's Pixel. The cold start case on the emulator stays above 0.3 s for 4 of 6 runs; its cause is the engine's start and Android's start work, recorded as tf-mo5q. The orchestrator decides whether the acceptance means a book opened in a running app (met on the emulator) or also a scrub in the first second after a cold start.

**2026-11-08T23:11:45Z**

Orchestrator, 2026-11-08: accepted as met. A person cannot open a book and scrub within the first second after the process starts, so the goal applies to a book opened in a running app (16 to 29 ms on the emulator). No Pixel 8 measurement: on 2026-11-08 the user said that no Pixel benchmark is needed. The start-up window itself is tf-mo5q.
