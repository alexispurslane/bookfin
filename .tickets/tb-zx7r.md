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

**2026-11-10T20:32:18Z**

Launched from integrated base 2ef6bfa with codex/gpt-6.1-sol reasoningEffort=xhigh. taskId: node:delegated-task:command%3Amcp%3Ae6a3d378-c450-4501-a47c-77e7994db5fb%3Adelegate-task%3Asol-xhigh-word-followup-20261110-tb-zx7r-1; childThreadId: thread:delegated-task:command%3Amcp%3Ae6a3d378-c450-4501-a47c-77e7994db5fb%3Adelegate-task%3Asol-xhigh-word-followup-20261110-tb-zx7r-1; clientRequestId: sol-xhigh-word-followup-20261110-tb-zx7r-1. Separate T3 worktree; lead implements, one fresh read-only Sol xhigh reviewer, lead fixes. Parent integrates/closes and owns hardening. No physical-device UI input. Launch state: running; branch pending report.
**2026-11-10T20:55:54Z**

Implemented whole-line PDF text screens in pdf_text_view.dart, using the existing cutScreens and a clipped TextPainter. PdfViewport owns screen turns and source-character addresses; vertical drags do not move text. Size, width and height changes recut around the displayed place. Forward and backward source-page crossings, reopening, word-view-compatible addresses, normalized-to-source offset mapping, partial-line rejection and paragraph-gap removal have behavior tests. Existing scrolling tests now turn screens or inspect the displayed text through accessibility. No three-way enum, settings, word-view engine, crop engine or native changes.

Red evidence: /tmp/bookfin-tb-zx7r-red.log records five meaningful failures against the original scrolling implementation (vertical drag, source-page boundary, word-to-text placement, size change and paragraph gap). Initial targeted green: 19 passed. Subsequent drawing/source-map/end-of-book tests are included in the final suite. Migrating existing text-widget assertions exposed eight stale expectations; these were updated for the displayed screen, not the entire source page. The first full run found one remaining stale text-widget assertion in ocr_viewport_test.dart: 2569 passed, 21 skipped, 1 failed; it was corrected. An initial analysis warning was an unused import in pdf_navigation_test.dart and was removed.

Final required checks, all through nix develop: dart format --output=none --set-exit-if-changed lib test tool integration_test: passed, 396 files, 0 changes; flutter analyze lib test integration_test: passed, no issues; flutter test --concurrency=2 --reporter expanded: passed, 2570 tests, 21 skipped, 4m13s. Logs: /tmp/bookfin-tb-zx7r-format.log, /tmp/bookfin-tb-zx7r-analyze.log, /tmp/bookfin-tb-zx7r-full.log. The conditional native OCR check does not apply because native code did not change. Flutter emits existing missing iphoneos/iphonesimulator SDK diagnostics before tests; the required checks still exit successfully. No devices, coverage or mutation jobs were used. Explicit Text-mode routing remains with tb-9mcf and parent integration; Source Serif 4 remains linked follow-up te-rtok. Fresh independent review is next; ticket stays in progress for parent integration.

**2026-11-10T21:21:05Z**

Fresh independent review completed against original base 2ef6bfa8faa3e13958c4cd7eda703cbb3a5d5d4f and built HEAD c0c4ea88acad5dcd50d1893e9415ff28f77f94cf. Review task: node:delegated-task:command%3Amcp%3A4b381a84-99dc-4e81-a84f-194dd2c2008a%3Adelegate-task%3Atb-zx7r-fresh-review-c0c4ea8-20261110. Exactly one reviewer was started. Original verdicts are retained: correctness changes_required; fulfillment changes_required; design changes_required. The reviewer found one P2/medium issue, R1, and no materially unverified assessments. R1: after crossing a source-page boundary, another turn before the next frame could use the preceding page layout and save the wrong place. Original location: pdf_viewport.dart:373. Static review predicted source page 2 character 45 instead of source page 1 character 90 on an immediate reverse.

R1 verified and resolved by the ticket lead, without another reviewer. Red first: the exact cross-and-reverse recipe failed with actual (2,45), expected (1,90). A second test showed a turn before the first text layout skipped to (2,0) instead of (1,45). Both failures are in /tmp/bookfin-tb-zx7r-r1-red.log. The fix keeps page, PdfText, layout and selected index in one _TextScreen value. _clearTextScreen disposes and invalidates that value together. Rendering and movement both call _layText, which validates the same source page, text identity, measured size and style. A cached size permits immediate layout of the new page; before any text size has been measured, a turn waits for the first frame and rejects a superseded page. Source-character addresses use the text and page attached to that layout, never an independently replaced page text. Evidence: lib/reader/pdf_viewport.dart:83, :381, :386 and :427. Regression tests: test/reader/pdf_text_screens_test.dart:287 and :317. All 12 text-screen tests pass in /tmp/bookfin-tb-zx7r-r1-green.log.

Final post-fix required checks, all through nix develop: dart format --output=none --set-exit-if-changed lib test tool integration_test: PASS, 396 files, 0 changes; flutter analyze lib test integration_test: PASS, no issues; flutter test --concurrency=2 --reporter expanded: PASS, 2572 passed, 21 skipped, 3m45s. Logs: /tmp/bookfin-tb-zx7r-r1-format.log, /tmp/bookfin-tb-zx7r-r1-analyze.log, /tmp/bookfin-tb-zx7r-r1-full.log. git diff --check also passes. Original review logs remain unchanged. No native code changed, so the conditional native OCR test remains inapplicable. No device, coverage or mutation jobs, second review, push, merge, PR or ticket closure occurred. No unresolved forks remain. The supplied worktree is unchanged; its branch was externally renamed at the original base from t3/190f0858 to t3/pdf-whole-line-screens. Ticket remains in progress for parent integration.

**2026-11-10T21:23:45Z**

Parent inspected complete implementation/tests and recorded R1 reproduction/fix. Merged 9a3b5f4 with drop-cap integration a89130c; no production conflict, both ticket histories retained. Parent Nix combined run passed all 117 tests across text screens, navigation, viewport, word view, recognition/cancellation/places, fallback, quiet reading, drop caps, Trim margins and crops. Log /tmp/bookfin-text-screens-integration.log. Production viewport/text screen and regression files match reviewed/fixed child HEAD exactly. Child full suite 2572 passed/21 skipped remains evidence; parent reran affected integration checks. Explicit Text routing still awaits tb-9mcf. No device input, phone installation or coverage/mutation claim.
