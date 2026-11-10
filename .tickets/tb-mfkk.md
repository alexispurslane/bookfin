---
id: tb-mfkk
status: in_progress
deps: [tb-22fu]
links: []
created: 2026-11-10T02:33:42Z
type: feature
priority: 1
assignee: Alexis Purslane
parent: boo-fval
---
# Select, copy, find and read word images in reflowed PDFs

W8 of docs/plans/pdf-word-image-reflow.md (The text under the images). Carets are characters of the reading text, through the text attachment. A point maps to a caret by its share of a piece, evenly over the piece's characters; highlights are the covered parts of target rectangles. Before a scanned page's text attaches, selection and highlights do nothing. Extract the selection event handling that the EPUB page (lib/reader/epub/selection.dart) and the word screen share into one selectable that takes four questions, or keep two and write why. Search hits open their screen. Screen readers read one node per paragraph. Expose the rectangles of a character range for read-aloud (t0-t799).

## Acceptance Criteria

Behavior tests, red first: a long press selects the word under the finger; a long press before the text attaches selects nothing; handles move by characters; copy gives the reading text of the selection; a piece with an empty range is never selected; a search hit opens the screen that holds it; a screen reader reads each paragraph's reading text. EPUB selection tests still pass.

## Notes

**2026-11-10T20:32:18Z**

Launched from integrated base 2ef6bfa with codex/gpt-6.1-sol reasoningEffort=xhigh. taskId: node:delegated-task:command%3Amcp%3Ae6a3d378-c450-4501-a47c-77e7994db5fb%3Adelegate-task%3Asol-xhigh-word-followup-20261110-tb-mfkk-1; childThreadId: thread:delegated-task:command%3Amcp%3Ae6a3d378-c450-4501-a47c-77e7994db5fb%3Adelegate-task%3Asol-xhigh-word-followup-20261110-tb-mfkk-1; clientRequestId: sol-xhigh-word-followup-20261110-tb-mfkk-1. Separate T3 worktree; lead implements, one fresh read-only Sol xhigh reviewer, lead fixes. Parent integrates/closes and owns hardening. No physical-device UI input. Launch state: running; branch pending report.
**2026-11-10T21:01:13Z**

Implementation in the supplied t3/pdf-word-image-selection worktree, review base 2ef6bfa8faa3e13958c4cd7eda703cbb3a5d5d4f. EPUB and word images now use ReaderSelection for the same Flutter selection events, handles, selected-content reporting and painting. The four geometry/text questions stay format-specific; coordinate extent, ordering and offsets name each format's caret system. ReaderCopyArea and ReaderTapArea also share the existing EPUB interaction path. The PDF viewport controller owns clipboard writes and tap/page actions. The word render object owns ephemeral selection. PdfWordScreens publishes text only with the displayed column/screen and the original text attachment. Paragraph preparation and region range indexing run through the book's off-isolate hop. Paragraph boundaries reuse column layout's paragraph rule. Character range rectangles are exposed by WordScreenText.rectsFor for read-aloud. No text representation, saved-place, crop, band-render, settings enum, text-screen or drop-cap policy was replaced. The existing adaptive Copy toolbar remains unchanged; follow-up t4-t67u records its pre-existing lack of shared glass styling.

**2026-11-10T21:12:38Z**

Red-green evidence in /tmp/bookfin-tb-mfkk:
- red-complete.log: Copy was absent after long press; no paragraph reading-text node existed. The pre-attachment no-selection test passed. Test setup reference/cleanup errors were corrected before this meaningful red run.
- focused-analyze.log: after selection cleared, the next page tap expected one controls callback but got zero. ReaderTapArea now reuses the EPUB recognizer inside the selection region. Its PDF regression and the EPUB gesture tests pass.
- attachment-identity-red.log: worker preparation returned a different PdfText instance. The worker now returns only paragraph/region ranges (WordTextPlan); the controller binds that plan to the original AttachedText. attachment-identity-green.log: all 56 focused tests passed, including original-object identity, delayed rendering, saved places and EPUB behavior.
- handle-boundary-red.log: a trailing handle at the shared character of two printed lines expected (100,20) logical pixels on the first line but got (0,50) on the second. The handle query now chooses the selected side of that character. handle-boundary-green.log: all 9 word-selection tests passed.
- An intermediate analyzer run reported 14 issues (imports, nullable generic carets and inferred nullable paragraph records). All were fixed; analyze-fixed.log reports no issues.
- First required full run: format checked 398 files with zero changes; analysis reported no issues; full Flutter tests passed 2577 tests with 21 skips. A second full run includes the added shared-character handle test and fix.
No native code changed, so the conditional native OCR script does not apply. No coverage, mutation, device or browser work ran. No settings enum, text-screen or drop-cap work was taken from the concurrent leads. Ticket stays in progress for parent integration and closure.

