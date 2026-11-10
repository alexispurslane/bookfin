---
id: tb-valc
status: in_progress
deps: [tb-lnak]
links: []
created: 2026-11-10T12:53:21Z
type: feature
priority: 1
assignee: Alexis Purslane
parent: boo-fval
---
# Trim the margins, running header and folio of the PDF Original view

T3 of docs/plans/pdf-word-image-reflow.md (Trimmed margins: The Original view). PdfViewport's original page shows the page's crop: it renders the page at the screen width divided by the crop's share of the page width (within the existing render limits) and draws only the crop, fitted to the screen. A page never changes its crop while it shows: a crop that becomes known later applies from the next page the reader shows. A page whose crop is not known waits up to 300 ms for it before its first draw, then shows uncropped. When a page shows, the next page in the reading direction gets its analysis first in the survey. Pinch zoom and pan work on the cropped page as today, up to 6 times. The scrub deck cards use a known crop and never wait for one.

## Acceptance Criteria

Behavior tests, red first: a body page shows only its content, without margins, header and folio; two body pages of one side show their text at the same size and place; a wide-table page shows all of its table; a page shows uncropped until its crop is known and keeps its look until the next turn; a page whose crop is ready within 300 ms shows cropped from its first frame; the next page's crop is ready before a turn in the normal case; pinch zoom and pan still work, and a swipe on a zoomed page moves it; the deck shows cropped cards when crops are known. No crop work runs on the UI isolate.


## Notes

**2026-11-10T17:20:38Z**

Built: the Original view shows each page's crop (PdfViewport._draw and preview, through _crops, the one place for the Trim margins switch of tb-nkz5); BookSurvey.cropWithin waits up to 300 ms for a jump, scrub or open, and gives null at once when no crop can come; BookSurvey.follow, called by ReaderSession.acceptAddress, surveys the shown page and the next one first; _drawPage renders wider by the crop's share and decodes only the crop's rows with a row stride. Tests: test/reader/pdf_crop_test.dart, book_survey_test.dart, survey_session_test.dart. Evidence: docs/evidence/reader/trimmed-margins/. New work: ta-go9x, ta-3g8x.

**2026-11-10T19:17:07Z**

Recovery: cherry-picked b4ec646 onto review base 9bf71644 as bca1de6 without conflicts; retained the newer word renderer and scanned-paper decision. Reproduced backward-priority gap with a failing session test (actual [1,5,6], expected [1,5,4]), then fixed direction ownership in BookSurvey.follow. Same-page reports retain direction; forward reversal covered. Focused crop/survey/session/viewport/book-crop/word-renderer run: 79 passed. Added exact 299/300 ms crop-wait boundary characterization; passed first run, not claimed as original red evidence. Existing emulator screenshots reused without rebuilding or touching any device. Format check and analyzer passed; full suite and fresh review follow.

**2026-11-10T19:20:02Z**

Required checks, 2026-11-10, through nix develop: dart format --output=none --set-exit-if-changed lib test tool integration_test passed (390 files, zero changes); flutter analyze lib test integration_test passed (no issues); full flutter test --reporter expanded passed (2514 tests, 21 skipped, 2m53s). Known intermittent boo-7plj survey reopen test passed in this run. iPhone SDK probe warnings did not fail checks. No native files changed; native OCR worker script not required. No coverage/mutations or device actions. Fresh shared Sol xhigh reviewer is running; leave ticket in_progress for parent integration.
