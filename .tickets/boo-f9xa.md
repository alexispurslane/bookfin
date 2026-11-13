---
id: boo-f9xa
status: in_progress
deps: []
links: [boo-0hin, boo-p9s3, td-rbtc, td-ez6p]
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
