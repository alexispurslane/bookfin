---
id: tb-nkz5
status: in_progress
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

**2026-11-10T19:44:52Z**

Implementation in t3/pdf-trim-margins from f674c7bc0fbfd103b9c0d2ee7d146ea0c5cf7fe3. Added the PDF-only Trim margins row under Pages in the existing glass Reading settings. ReaderSession owns the saved per-account choice and a narrow change signal; it saves the choice with text size (missing means on). Original pages and deck cards share the existing _crops gate. Explicit toggles redraw the shown page, retire stale draws, and discard old deck cards; background survey updates still cannot change a shown page. Word-column analysis/layout is unchanged. The settings content scrolls at large system text sizes. Meaningful red evidence: /tmp/tb-nkz5-default-red.log (missing switch), then /tmp/tb-nkz5-behavior-red.log (restart restored true, crop unchanged, old deck survived, 363px vertical overflow). Initial test compile/setup failures were corrected before counting red. Six feature tests and a 58-test focused regression run pass. Required format/analyze/full-test checks are in progress; no device or Pixel 8 touched. Fresh Sol xhigh review follows. Integration with tb-22fu must preserve PdfViewport.trimMargins, the original/deck _crops gate, explicit-toggle draw revision, and ReaderSettingsPanel trim data/action wiring; no word-view implementation has been copied here.

**2026-11-10T19:48:39Z**

Required format passed: 391 files, 0 changed. Required flutter analyze lib test integration_test passed with no issues after removing three warnings in the new tests. The first full flutter test completed with 2513 passed, 21 skipped, 7 failed (/tmp/tb-nkz5-full.log). All seven failures come from two existing standalone-viewport test files selecting every SingleChildScrollView: the newly scrollable Reading settings panel is mounted beside their viewport, so they selected the settings scroll view or both scroll views. Narrowed only those finders to descendants of PdfViewport; assertions still exercise the same reading positions and original/reflow behavior. Focused verification and the full rerun follow. boo-7plj did not recur in this first full run. Fresh read-only Sol xhigh reviewer launched for base..19beb5194e3f06b735b3de1db98f97ea1aa6791a; taskId node:delegated-task:command%3Amcp%3A4b943b86-5d34-488f-8357-1eef530f5087%3Adelegate-task%3Atb-nkz5-fresh-sol-xhigh-review-20261110-1. No other reviewer or nested delegate launched.

**2026-11-10T19:49:01Z**

The scoped OCR-position/navigation tests plus all six new Trim margins tests pass: 23 tests, /tmp/tb-nkz5-scroll-scope.log. The seven failures from the first full run were test selector coupling, not changed reading-position behavior.
