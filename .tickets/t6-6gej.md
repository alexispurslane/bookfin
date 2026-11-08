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

