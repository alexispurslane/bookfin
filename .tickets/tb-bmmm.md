---
id: tb-bmmm
status: open
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
