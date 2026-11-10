---
id: tb-9mcf
status: in_progress
deps: [tb-22fu]
links: [te-rtok]
created: 2026-11-10T02:33:42Z
type: feature
priority: 1
assignee: Alexis Purslane
parent: boo-fval
---
# Choose original pages, word view or text view for PDFs in Reading settings

W7 of docs/plans/pdf-word-image-reflow.md (The switch to the text view, decision 1 of 2026-11-10). Replace ReaderSession's reflow bool with one enum of three values that lasts for the run of the app (t9-3n2m). The user chose design A: the Pages row in the glass Reading settings sheet has three segments, Original, Page words and Text. Make the shared PillChoice usable at large system text sizes for every caller: when its segments do not fit the width, it first hides the icons and keeps the full labels, and if they still do not fit, it stacks the segments in a column in the same pill shape, each with a touch target of at least 48 by 48 logical pixels. Labels are never cut or shortened.

## Acceptance Criteria

Behavior tests, red first: the choice lasts through closing and opening books in one run and a new run starts on the original page; the Pages row shows Original, Page words and Text, and only for PDFs; at the largest system text size on a narrow phone, the row first drops its icons and then stacks, and every label stays whole and every segment can be tapped; the Theme row gets the same behavior; turning reflow on shows the word view; the text view shows the reading text in the reader's font. The sheet stays glass. Existing reflow tests pass with the enum.


## Notes

**2026-11-10T21:09:14Z**

Implementation in supplied worktree /Users/alexispurslane/.t3/worktrees/bookfin/t3-afa2407f, branch t3/afa2407f, review base 2ef6bfa8faa3e13958c4cd7eda703cbb3a5d5d4f (includes 1330132). Session API: PdfPageView {original, pageWords, text} in pdf.dart; ReaderSession.pdfView, pdfViewChanges and setPdfView. PdfViewport takes view; ReaderSettingsPanel takes pdfView/onPdfViewChanged. The shared PillChoice takes full-label PillSegments for Pages, Theme and density. It hides icons before stacking, constrains stacked labels to the actual width, retains 48-logical-pixel targets, and uses bounded rounded ends so large labels cannot be clipped. Text uses Source Serif 4 through the existing scroll renderer. Pagination, selection and drop caps remain with their assigned leads. No native code, device operation, coverage or mutation work.

**2026-11-10T21:09:14Z**

Red proof: /tmp/tb-9mcf-red-choices.log has 3 expected behavior failures (missing Page words/Text, icons not hidden, no vertical large-text choice); /tmp/tb-9mcf-red-session.log has 2 expected behavior failures (Theme does not stack and Text cannot be chosen). The first session command used --plain-name with a regex, exited 79 with no matching tests, and was corrected to --name before counting red. Later /tmp/tb-9mcf-red-rounded-ends.log reproduced Original clipping. A first clipping fix still failed the same assertion because Flutter vertical segments kept an over-wide intrinsic label; limiting the label width resolved it. Focused final shared-choice/settings tests: 21 pass (/tmp/tb-9mcf-green-rounded-ends.log). Crop/word/native routing/trim regression group: 63 pass (/tmp/tb-9mcf-focused-routing.log). Synthetic 320-logical-pixel-wide Cream/Night test renders at text scales 1 and 3.2 were inspected using bundled Outfit and Source Serif 4. These are widget-renderer captures, not Android acceptance. The temporary capture test was removed.

**2026-11-10T21:09:14Z**

Verification history: the initial analyzer found one old PdfViewport.reflow assertion at test/reader/screen_rebuild_test.dart:143; it now checks view. The first full suite had 2562 passes, 21 skips and 4 failures due to old Reflow text selectors: reader_gestures_test.dart (a PDF page a swipe moves reflowed text on by about a screen); pdf_navigation_test.dart (repeated original-page requests share one pending draw and release its image; Previous from a reflow page boundary returns to the preceding final viewport; Previous onto a short page saves its visible beginning for larger-text restoration). Those selectors now choose Page words. Their focused rerun passed all 16 tests (/tmp/tb-9mcf-selector-fixes.log). The next full suite passed 2566 tests with 21 skips (/tmp/tb-9mcf-full-tests-before-rounded-fix.log). Final required checks are being rerun after the additional rounded-end clipping fix. Flutter native hooks print missing iphoneos/iphonesimulator SDK warnings on this host; tests still run. Native worker script is not required because native code is unchanged.

**2026-11-10T21:12:38Z**

