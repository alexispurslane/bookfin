---
id: tb-zx7r
status: in_progress
deps: [tb-22fu]
links: [te-rtok]
created: 2026-11-10T12:48:24Z
type: feature
priority: 1
assignee: Alexis Purslane
parent: boo-fval
---
# Cut the PDF text view into screens of whole lines

W6b of docs/plans/pdf-word-image-reflow.md (Screens and turns, decision 2 of 2026-11-10). The text view stops being one scroll column. It lays out the reading text with its TextPainter as today, gives the line metrics to cutScreens (from tb-0mex), and draws one screen as the part of the painter from the screen's first line top to the next screen's first line top, with no scroll controller. A swipe shows the next or previous screen, past the last screen it shows the next source page's first screen, and back from the first screen the previous page's last screen. A vertical drag does nothing. The place of a screen is the first character of its first line. A text size or width change cuts the screens again and shows the screen that holds the shown place.

## Acceptance Criteria

Behavior tests, red first: no text view screen cuts a line or starts with a paragraph gap; a swipe shows the next screen and passes between source pages at their ends in both directions; a vertical drag changes nothing; the place of a screen is its first line's first character and reopening at it shows the same screen start; a size step keeps the shown place on screen; a place saved in the word view opens on the text view screen that holds it. Existing PDF reflow tests that scrolled are rewritten to turn screens, and the move by 85 percent of the viewport is gone.


## Notes

**2026-11-10T20:55:54Z**

Implemented whole-line PDF text screens in pdf_text_view.dart, using the existing cutScreens and a clipped TextPainter. PdfViewport owns screen turns and source-character addresses; vertical drags do not move text. Size, width and height changes recut around the displayed place. Forward and backward source-page crossings, reopening, word-view-compatible addresses, normalized-to-source offset mapping, partial-line rejection and paragraph-gap removal have behavior tests. Existing scrolling tests now turn screens or inspect the displayed text through accessibility. No three-way enum, settings, word-view engine, crop engine or native changes.

Red evidence: /tmp/bookfin-tb-zx7r-red.log records five meaningful failures against the original scrolling implementation (vertical drag, source-page boundary, word-to-text placement, size change and paragraph gap). Initial targeted green: 19 passed. Subsequent drawing/source-map/end-of-book tests are included in the final suite. Migrating existing text-widget assertions exposed eight stale expectations; these were updated for the displayed screen, not the entire source page. The first full run found one remaining stale text-widget assertion in ocr_viewport_test.dart: 2569 passed, 21 skipped, 1 failed; it was corrected. An initial analysis warning was an unused import in pdf_navigation_test.dart and was removed.

Final required checks, all through nix develop: dart format --output=none --set-exit-if-changed lib test tool integration_test: passed, 396 files, 0 changes; flutter analyze lib test integration_test: passed, no issues; flutter test --concurrency=2 --reporter expanded: passed, 2570 tests, 21 skipped, 4m13s. Logs: /tmp/bookfin-tb-zx7r-format.log, /tmp/bookfin-tb-zx7r-analyze.log, /tmp/bookfin-tb-zx7r-full.log. The conditional native OCR check does not apply because native code did not change. Flutter emits existing missing iphoneos/iphonesimulator SDK diagnostics before tests; the required checks still exit successfully. No devices, coverage or mutation jobs were used. Explicit Text-mode routing remains with tb-9mcf and parent integration; Source Serif 4 remains linked follow-up te-rtok. Fresh independent review is next; ticket stays in progress for parent integration.
