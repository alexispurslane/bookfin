---
id: te-k1l3
status: open
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

