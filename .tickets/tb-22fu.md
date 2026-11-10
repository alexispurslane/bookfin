---
id: tb-22fu
status: in_progress
deps: [tb-xjfi]
links: [t6-1luw]
created: 2026-11-10T02:33:42Z
type: feature
priority: 1
assignee: Alexis Purslane
parent: boo-fval
---
# Show the word view in the PDF viewport: waiting for words and text, places, turns and failure

W6 of docs/plans/pdf-word-image-reflow.md (The text under the images; Waiting, turns, the scrub deck and the scrub bar). Wire PdfWordPages into PdfViewport. One waiting flag covers the text layer text or the layout record, the analysis, the layout and the first bands, with the original page under the progress line. On a scanned page the words show after the layout pass, and the progress line stays until the text attaches. Places come from the first piece with a range on the shown screen, or the page itself before the text. A saved place inside a page without text is kept, not overwritten; when the text attaches and the person has not turned or touched, the screen that holds it shows. Turns follow decision 2 of 2026-11-10: a swipe shows the next whole-line screen, a swipe past a page's last screen shows the next page's first screen, back from a first screen shows the previous page's last screen, and a vertical drag does nothing. Failures follow the doc. The scrub deck keeps original pages. Until W7 lands, reflow shows the word view.

## Acceptance Criteria

Behavior tests, red first: on a scanned page the first word screen shows before recognition ends and the progress line stays until the text attaches, with no change of screen; before the text, a saved place inside the page opens the first screen and stays saved, and after the text it opens its screen if the person did not move; the place of a screen is its first word and reopening shows the same word; a place from the text view opens on the screen that holds it, and the reverse; turns pass between pages' first and last screens; a vertical drag changes nothing; the deck starts no layout pass and no recognition; a failed layout pass or analysis falls back as the doc says. Engine rule 1 holds.

## Notes

**2026-11-10T17:00:20Z**

From tb-m8xo: until the book profile freezes (about the first minute of a new book), ReflowPage.column shows running headers and folios; a column made after the freeze leaves them out. Keep the shown page's column until a turn or a text size change, as the Original view keeps its crop, so the shown screen never changes under the reader.

**2026-11-10T17:04:29Z**

From tb-xjfi: PdfWordPages(book) is the data source, one per viewport. column(page, settings) gives the WordColumn (column and band plans) or null without word geometry. show(page, settings, screen, forward:) shows a screen in the shown listenable once its bands are ready, keeps the old screen until then, and completes after the next screen is rendered ahead. WordScreenView(screen: pages.shown) draws it with the theme's tints and fills its constraints. Place it at a whole device pixel (for example a left margin of round(20 * ratio) / ratio), or level words lose their one-to-one pixels. WordSettings carries the column width, text size, screen height and device pixel ratio. The sprites of a screen are placed from the screen's top (column.screenTop(screen)) and the column's left edge, so the view draws a screen at its own origin.

**2026-11-10T19:09:25Z**

Resumed with GPT 6.1 Sol xhigh. taskId: node:delegated-task:command%3Amcp%3Ae6a3d378-c450-4501-a47c-77e7994db5fb%3Adelegate-task%3Asol-xhigh-resume-20261110-tb-22fu-1; childThreadId: thread:delegated-task:command%3Amcp%3Ae6a3d378-c450-4501-a47c-77e7994db5fb%3Adelegate-task%3Asol-xhigh-resume-20261110-tb-22fu-1; clientRequestId: sol-xhigh-resume-20261110-tb-22fu-1. Separate T3 worktree; build/recovery, fresh Sol xhigh review, then fixes. Parent integrates and closes.
**2026-11-10T19:29:18Z**

Recovery in /Users/alexispurslane/.t3/worktrees/bookfin/t3-e4690732, branch t3/e4690732, base 9bf71644. Copied old tracked partial edits and two untracked word-view files through patches; old checkout remains untouched. The recovered scanned-before-recognition widget test failed meaningfully on the base (no word screen), then passed after viewport wiring. Recovered tests needed cleanup that pumps pending native work and nonblocking cross-page navigation. New tests exposed and fixed pre-geometry touches causing a late saved-place jump, fractional global pixel origins, and switching regressions. Inspected cropped Original merge 2a73abc2596e4f4fac1c477e7878843c3ec16e15 without merging: integration must retain its _turned/_load(turned:)/crop wait/_drawPage changes in _draw and preview; preserve _startWords and word-screen turn precedence. Constructor unchanged. No edits to BookSurvey.follow or ReaderSession.acceptAddress; word places still report through onAddress so parent direction tracking remains authoritative. Upcoming trim-toggle constructor wiring must be preserved during parent integration.

**2026-11-10T19:42:49Z**

Additional red-green evidence: touch-preserve-red.log failed with saved character 1350 replaced by 0 before text; shown-place-red.log failed with requested character 793 reported while character 397 screen was still shown; cached-touch-red.log failed because cached text jumped after a pre-geometry touch. Fixed distinct touch/turn tracking, actual displayed-screen address reporting, and touch suppression during first layout. Focused behavior-final.log: 24 passed. OCR cancellation fixture now explicitly models text-only fallback (no word geometry); its previous failures were caused by the new layout phase reaching its recognition-only native stub, not proof of duplicate production recognition. Added request identity checks around word-opening fallback. Actual current branch is t3/recover-word-image-reflow (same checkout/base); no checkout changes performed. boo-5fcg belongs to another lead: preserve usable embedded text and existing saved addresses when parent integrates geometry fallback. This branch changes only ReflowPage column planning in pdf.dart, not native geometry or representation identity.

