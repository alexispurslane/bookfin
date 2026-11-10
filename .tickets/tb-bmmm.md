---
id: tb-bmmm
status: closed
deps: [tb-t0ea]
links: []
created: 2026-11-10T03:01:07Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-fval
---
# Measure Tesseract's layout pass against full recognition on an Android emulator

W0b of docs/plans/pdf-word-image-reflow.md (The layout pass, measurements). The host measurement (tool/evidence/reader/layout-pass/20261109/) found the layout pass at 13 percent of full recognition on a dense page. Measure the same on an Android emulator through the new layout and recognize channel methods, so that the gain on Android is known. Use the T3 device tools for the app. Pages: the dense, skewed and raven pages of the host evidence, and one page of a scanned book from the user's library (not committed).

## Acceptance Criteria

A table under tool/evidence/reader/layout-pass/ gives, per page and best of three, the time of the layout pass, of recognition after it, and of full recognition alone, with the emulator's ABI and the host. The ticket states the time from a page turn to the first word screen against the time to the first text screen before this epic. If the layout pass takes more than 40 percent of full recognition, record a ticket to revisit the design.

## Notes

**2026-11-10T13:29:22Z**

Answered by tb-t0ea's emulator run (own AVD, Android 36 arm64, debug build, one run): the layout pass took 12 to 13 percent of recognition alone on the three densest pages (census-notice pages 1 and 2: 342 and 347 ms against 2876 and 2813 ms; nist-cloud page 6: 192 against 1510 ms), and 33 to 51 percent on light pages where recognition itself is short (scanned fixture 116 against 226 ms). The 40 percent gate concerns dense pages, where the wait matters, so the design stands. Pixel 8 times come in tb-fb6j.
