---
id: boo-f9xa
status: in_progress
deps: []
links: [boo-0hin, boo-p9s3, td-rbtc, td-ez6p, t8-dqir]
created: 2026-11-12T23:41:01Z
type: bug
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
tags: [survey-1112]
---
# Save the PDF page as the reading place as soon as the page shows

Found in the code survey of November 12 (main at f9f26500). Nothing was run for this finding. Status: confirmed. lib/reader/pdf_viewport.dart:288-337. In the text view, `_publish()` runs only after `book.text(page)` returns. On a scanned page that is full recognition, 3 to 10 seconds, while the original image of the page already shows. A kill in that time leaves the saved place one page behind, and a series of fast turns saves nothing until the text of the last page arrives. Publish the page-level place (`PdfAddress(page, 0)`) when the page shows and refine it when the text resolves. Add a test: turn, kill before recognition ends, reopen.


## Notes

**2026-11-13T03:07:13Z**

Continuation recovered the existing second fixer, task node:delegated-task:command%3Amcp%3Af0e68da9-9404-43ac-a9da-69e376960cf2%3Adelegate-task%3Ae1eccf25-e75a-489c-a2c8-3e497a1bf668, child thread:delegated-task:command%3Amcp%3Af0e68da9-9404-43ac-a9da-69e376960cf2%3Adelegate-task%3Ae1eccf25-e75a-489c-a2c8-3e497a1bf668. It already uses codex/gpt-6-astra reasoningEffort xhigh. No replacement writer was started. Await its completion delivery before integration. boo-0hin now depends on this ticket.

**2026-11-13T03:18:01Z**

Second Astra fixer completed at abc26b52ca9c3e72c2b0724b3a9f9bde39e4f099 on t3/fix-reader-undo-refinements, clean. Prerequisite commits a53a7de5 and 0f2e31dd. Reported required 100-file selection: 1330 passed, 21 skipped, no failures; changed-file analysis clean. Parent inspected the production corrections and launched fresh read-only review node:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-boo-f9xa-final-review-astra-20261112-1, child thread:delegated-task:command%3Amcp%3A1c08c61d-1551-4bdb-9409-d3433b5889af%3Adelegate-task%3Abookfin-boo-f9xa-final-review-astra-20261112-1, clientRequestId bookfin-boo-f9xa-final-review-astra-20261112-1, codex/gpt-6-astra reasoningEffort high. Do not integrate until review resolves material issues. Then run the full suite on main. Preserve newer dependency lines in boo-0hin and boo-s11s when integrating. td-ez6p is fixed by this branch and can close after integration verification. td-rbtc remains open, but its older note must be corrected: only waiting Undo is canceled by a newer request; normal jumps remain ordered.
**2026-11-13T01:54:50Z**

The PDF viewport now reports the place of a page as soon as the page shows, before its text arrives. In lib/reader/pdf_viewport.dart, _requestText publishes the place right after it asks for the text. That covers the text view, the Original view and the path where the word view gives up on a page. When the text resolves, the viewport reports the place again through a new callback, onRefinedAddress. The rule of the word view for a retained screen did not change.

ReaderSession has a new operation, refineAddress. A refinement is the same place under a better name. It saves the place like a page turn and records no move. The move that ended when the page showed takes the refined place, so a History row still shows the words of the place. The start of a visit takes it at both ends, so it still does not count as a move. A refinement for another page than the shown one changes nothing, and a refinement that names nothing new saves nothing. The session keeps the move that the last report ended in _landed, and checkInvariants covers it.

The move of a jump is now saved in one change set with the page-level place. So a stop during recognition keeps both the new page and the way back to the old place.

Existing test changed: "every place inside one reflowed page names the digest that came with its page text" in test/reader/pdf_viewport_test.dart now looks at the places from the first refinement on, because the first report of a page names no text.

Verification on 2026-11-12, through nix develop:
- flutter test test/reader/pdf_place_test.dart: 16 new tests pass. 11 of them failed before the change for the missing early report. The other 5 were written with refineAddress. A mutation of the rule that each one covers made each of them fail.
- flutter test of test/reader/pdf_*_test.dart, ocr_*_test.dart, session*_test.dart, reading_moves_test.dart, scrub_test.dart and 20 more test files that use PDF places: 612 passed, 1 skipped (pdf_open_benchmark_test.dart needs BOOKFIN_PDF_OPEN_BENCHMARK), 0 failed.
- dart analyze on the 11 changed Dart files: no issues.

Found work, filed as tickets: td-rbtc (a second PDF jump, Undo included, waits for the recognition of the page of the jump before it) and td-ez6p (the word view does not save the new page while its original image shows and no earlier word screen is retained).

**2026-11-13T02:31:59Z**

Second change, after review, on 2026-11-12. It keeps the order of the reports, the moves recorded and the two callbacks of the first change.

B1. The Undo offer of a jump shows when the jump has ended, not at the first report of its page. The move is still recorded and saved at the first report. ReaderSession._endMove ends the earlier offer there, and _offerUndo sets the new offer when the navigator call of the jump completes. A jump that waits behind another jump does not run when the person turns a page or asks for another jump in that time (_requests in ReaderSession). So a waiting Undo can not run late.