**2026-11-10T19:50:32Z**

Required final checks: dart format --output=none --set-exit-if-changed lib test tool integration_test passed (392 files, 0 changed); flutter analyze lib test integration_test passed with no issues; full flutter test --reporter expanded rerun passed (2519 passed, 21 skipped, 0 failed, 2m37s); bash test/native/ocr_worker_test.sh passed. First final full run had only known boo-7plj (2518 passed, 21 skipped, 1 failed), which passed alone then in the full rerun. Focused behavior-final.log: 24 passed. Earlier focused-final.log: 43 word-page/view/running-line tests passed. Android OCR preparation, debug ARM64 build and install passed. Actual scan/text-layer emulator captures and reproduction/limits are in docs/evidence/reader/word-view/README.md. Evidence fixture server stopped. No coverage or mutation work performed. Ready for the required fresh read-only review.

**2026-11-10T20:16:59Z**

Fresh read-only Sol review of 9bf71644..80f6f19 returned changes-required for correctness, fulfillment, and design, with no unverified assessments. F1 reproduced twice: returning 20→30→20 after profile freeze and leaving/returning to a cached page restore running lines (review-f1-red.log). Fixed profile-aware reusable column keys, explicitly pinned selected-column lifetime, and band keys tied to column identity; F1 focused passed. F2 reproduced wrong displayed places for overlapping size changes and size changes during a held turn (review-f2-red-corrected.log: expected screen 1/2 but got 0/4). Fixed relayout to capture actual displayed WordScreen, not pending requested state; both tests pass. F3 reproduced six swallowed internal AssertionErrors at geometry, analysis, column, bands, attachment, and render-ahead (review-f3-red.log), plus a replaced-request Error silently ignored (review-f3-replaced-red.log). Operational Exceptions still fall back; internal failures now complete the initial wait with its original error/stack or propagate after first display, including ahead/replaced work. Attachment test needed fake-time pumping with held bands; one intermediate focused command was cancelled through its own session after runAsync-only waiting deadlocked, not a production failure. Final combined focused run fix-focused-final.log: 65 passed. No second reviewer launched; user permits exactly one. Parent integration updates observed without merging: fd722db trimMargins constructor/default, crop gating, draw revision and retained-image retry must remain; b901b6c native geometry+attachment pair, off-page-label omission, extracted-text identity, and rotated-page refusal must remain. Our pdf.dart changes still only affect ReflowPage column planning. Main now owns boo-7plj wait fix; this branch does not duplicate it.

**2026-11-10T20:23:39Z**

Final fix validation widened to legacy reader fixtures. The first post-fix full run had 2520 passed, 21 skipped, 9 failures because the shared HeldPdf text-only fake inherited a geometry path whose supplies deliberately throw StateError. These internal errors were formerly hidden by the broad catches. Fixed the fake once to explicitly return no geometry, retaining its refusing supply assertions and all behavior assertions; removed the now-redundant PendingScan override. The nine affected fixture tests plus all prior focused regressions pass: fix-expanded-focused.log, 91 passed. Required full checks are running again. The Android probe was prepared, rebuilt, reinstalled after F1–F3 and all five acceptance images refreshed; scan and text-layer captures inspected. The dedicated fixture server is stopped again. No extra agents, main merge, physical-device input, coverage, or mutations.

**2026-11-10T20:25:05Z**

Release verification after all review fixes and fixture correction passed: dart format --output=none --set-exit-if-changed lib test tool integration_test (392 files, 0 changed); flutter analyze lib test integration_test (no issues); flutter test --reporter expanded (2529 passed, 21 skipped, 0 failed, 1m43s); bash test/native/ocr_worker_test.sh (PASS). Exact logs: /tmp/bookfin-tb-22fu/release-{format,analyze,tests,native,status}.log. Combined focused reader regression run: 91 passed. F1, F2, F3 all resolved by lead with reproduced red tests; reviewer original verdicts remain changes-required, not misrepresented as a second pass. Review task node:delegated-task:command%3Amcp%3A0e2f6110-aef8-4394-8812-713ad72dc5a2%3Adelegate-task%3Aa7d8819c-4c10-4dd2-ba64-a40619686825 completed; exactly one fresh codex/gpt-6.1-sol xhigh reviewer was used, no other delegates. Latest Android prepare/build/install passed, acceptance screenshots refreshed after fixes, and fixture server stopped. Ready for parent integration, preserving cropped Original 2a73abc, Trim margins fd722db, geometry repair b901b6c, and main survey-test fix. No merges, pushes, ticket closures or PR publication performed.

**2026-11-10T20:31:40Z**

Parent integrated 422d22f with accepted Original crops, Trim margins and Nihil geometry repair. Resolved the viewport turn conflict by keeping turned:true and using widget.reflow for previous-page last-screen placement; retained both ticket histories. Inspected production diff and review resolutions F1-F3. Combined focused reader run: 105 passed. Required Nix checks: format passed, analyze no issues, full flutter test 2560 passed/21 skipped/0 failed in 1m46s; native OCR worker PASS. Logs /tmp/bookfin-word-integration-{focused,format,analyze,full,native}.log. No phone UI input or hardening performed. User acceptance of word view remains pending; planned follow-ups remain separate.
