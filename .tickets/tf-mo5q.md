---
id: tf-mo5q
status: open
deps: []
links: []
created: 2026-11-08T22:58:02Z
type: task
priority: 3
assignee: Alexis Purslane
parent: boo-b2ey
---
# Find which Android start work in Bookfin's first second can wait until after the first frame

Found in te-k1l3. A Perfetto trace of a cold start of a profile build on an arm64 Android 36 emulator (4 virtual CPUs, Impeller on OpenGLES) shows four kinds of work that compete for the CPUs in the first second after the engine starts: the engine's shader program compiles on the raster thread (about 70 ReactorGLES::React slices, 390 ms, which end about 100 ms after the first frame), the ART JIT thread pool (165 ms in a 0.4 s window), androidx EmojiCompatInit (123 ms in that window, 447 ms in total), and the audio_service AudioService serviceCreate on the main thread (158 ms). In that window a raster snapshot waited runnable for 186 ms of its 398 ms. Find which of the Android work can start later (for example the androidx.startup emoji2 initializer, or binding the audio service before playback is needed), and measure the first frame and the first second before and after. The engine's shader compiles are not ours to move.

## Acceptance Criteria

A trace of a cold start before and after, on the emulator and on the Pixel 8, with the work that moved and the change in time to the first frame.