**2026-11-10T21:16:56Z**

Final build-stage checks (all through nix develop):
- dart format --output=none --set-exit-if-changed lib test tool integration_test: PASS, 398 files, zero changes (2.20 seconds), /tmp/bookfin-tb-mfkk/final-format.log.
- flutter analyze lib test integration_test: PASS, no issues (4.2 seconds), /tmp/bookfin-tb-mfkk/final-analyze.log.
- flutter test --concurrency=2 --reporter expanded: PASS, 2578 passed and 21 skipped (4 minutes 2 seconds), /tmp/bookfin-tb-mfkk/final-full-test.log. Skips are opt-in EPUB benchmarks/trials or absent trial inputs, not word-selection acceptance tests.
Flutter emits the host warnings that iphoneos and iphonesimulator SDKs are not installed. They do not fail these checks; no iOS/device claim is made. The conditional native OCR script is not applicable because no native code changed. No user-visible fork remains. Ready for the one authorized fresh review stage; not yet an integration verdict.

**2026-11-10: Independent review and R1 resolution**

The one authorized read-only reviewer assessed original base 2ef6bfa8faa3e13958c4cd7eda703cbb3a5d5d4f through built HEAD b9c5ad8dc3ddbbb101d9bc8d5f222ce347a0e102. Preserve its original verdicts: correctness CHANGES REQUIRED, fulfillment CHANGES REQUIRED, design PASS, overall CHANGES REQUIRED. It inspected the source, complete diff and supplied test logs; it did not edit, build, test or use a device. No second reviewer was started.

R1 (P2/medium, lib/reader/pdf_word_view.dart, PdfWordScreens._publishText): attachment completed during a pending turn or column-size change, but publication required the displayed column/screen to match the pending request. The still-visible screen therefore had no selection text or paragraph labels. The reviewer predicted this statically; the builder reproduced both cases before the fix.

Resolution: keep the displayed-source-page check and original attachment binding, but publish against the actual displayed column/screen without requiring the pending request to match. Two held-band regressions verify original text/attachment identity, displayed geometry, range rectangles, paragraph reading-text labels, long press, selection rectangles and clipboard Copy before the requested images arrive. They also check ownership after the pending display appears. No saved-place or image-render policy changed.

Evidence, all through nix develop:
- /tmp/bookfin-tb-mfkk/r1-red.log: both new domain regressions failed because selectable text was null after attachment. No syntax/reference failure counted as red.
- /tmp/bookfin-tb-mfkk/r1-green.log: behavior assertions passed, but both tests failed cleanup because a SemanticsHandle remained active. Explicit disposal before test completion fixed the test lifecycle; this cleanup failure is not a production defect.
- /tmp/bookfin-tb-mfkk/r1-green-fixed-cleanup.log: both pending-turn and pending-size-change regressions passed.
- /tmp/bookfin-tb-mfkk/r1-focused.log: 59 PDF view, PDF selection, word selection and EPUB selection tests passed.

R1 is resolved with executed red-green evidence, not a new independent review verdict. Remaining review gaps: Android accessibility/phone acceptance and coverage/mutation testing belong to the parent; the paragraph tests do not independently count every paragraph node across all screens. No unresolved user-visible fork was found.

**2026-11-10: Parent integration compatibility notes**

Inspected dfeb229283c7afb931d2fb66b6548811d92ad3d0 and its implementation commit 84fdc4acaa24872a6e8c4d08e800788549a904f9 without resetting, merging or changing this branch. dfeb229 itself only records the passing boo-wfg1 review. The implementation changes lib/reader/pdf_word_view.dart and lib/reader/word_pages.dart.