Additional intermediate failure, not a red proof: one focused run during the API migration had two loading failures from remaining removed reflow arguments/getters. After completing the enum migration, the same 27-test core group passed (/tmp/tb-9mcf-green-core.log). No syntax or missing-reference failure is counted as red. The successful final clipping group additionally covers the actual painted rounded outline and verifies that stacked buttons stay within the choice width. The minimum target, segment padding, icon size and icon gap each have one definition inside PillChoice.

**2026-11-10T21:13:33Z**

Final build gate passed after the clipping fix, all through nix develop: dart format --output=none --set-exit-if-changed lib test tool integration_test (395 files, 0 changes, exit 0; /tmp/tb-9mcf-format.log); flutter analyze lib test integration_test (no issues, exit 0; /tmp/tb-9mcf-analyze.log); flutter test --concurrency=2 --reporter expanded (2566 passed, 21 skipped, 0 failed, exit 0; /tmp/tb-9mcf-full-tests.log). No native changes, so bash test/native/ocr_worker_test.sh is not required. No unresolved product forks. Ready for the one authorized fresh read-only review; ticket remains in progress until parent integration.

**2026-11-10T21:40:00Z**

The one authorized fresh review assessed original base 2ef6bfa8faa3e13958c4cd7eda703cbb3a5d5d4f through built HEAD 624d684c07eeaca31065500e5dabefc5afe4505a. Preserve its original verdicts: correctness changes_required, fulfillment changes_required, design pass, overall changes_required. Its only finding was F1 (P2): at width 320 logical pixels and text scale 3.2, the production Settings density choice remained in ListTile.trailing, whose width and height constraints prevent the shared choice from stacking safely. The reviewer made no edits and ran no builds, tests or device actions. No second reviewer is authorized or started.

**2026-11-10T21:40:00Z**

F1 was reproduced before its production fix by a signed-in SettingsTab behavior test. The expected failure was "Trailing widget consumes the entire tile width (including ListTile.contentPadding)." at lib/settings/screen.dart:97 (/tmp/tb-9mcf-F1-red.log, exit 1). The density heading and choice now occupy one full-width, content-height column; PillChoice still owns all fitting decisions. The regression test checks the visible heading, both complete labels inside the painted outline, stacked targets at least 48 by 48 logical pixels, both real taps, and saved Compact/Spacious choices. The focused Settings/shared-choice/Reading-settings group passed all 22 tests (/tmp/tb-9mcf-F1-green.log, exit 0). A first test-fixture attempt could not find the lazy-built offscreen choice; a later attempt tapped before the scroll had painted. Neither is counted as red proof; the fixture now scrolls to the heading and waits for painting.

**2026-11-10T21:40:00Z**

Synthetic density captures at width 320 and text scale 3.2 were inspected in both themes using the bundled Outfit font and pinned Material icon font (/tmp/tb-9mcf-density-light-3.2.png and /tmp/tb-9mcf-density-dark-3.2.png). The capture test passed both renders (/tmp/tb-9mcf-F1-render-probe.log) and was removed before final checks. Its first attempt failed because fonts/MaterialIcons.otf is absent from the test asset bundle (/tmp/tb-9mcf-F1-render-probe-first.log); loading the pinned SDK font resolved that. A second capture attempt hung after writing its first image and was interrupted only through its own runner PID; shutdown printed "Cannot close sink while adding stream" and "Cannot add event while adding stream" (/tmp/tb-9mcf-F1-render-probe-interrupted.log). Running capture work wholly outside fake test time resolved the probe. None of these test-renderer captures is Android acceptance. The parent and user retain phone acceptance and hardening.

**2026-11-10T21:46:15Z**

F1 is verified resolved; its original review verdict is not rewritten. Final required checks after the fix all passed through nix develop: dart format --output=none --set-exit-if-changed lib test tool integration_test (395 files, 0 changes, exit 0; /tmp/tb-9mcf-F1-format.log); flutter analyze lib test integration_test (no issues, exit 0; /tmp/tb-9mcf-F1-analyze.log); flutter test --concurrency=2 --reporter expanded (2567 passed, 21 skipped, 0 failed, exit 0; /tmp/tb-9mcf-F1-full-tests.log). Flutter still prints missing iphoneos/iphonesimulator SDK warnings; these do not fail the tests. No native code changed, so bash test/native/ocr_worker_test.sh is not required. No device input, coverage, mutation jobs, pushes, merges or ticket closure. Actual T3 branch is t3/pdf-view-modes-settings, in the original supplied worktree. No unresolved findings or product forks. Original crop/trim/retry/zoom behavior and the existing scrolling Text renderer remain unchanged by this resolution; Text pagination, word selection and drop caps remain with their assigned leads.
