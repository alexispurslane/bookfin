---
id: tb-valc
status: closed
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

**2026-11-10T19:09:24Z**

Resumed with GPT 6.1 Sol xhigh. taskId: node:delegated-task:command%3Amcp%3Ae6a3d378-c450-4501-a47c-77e7994db5fb%3Adelegate-task%3Asol-xhigh-resume-20261110-tb-valc-1; childThreadId: thread:delegated-task:command%3Amcp%3Ae6a3d378-c450-4501-a47c-77e7994db5fb%3Adelegate-task%3Asol-xhigh-resume-20261110-tb-valc-1; clientRequestId: sol-xhigh-resume-20261110-tb-valc-1. Separate T3 worktree; build/recovery, fresh Sol xhigh review, then fixes. Parent integrates and closes.

**2026-11-10T17:20:38Z**

Built: the Original view shows each page's crop (PdfViewport._draw and preview, through _crops, the one place for the Trim margins switch of tb-nkz5); BookSurvey.cropWithin waits up to 300 ms for a jump, scrub or open, and gives null at once when no crop can come; BookSurvey.follow, called by ReaderSession.acceptAddress, surveys the shown page and the next one first; _drawPage renders wider by the crop's share and decodes only the crop's rows with a row stride. Tests: test/reader/pdf_crop_test.dart, book_survey_test.dart, survey_session_test.dart. Evidence: docs/evidence/reader/trimmed-margins/. New work: ta-go9x, ta-3g8x.

**2026-11-10T19:17:07Z**

Recovery: cherry-picked b4ec646 onto review base 9bf71644 as bca1de6 without conflicts; retained the newer word renderer and scanned-paper decision. Reproduced backward-priority gap with a failing session test (actual [1,5,6], expected [1,5,4]), then fixed direction ownership in BookSurvey.follow. Same-page reports retain direction; forward reversal covered. Focused crop/survey/session/viewport/book-crop/word-renderer run: 79 passed. Added exact 299/300 ms crop-wait boundary characterization; passed first run, not claimed as original red evidence. Existing emulator screenshots reused without rebuilding or touching any device. Format check and analyzer passed; full suite and fresh review follow.

**2026-11-10T19:20:02Z**

Required checks, 2026-11-10, through nix develop: dart format --output=none --set-exit-if-changed lib test tool integration_test passed (390 files, zero changes); flutter analyze lib test integration_test passed (no issues); full flutter test --reporter expanded passed (2514 tests, 21 skipped, 2m53s). Known intermittent boo-7plj survey reopen test passed in this run. iPhone SDK probe warnings did not fail checks. No native files changed; native OCR worker script not required. No coverage/mutations or device actions. Fresh shared Sol xhigh reviewer is running; leave ticket in_progress for parent integration.

**2026-11-10T19:25:50Z**

Fresh review complete: one shared Codex gpt-6.1-sol reviewer at xhigh passed correctness, fulfillment and design independently, with no findings or material acceptance gaps. Reviewed base 9bf71644c0639f5fc201b756fb938eb1137b75be through application/test head 95602865332e018c6287cb3245dfbfe03e8a12d5; later commits change only evidence and tickets. Reviewer inspected existing logs and seven original screenshots, performed no build/test/device actions, and started no agents. Review: <t3-thread://v2/38d3e8fa-8572-4c2a-8a3b-2eb7c344dfce/thread:delegated-task:command%3Amcp%3A3ee24ca5-4cc2-4ee8-a396-8d5f5293a1f1%3Adelegate-task%3Atb-valc-recovery-review-20261110-1>. Ready for parent integration; ticket remains in_progress and was not merged, pushed or closed.

**2026-11-10T19:27:41Z**

Parent integration: inspected full production diff and evidence. Merged with only a ticket-note conflict, preserving both notes. Focused six-file suite: 78 passed, 1 failed in the existing boo-7plj survey resume test at survey_session_test.dart:305 (kept survey file absent). All crop tests passed. Dedicated Sol lead is fixing boo-7plj; prior full branch suite passed 2514 with 21 skipped.

**2026-11-10T19:29:28Z**

Phone update: normal ARM64 debug APK built through nix develop --command bash tool/bookfin build-android from source commit 2a73abc; native package, OCR package, APK signing and alignment verification passed. adb install -r succeeded on the Pixel 8 over Wi-Fi. Launched via T3 bound agent-device; screenshot confirmed app Library screen. No private data reset. Crop reading acceptance on the physical phone remains user testing; prior emulator evidence retained.