EZ (td-ez6p). In the word view with no word screen to keep, the page reports its place when its words are late.

D1. PdfWordScreens has a second callback, onRefinedPlace. When the text attaches to the word screen that shows, the screen reports its place through it, and the viewport passes it to onRefinedAddress. A screen that shows, also after a turn or a new layout, still reports through onPlace.

B3. The viewport reports the page-level place only when the text or the words are late: 50 ms after the page began to wait (_placeWait in lib/reader/pdf_viewport.dart). A page whose text arrives before that reports once, with the full place. The first text screen of a page reports nothing more when its place is the one that was reported. A turn in the text view to a page with ready text now makes one save. It made two before the first change and three after it.

B2. A second report of the same place that ends no move keeps the move that a refinement can still name.

D2. HistoryEvent.withEnds in lib/playback/records.dart copies a move with new ends. ReaderSession._nameEnds uses it.

Existing tests changed. In test/reader/pdf_place_test.dart, settle now lets 100 ms pass, 'after two fast turns' expects only the last page, and 'a jump to a scanned page saves its move' no longer expects the Undo offer during recognition. In test/reader/pdf_viewport_test.dart, 'every place inside one reflowed page names the digest that came with its page text' has the body of the base commit again, because a page with ready text gives no page-level report.

Verification on 2026-11-12, through nix develop:
- flutter test test/reader/pdf_place_test.dart test/playback/records_test.dart test/reader/pdf_word_view_test.dart: 76 passed (31, 1 and 44).
- flutter test of every test file under test/reader whose name starts with pdf_, ocr_, session, reading_, scrub or dock, of test/reader/records_test.dart and test/playback/records_test.dart, and of 17 more test files that use Undo, jumps, page turns or the PDF viewport: 618 passed, 1 skipped (pdf_open_benchmark_test.dart needs BOOKFIN_PDF_OPEN_BENCHMARK), 0 failed.
- dart analyze on the 10 changed or dependent Dart files: no issues. dart format: no changes.
- No device and no emulator was used.

Found work, filed as a ticket: t8-dqir (a page of the text view whose text begins with white space still reports its place twice). td-rbtc and td-ez6p have notes about this change.

**2026-11-13T03:11:34Z**

Applied the second review in the isolated t3/fix-reader-undo-refinements worktree. The two prior commits are a53a7de5 and 0f2e31dd here. Both cherry-picks were clean.

Finding 1. DocumentNavigator.reportPendingPlace() synchronously reports a shown place that still waits for its report. ReaderSession calls it at the start of flush(), before _clear() ends a visit or releases the navigator, and before failed() detaches the navigator. Account changes clear the old book before changing the account key. Disposal clears the book before setting _disposed. The PDF navigator leaves a retained word screen at its old place while the requested page waits. EpubPager reports places at once, so its implementation does nothing. The screen disposal path already calls flush() and closeView(). No widget lifecycle listener was added.

Two related tests found stale History starting points after a turn within the 50 ms wait. The session now collects the pending place before _jump captures its starting point and before _jumpTo captures the starting point for another edition. These tests check the store through a fresh session.

Finding 2. The request counter cancels only a waiting HistoryAction.undo. Ordinary jumps run in order. The comment distinguishes the request counter, the open-book token, and the move that waits for its destination. Both existing tests that cancel a waiting Undo still pass. The Undo offer still appears only after navigation finishes.

Finding 3. Every accepted place report assigns the move that it ends to _landed, including null when it ends no move. The PDF navigator suppresses repeated reports by the reported address and the shown layout and screen index. This keeps a turn between word screens whose incomplete addresses both name character zero. A refinement updates the remembered address and screen. The word-view refinement callback and HistoryEvent.withEnds stay intact.

The former test 'a second report of the same place keeps the move for the refinement' now uses a real viewport and a change of view. It is named 'a repeated view of the same place keeps the move for the refinement'. It still proves that the Opened entry gains the recognized words and stays a visit without a move. The existing jump test for a change of view keeps its outcome. The existing overlapping-size-changes test now waits for the restored screen instead of a repeated place report, and asserts that there is no repeated report.

Red evidence before each fix:
- Six early-end tests failed with saved page 1 instead of 2. They cover flush, close, screen removal, open, sign out, and edition removal. The disposal test then failed the same way. No fake time passed between the page turn and the end operation.
- The EPUB chapter-step test ended in section 1 instead of section 2. The consecutive-jump test recorded only Cedar instead of Birch followed by Cedar. The queued EPUB landing returned false.
- The PDF chapter-choice test recorded destinations [4, 2] instead of [4, 3, 2], newest first. The queued PDF landing returned false.
- The repeated-view test received two reports instead of one. The real-session word-view test changed the History destination from character 0 to character 232 after the person turned a word screen during recognition.
- The cross-edition jump and the jump within the same PDF each recorded page 1 instead of page 2 as the starting point.

