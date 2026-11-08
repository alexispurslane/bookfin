---
id: tc-ptuo
status: open
deps: [tc-cl77, tc-rap6]
links: []
created: 2026-11-08T19:23:13Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-b2ey
---
# Tune step budgets and cache limits on the Pixel 8

Goal: measure the native reader on the Pixel 8 in a profile build, and set the step budget and the cache limits from the numbers. This absorbs t6-6gej.

Design sections: "Layout off the frame path" (Steps, Cache policy), "Pages" (the deferred page map on disk), "Risks".

Files: lib/reader/epub/page_source.dart (budget and limits only), docs/research/native-epub-phone.md (new).

Steps:
1. Build a profile APK in the dev shell. Use the T3 device tools (device_list, device_open, then the device-bound agent-device command) for every launch and input. If the phone is in use (DEVICE_IN_USE), wait and retry. Never launch it another way.
2. Script a session: open deep in the 430,000-character Keats section, turn 20 pages, turn back 5, change the text size twice, scrub across the book with the deck, and hide and show the dock 5 times.
3. Record UI and raster frame times, step durations, the time to the first page, the deck page time, and memory (dumpsys meminfo and the Dart heap).

## Design

docs/plans/native-epub-reader.md (epic boo-b2ey). Read the sections named in the description. The design decides the owners, interfaces and order. Ask the orchestrator before changing them.

## Acceptance Criteria

- In the scripted session, no UI frame goes over 8.3 ms because of a layout step, or the budget is lowered until none does.
- A turn back right after opening deep in Keats waits under 0.5 s, or a new ticket records the page map on disk with the numbers.
- Memory stays within the limits, and any changed limit in page_source.dart cites the measurement.
- docs/research/native-epub-phone.md records the numbers and the commands.

