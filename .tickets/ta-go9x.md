---
id: ta-go9x
status: open
deps: []
links: []
created: 2026-11-10T17:20:32Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fval
---
# Measure how long a kept PDF survey takes to read when a book opens

On the debug build on an Android 36 emulator, the first open after an install resumed the margins book at page 10 and showed it uncropped: the kept crop was not known within the 300 ms wait of tb-valc. A later reopen showed the page cropped. Measure the time from the open to the kept survey's crops (SurveyFiles.read and its decode hop) on a release build on the Pixel 8. If it is often more than 300 ms, read the kept survey sooner or make it cheaper to read. Evidence: docs/evidence/reader/trimmed-margins/README.md.

