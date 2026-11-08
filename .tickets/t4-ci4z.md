---
id: t4-ci4z
status: open
deps: []
links: []
created: 2026-11-08T14:11:18Z
type: task
priority: 3
assignee: Alexis Purslane
parent: boo-fs0n
---
# Retake the README screenshot of a PDF page under recognition with the scrub bar

docs/screenshots/reader-recognizing.png still shows the old reader progress bar after boo-315o. The emulator's OCR cache already holds the Windfall page, so the Recognizing English text card no longer shows. Retake it at 720 by 1600 on emulator-5554 with a fresh OCR cache, and make sure that no personal data shows.


## Notes

**2026-11-08T17:05:46Z**

2026-11-08: docs/screenshots/reader-deck.png also predates the glass dock (boo-bz3x); retake it with the dock in the same pass.
