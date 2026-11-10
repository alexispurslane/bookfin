---
id: tb-nkz5
status: closed
deps: [tb-valc]
links: []
created: 2026-11-10T12:53:21Z
type: feature
priority: 1
assignee: Alexis Purslane
parent: boo-fval
---
# Add a Trim margins switch to the PDF Reading settings

T4 of docs/plans/pdf-word-image-reflow.md (Trimmed margins: The switch). A Trim margins switch in the glass Reading settings sheet, shown only for PDFs, on by default. Off shows the full printed page in the Original view. ReaderSession keeps it and saves it with the text size, so it lasts across runs. The word view always drops headers and folios, whatever the switch says.

## Acceptance Criteria

Behavior tests, red first: the switch shows only for PDFs and is on in a new install; turning it off shows the full page at once, and on shows the crop at once; the choice survives a restart; the word view is the same with the switch on or off; the sheet stays glass and the row stays usable at the largest system text size.


## Notes

**2026-11-10T19:28:22Z**

Sol xhigh lead launched. taskId: node:delegated-task:command%3Amcp%3Ae6a3d378-c450-4501-a47c-77e7994db5fb%3Adelegate-task%3Asol-xhigh-resume-20261110-tb-nkz5-1; childThreadId: thread:delegated-task:command%3Amcp%3Ae6a3d378-c450-4501-a47c-77e7994db5fb%3Adelegate-task%3Asol-xhigh-resume-20261110-tb-nkz5-1; clientRequestId: sol-xhigh-resume-20261110-tb-nkz5-1. Base f674c7b includes reviewed crop implementation. Fresh Sol xhigh reviewer required.

**2026-11-10T19:44:52Z**

Implementation in t3/pdf-trim-margins from f674c7bc0fbfd103b9c0d2ee7d146ea0c5cf7fe3. Added the PDF-only Trim margins row under Pages in the existing glass Reading settings. ReaderSession owns the saved per-account choice and a narrow change signal; it saves the choice with text size (missing means on). Original pages and deck cards share the existing _crops gate. Explicit toggles redraw the shown page, retire stale draws, and discard old deck cards; background survey updates still cannot change a shown page. Word-column analysis/layout is unchanged. The settings content scrolls at large system text sizes. Meaningful red evidence: /tmp/tb-nkz5-default-red.log (missing switch), then /tmp/tb-nkz5-behavior-red.log (restart restored true, crop unchanged, old deck survived, 363px vertical overflow). Initial test compile/setup failures were corrected before counting red. Six feature tests and a 58-test focused regression run pass. Required format/analyze/full-test checks are in progress; no device or Pixel 8 touched. Fresh Sol xhigh review follows. Integration with tb-22fu must preserve PdfViewport.trimMargins, the original/deck _crops gate, explicit-toggle draw revision, and ReaderSettingsPanel trim data/action wiring; no word-view implementation has been copied here.

**2026-11-10T19:48:39Z**

Required format passed: 391 files, 0 changed. Required flutter analyze lib test integration_test passed with no issues after removing three warnings in the new tests. The first full flutter test completed with 2513 passed, 21 skipped, 7 failed (/tmp/tb-nkz5-full.log). All seven failures come from two existing standalone-viewport test files selecting every SingleChildScrollView: the newly scrollable Reading settings panel is mounted beside their viewport, so they selected the settings scroll view or both scroll views. Narrowed only those finders to descendants of PdfViewport; assertions still exercise the same reading positions and original/reflow behavior. Focused verification and the full rerun follow. boo-7plj did not recur in this first full run. Fresh read-only Sol xhigh reviewer launched for base..19beb5194e3f06b735b3de1db98f97ea1aa6791a; taskId node:delegated-task:command%3Amcp%3A4b943b86-5d34-488f-8357-1eef530f5087%3Adelegate-task%3Atb-nkz5-fresh-sol-xhigh-review-20261110-1. No other reviewer or nested delegate launched.