- Keep the flash fix's retainShown/clearShown cancellation and its assignment of _displayed plus _keep before notifying _shown. This ticket does not change word_pages.dart.
- Keep the flash fix's screen-listenable drawing even when showing is false. showing means target-page readiness, not whether retained words are visible.
- Resolve the _screen conflict by putting WordSelectable(text: screens.text, key: selectionKey, child: WordScreenView(...)) inside the flash fix's displayed-screen ValueListenableBuilder and _DevicePixelOrigin(ratio: shown.settings.devicePixelRatio). Do not restore image-only paragraph semantics or use requested settings for retained-word pixel alignment.
- Keep this ticket's _text.value = null in open, leave and _giveUp. During a new source-page request this clears selection and paragraph labels on retained previous-page words. It deliberately does not make retained words selectable using the unseen target's text. Preserve the flash fix's touch guard while showing is false.
- Keep the R1 publication guard shown.page == open.page, and build WordScreenText only from shown.column.column and shown.screen. Do not drop the source-page guard when reconciling the display-retention changes. Same-page pending turns/size changes receive attached text; previous-source-page retained words do not receive the target page's attachment.
- Inspected whole-line Text commit 9a3b5f40f5d92ebb82c80d2297cbdbf940d9bfec. Preserve its text layout/turn changes when resolving pdf_viewport.dart; layer this ticket's selection-aware Copy/tap/swipe wiring around the word branch. On the parent's combined branch, update the pre-existing fallback assertion in test/reader/pdf_word_view_test.dart from SingleChildScrollView to PdfTextView, with its import. This isolated branch has the older text view and has not imported or implemented that concurrent ticket.

Combined integration should verify that selected retained words clear on a source-page request, no long press/Copy resolves those words against the pending target, and selection resumes only with the matching displayed page's attachment. No combined-branch/device validation is claimed here.

**2026-11-10: Final post-review checks**

All required checks were rerun after the R1 fix, through nix develop, one heavy command at a time:
- dart format --output=none --set-exit-if-changed lib test tool integration_test: PASS, 398 files, zero changes (1.90 seconds), /tmp/bookfin-tb-mfkk/r1-final-format.log.
- flutter analyze lib test integration_test: PASS, no issues (3.4 seconds), /tmp/bookfin-tb-mfkk/r1-final-analyze.log.
- flutter test --concurrency=2 --reporter expanded: PASS, 2580 passed and 21 skipped (245 seconds shell elapsed), /tmp/bookfin-tb-mfkk/r1-final-full-test.log. Skips remain the opt-in EPUB benchmarks/trials or absent trial inputs.
- git diff --check: PASS. No native code changed, so bash test/native/ocr_worker_test.sh is not applicable.

The host still emits missing iphoneos/iphonesimulator SDK warnings; they do not fail the checks. No device, browser, coverage or mutation job ran. Original independent verdicts remain recorded above, and every review finding has an executed resolution. Ready for parent integration, not independently re-reviewed or accepted on a phone. Keep the ticket in progress until the parent merges and closes it.


**2026-11-10: Parent integration regression**

Integrated with retained word screens, whole-line Text screens, drop caps, Original crop and Trim margins. The added behavior test selects page 2, holds page 3 image rendering after its text attaches, and presses the retained page 2 pixels again. Selection must clear while those pixels remain readable, and resume with the matching page 3 text only when its images arrive.

RED: /tmp/bookfin-selection-integration-focused.log records 117 passed and one failure: Flutter reopened its existing menu with no selectable content, and ReaderCopyArea requested nonexistent selection anchors (startGlyphHeight null check). This is a real integration failure, not a fixture/reference error.

GREEN: the shared ReaderCopyArea returns an empty widget when Flutter supplies no menu actions, before requesting anchors. This fixes the empty-content menu path for PDF and EPUB without catching internal errors or adding a second selection state. /tmp/bookfin-selection-integration-green.log records all 118 focused tests passed. Existing EPUB Copy, handles and page gestures remain covered. This parent fix has executed red/green evidence; no additional independent review is claimed.

**2026-11-10T21:48:37Z**

Parent final combined checks through nix develop: 118 focused tests passed; format checked 401 files with zero changes; analyze reported no issues; full flutter test --concurrency=2 --reporter expanded passed 2616 tests with 21 skips in 3m52s. Logs: /tmp/bookfin-selection-integration-{green,format,analyze,full}.log. git diff --check passed. Native implementation unchanged; conditional native OCR worker check not required. Device acceptance and post-acceptance hardening remain pending.
