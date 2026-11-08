---
id: t6-6gej
status: open
deps: []
links: []
created: 2026-11-08T15:20:54Z
type: task
priority: 3
assignee: Alexis Purslane
parent: boo-fs0n
---
# Measure the reader's frame rate on hardware graphics

emulator-5554 renders with SwiftShader, a software GPU, at 1080 by 2400. In boo-foo7, every reader frame took 117 to 171 ms of raster time (median), with or without the scrub deck: a plain page turn and the contents sheet were as slow as the deck. Build time stayed at about 1 ms (median), 7.3 ms at most, so the UI isolate is free. The 60 fps goal for the deck motion cannot be judged on this emulator. Measure the deck, a page turn and the reader sheets with a profile build on a phone or an emulator with host GPU, and record frame times.


## Notes

**2026-11-08T17:00:09Z**

boo-duaq moved the EPUB WebView to texture-layer composition (useHybridComposition: false), so Flutter raster no longer runs on the Android main thread. One cost moved instead: on SwiftShader, each WebView redraw blocks the main thread in postAndWait and Record View#draw. In the last emulator scrub, one redraw during the drag took 186 ms (the second page preview), and the redraws after landing took 167 and 434 ms, with no Choreographer warning. Raster median was 178 ms. On a phone, measure the WebView redraw on the main thread at page turns and at the end of a scrub, and compare with hybrid composition.

**2026-11-08T19:23:53Z**

Absorbed by tc-ptuo (epic boo-b2ey). It measures the native reader's frames, layout steps and memory on the Pixel 8. The WebView redraw costs in the notes above go away with tc-rap6. Close when tc-ptuo merges.
