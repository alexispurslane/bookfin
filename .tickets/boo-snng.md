---
id: boo-snng
status: in_progress
deps: []
links: []
created: 2026-11-11T19:51:50Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-z3is
---
# Prototype speech search to correct a whole-book place estimate

User decision 2026-11-11 after t3-a4fi: chapter matching refuses most of the real library. Prototype the user's idea: a whole-book progress estimate, corrected by on-device speech recognition and a text search near the estimate. Audio to text: transcribe about 15 s at the listening place, search the ebook text within the estimate's error window (p90 22 pages). Text to audio: transcribe at the estimated time, find those words in the text, correct the time, repeat 2 to 3 rounds. Fail early when the words are not found, then fall back. Fetch only the needed audio range from the server when not downloaded. Emulator only, no Pixel. Measure speed per jump and accuracy. The user accepts the speech approach only if it is fast.

