---
id: t2-er9m
status: open
deps: []
links: [boo-pc6x]
created: 2026-11-11T18:29:16Z
type: chore
priority: 3
assignee: Alexis Purslane
parent: boo-fs0n
---
# Find the calibration raster in the Bookfin benchmark shell through the drawn-frame timing

In tool/research/epub_engines/bookfin/lib/main.dart, a calibration run waits for a later raster with its own _raster Completer and _rasterAfter time, which _receiveFrames completes. Measured runs find the page's frame through _painted and _firstFrameWith. Two mechanisms thus answer the question of which frame drew a page. The reviewer of boo-pc6x (finding D4) asked for one. Change only the benchmark shell, not Bookfin's renderer, and keep the calibration pixels the same.

## Acceptance Criteria

One mechanism finds the frame that drew a page for calibration and measured runs. Calibration references stay identical.