Verification through the Nix dev shell:
- Early-end red run: 0 passed and 6 failed. Disposal red run: 0 passed and 1 failed. Early-end green run: 7 passed.
- The first queue run had 3 expected EPUB assertion failures and 2 load failures because the PDF landing fixture omitted its required chapter argument. That run is not the accepted red evidence. The corrected queue and repeat run had 0 passed and 6 assertion failures. The queue green run, including both waiting-Undo tests, passed 7 tests.
- The real-session word-view red run had 0 passed and 1 failed. The word-view and repeat green run passed 4 tests.
- The first complete run of pdf_place_test.dart, pdf_word_view_test.dart, and reading_moves_test.dart passed 129 tests and failed 1. The failure was 'overlapping size changes preserve the word that remained visible instead of a screen that never appeared'. Its wait for a repeated report timed out. The isolated rerun failed the same way. After changing the wait to the restored screen, the isolated test passed.
- The first required 100-file selection passed 1328 tests and skipped 21, with no failures. The cross-edition red test then failed and its green test passed. The second required selection passed 1329 tests and skipped 21, with no failures.
- The pending-jump red test failed. After its fix, all of pdf_place_test.dart and reading_moves_test.dart passed, 87 tests total.
- The required selection is every test file under test/reader whose name starts with pdf_, ocr_, session, reading_, scrub, dock, epub or kept, all of test/reader/epub, all of test/crossings, and all 11 test files that import timeline.dart. It also includes test/reader/screen_test.dart, test/reader/records_test.dart and test/playback/records_test.dart. It runs with --concurrency=2 and --reporter=json. The 21 skips are existing opt-in benchmarks and corpus tests.
- dart analyze on all 10 changed Dart files reports no issues. Its first pass reported one missing-braces style hint, which was fixed. dart format was applied. No device or emulator was used. No push or ticket closure was done.

A note on boo-0hin names the timer, the reported flag, the pending place and the last reported address and screen that must move with the navigator. That ticket was not started. td-rbtc and t8-dqir remain follow-ups. All three findings were applied. No product decision is pending.

Final verification after both pending-start fixes: the required 100-file selection passed 1330 tests, skipped 21, and failed none. dart analyze on the 10 changed Dart files reported no issues. The final test command ran through nix develop with --concurrency=2 and --reporter=json.


## Final displayed-page correction, 2026-11-12

The final Astra review found F1: the 50 ms timer and reportPendingPlace could persist a requested page while its raster and recognition were both pending. Reproduced it with three real-session tests (timer, flush, contents jump): all reopened page 2 instead of the still-last-shown page 1. A fourth test reproduced ready text being saved before its first frame. Red logs: /tmp/boo-f9xa-unseen-red.log and /tmp/boo-f9xa-text-frame-red.log.

The existing navigator now makes the requested page eligible for reporting only after its original image or reading text enters a completed frame. Word screens use their existing displayed-screen notification. The 50 ms allowance starts at that frame. Both delayed publication and synchronous collection respect the same visibility state. Navigation also waits for that frame before completing, so a ready-text jump cannot leave its queue before its History destination has reported. Abandonment, disposal, and draw failure release the frame wait without reporting unseen content. Recognition still delays navigation completion as recorded in td-rbtc; this correction does not implement that follow-up.

The three held-render tests prove that no original image or reading-text widget appears before release, read the saved records through a fresh session, then release the raster while keeping recognition pending and prove that the original image appears and page 2 is saved. The contents case checks both History endpoints. Existing early-end tests now wait for native image decoding and confirm the displayed image, without advancing fake time between its appearance and flush/close/pop/open/account change/removal/disposal. Tests that await page navigation now pump the frame it needs. OCR tests retain saved bookmarks while an unshown initial page has no visible address, then assert the address after content appears.

Verification through nix develop:
- Four new regressions passed after the visibility correction.
- Initial four-file reader run: 70 passed, 35 failed. The failures exposed tests that assumed appearance from a completed raster and queued navigation completing before the frame.
- Next three-file run: 44 passed, 16 failed because the shared test wait still accepted the previous frame's content. Corrected it to pump the requested frame before waiting for content.
- Complete pdf_place_test.dart: 47 passed, no failures.
- 100-file selection: 1323 passed and 21 skipped before interruption; six OCR screen assertions/waits failed, and an OCR navigation test waited without pumping its required frame. Stopped only the owned test runner (PID 45623). Its interruption adds two error events; this run is not a passing suite. Log: /tmp/boo-f9xa-shown-required.jsonl.
- After correcting those test waits, both OCR files passed all 11 tests: /tmp/boo-f9xa-shown-ocr.log.
- dart analyze on all eight changed Dart files: no issues. Formatting and git diff --check pass.
- Parent's full suite on integrated main remains the completion gate. No device acceptance, coverage, mutation run, push, or ticket closure is claimed here.

F1 is resolved by the reproduced behavior and checks above. The planned PDF pager extraction remains boo-0hin; its notes include ownership of visibility and the frame wait. The td-rbtc note now correctly distinguishes superseded queued Undo from ordinary queued jumps.