**2026-11-10T19:49:01Z**

The scoped OCR-position/navigation tests plus all six new Trim margins tests pass: 23 tests, /tmp/tb-nkz5-scroll-scope.log. The seven failures from the first full run were test selector coupling, not changed reading-position behavior.

**2026-11-10T19:52:54Z**

Required rerun after the viewport-selector fixes: dart format --output=none --set-exit-if-changed lib test tool integration_test passed (391 files, 0 changed; /tmp/tb-nkz5-format-final.log). flutter analyze lib test integration_test passed with no issues (/tmp/tb-nkz5-analyze-final.log). Full flutter test: 2519 passed, 21 skipped, 1 failed in 2m34s (/tmp/tb-nkz5-full-final.log). The only failure is known boo-7plj: survey_session_test.dart / a reopened book goes on with the survey that it kept beside the download, line 305, expected true and received false. Its existing ticket has the recurrence evidence. All seven scroll-selector failures from the first run are resolved; no new feature test failed. No native files changed, so native OCR worker check does not apply. Awaiting the one fresh reviewer before the final ticket report.

**2026-11-10T20:00:54Z**

Fresh read-only Sol xhigh review completed for base f674c7bc0fbfd103b9c0d2ee7d146ea0c5cf7fe3 through pinned head 19beb5194e3f06b735b3de1db98f97ea1aa6791a: correctness changes-required, fulfillment changes-required, design pass. F1 (P2) confirmed by a new behavior test: successful cropped page, failed toggle-off render, no visible failure/retry (/tmp/tb-nkz5-review-f1-red.log). Fixed the shared original-page failure display to stay visible beside the retained image; Retry source page draws the requested choice without clearing the readable image, reading place, or history. All eight feature tests now pass, including a held retry and deliberate newer-before-older render completion (/tmp/tb-nkz5-review-fix-green.log). The race test was added as regression evidence, not claimed red. F2 (P2), seven broad scroll-view test selectors, was already fixed in ce7ddc23 while review ran; its focused 23-test run and later full run establish the fix, not an independent reviewer recheck. Fix-stage focused run passes 58 tests including crop stability, navigation, OCR positions, dock, and all eight feature tests (/tmp/tb-nkz5-review-fix-focused.log). Required formatting passes: 391 files, zero changes (/tmp/tb-nkz5-fix-required-format.log); required analysis passes with no issues (/tmp/tb-nkz5-fix-required-analyze.log). Full suite is running. Exactly one reviewer used; no additional delegates, native changes, coverage/mutations, or device work.

**2026-11-10T20:02:51Z**

Fix-stage required full flutter test passes: 2522 passed, 21 skipped, zero failures in 2m02s (/tmp/tb-nkz5-fix-required-full.log). Known boo-7plj did not recur in this final run; its prior 2519-pass/21-skip/one-failure occurrence remains recorded honestly in this ticket and boo-7plj. Required format and analysis also pass after the production fix. Both review findings are resolved with behavior evidence; the competing-render coverage gap now has deliberately reversed completion order. The reviewer verdicts remain pinned to 19beb519 and are not represented as a second independent pass after these self-fixes. No forks. Parent owns integration, ticket closure, coverage, mutation testing, and Android/device acceptance. Preserve trim preference/signal/storage, settings callback wiring, _crops gating for Original and deck images, explicit-toggle stale-render rejection, and the retained-image failure/retry path when combining tb-22fu.

**2026-11-10T20:04:49Z**

Parent inspected implementation and both review resolutions, including failed replacement rendering and reversed completion regression. Merged with only ticket-note conflicts, retaining all notes and the integrated boo-7plj fix. Combined nine-file reader suite passed all 110 tests. Log /tmp/bookfin-trim-integration.log. No additional device install yet; physical verification will accompany the pending Nihil Unbound crop repair.

**2026-11-10T20:10:25Z**

User acceptance: the user verified on the Pixel 8 that the Trim margins toggle works.
