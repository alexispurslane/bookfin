---
id: boo-6n45
status: open
deps: []
links: []
created: 2026-11-12T23:41:02Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Keep the Android audio extractor open between speech windows and test the shipped decoder

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: plausible. The extractor behavior comes from AOSP and was not measured. native/speech/bookfin_speech.c:181-216 opens the file and builds a new extractor and codec for each 8-second window. For a single-file M4B, the platform extractor builds its sample table at the first seek, an estimated 25 to 50 MB for a 20-hour book. test/speech/decoder_test.dart runs only on the Mac, where the Apple branch runs, so no automated test runs the Android codec loop, the stereo mix or the resample. Keep the extractor and codec of the last file in the native state of the worker. Split the platform decode from one shared mix, trim and resample stage that host tests run with stereo 44.1 kHz input. Related: t2-vhnz.

