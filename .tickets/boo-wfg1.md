---
id: boo-wfg1
status: in_progress
deps: []
links: []
created: 2026-11-10T20:42:55Z
type: bug
priority: 1
assignee: Alexis Purslane
parent: boo-fval
---
# Keep word-image pages visible until the next word screen is ready

User reports a brief flash of Original while turning to PDF word-image pages whose layout should already be cached. Trace and reproduce with held asynchronous rendering. PdfWordScreens.open currently resets showing=false on every source-page open, while PdfWordPages already retains its displayed screen until replacement pixels are ready; PdfWordView then draws the Original waiting widget. Fix that transition through the existing displayed-screen ownership. Saved geometry/layout does not imply saved rendered word-screen pixels; document actual cache lifetime rather than claiming disk-cached reflow images. Keep the last readable word screen during page replacement, with positions and interaction referring to the truly displayed content. Preserve cold-open behavior, legitimate no-geometry/content/operational fallback, internal Error propagation, crop/trim behavior and bounded image memory. Treat next-source-page pre-render t8-bnwn as separate unless necessary.

## Acceptance Criteria

Red-first behavior tests: a source-page turn and a return to a cached page never paint Original between readable word screens, including held renders; stale completions and rapid direction changes cannot replace newer content; displayed position does not advance to unseen content; true fallback and opening a word view without a previous screen remain correct. Inspect close/reopen and view-switch paths and report scope honestly. Required Nix checks and one fresh Sol xhigh read-only review, then fix findings. No Pixel UI input.


## Notes

**2026-11-10T21:07:30Z**

Implementation scope: keep the existing PdfWordPages.shown screen visible while a different target page or layout is pending. Target readiness remains PdfWordScreens.showing and still guards place reports and requested-page ownership. PdfWordView now subscribes to displayed content, not readiness. Opening a page and changing layout abandon stale replacements immediately. Actual fallback clears displayed word pixels and cancels pending renders. Touches on retained content do not mark an unseen target as touched. Pixel alignment follows the displayed screen settings. Band ownership is set before display notification, and reentrant cancellation prevents rendering ahead.

Meaningful red evidence in /tmp/bookfin-boo-wfg1: red-retention.log (source turn, cached return, size overlap hide the word widget); display-green-stale-red.log (abandoned same-source render replaces the retained screen during a different page geometry wait); fallback-red-scope.log (fallback resurrects old words on a later page); red-touch.log (touching retained words opens unseen target screen 0 instead of screen 3); green-fallback-touch-red-ratio.log (replacement uses old pixel alignment, 60.57142857142857 instead of whole pixel 61); red-display-publication.log (retaining during notification disposes the just-published pixels). Initial red-source.log was a test-double setup timeout, not meaningful red: the copy intentionally lacked native geometry. HeldWordPdf now delegates native geometry and attachments. The later failures above are behavior failures.

Preserved scope: source-page turns, cached returns, held renders, rapid direction changes and overlapping size changes retain actual readable words and do not publish unseen places. Existing same-source turns already retained their screen; regression coverage remains. Geometry, own-content and operational fallback remain legitimate. Switching to Original calls leave and disposes band images/plans; switching back has no retained word screen, so Original remains the legitimate waiting view. Recreating the viewport also has no band images. A same-book-object reopen reuses page analysis but makes new plans and pixels. This does not promise instant words after a real book close/reopen.

Cache lifetime: scanned layout records and recognition output are stored on disk; book profiles/crops are persisted separately. PdfBook keeps at most 16 reflow page records in memory for that book object. PdfWordPages keeps four profile-aware column futures per word-view lifetime, and pixels for at most two screens (displayed plus requested/ahead), bounded by the existing per-screen band plan. leave/dispose releases those images and creates/destroys that plan cache. Rendered word pixels are not persisted. No cache was broadened; t8-bnwn next-source pre-render remains separate.

Integration: lib/reader/pdf_word_view.dart overlaps tb-mfkk. Keep displayed screen data separate from _open target state; showing=false can coexist with visible retained words. Keep the screen-listenable builder and displayed-settings pixel origin when merging selection. lib/reader/word_pages.dart adds retainShown/clearShown and atomic notification order. No PdfViewport crop, trimMargins, 300ms jump wait, immediate turn crop, preview crop, six-times zoom, paired text/geometry, text representation, or internal Error policy changes. No device operation, coverage or mutation jobs.

**2026-11-10T21:15:22Z**

Required verification completed through the pinned Nix shell, one heavy command at a time. dart format --output=none --set-exit-if-changed lib test tool integration_test: exit 0, 394 files, zero changed (format-analyze-final.log). flutter analyze lib test integration_test: exit 0, no issues (same log). Its first run found only use_super_parameters in the new test helper; the constructor was corrected before final checks. flutter test --concurrency=2 --reporter expanded: exit 0, 2573 passed, 21 skipped, 4m12s (full-test.log). Both affected reader test files: exit 0, 62 passed (focused-final.log). git diff --check passes. Logs are under /tmp/bookfin-boo-wfg1. Flutter prints host warnings about missing iphoneos/iphonesimulator SDKs and available package updates; the mandatory checks still exit 0. No native code changed, so bash test/native/ocr_worker_test.sh is not required and was not run. No phone/emulator acceptance claimed; the parent installs and the user tests. No coverage or mutation jobs were run. Review is next; ticket remains in progress.
