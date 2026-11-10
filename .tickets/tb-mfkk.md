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
