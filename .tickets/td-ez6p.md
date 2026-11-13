---
id: td-ez6p
status: open
deps: []
links: [boo-f9xa, boo-0hin]
created: 2026-11-13T01:51:14Z
type: bug
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
tags: [reader, pdf]
---
# Save the PDF page in the word view when no earlier word screen shows

Found during boo-f9xa on 2026-11-12. Nothing was run for this finding. It comes from a read of lib/reader/pdf_viewport.dart (_startWords) and lib/reader/pdf_word_view.dart.

In the word view, the viewport reports the place of a new page only when its first word screen shows, or when the page gives up and falls back to its text. While an earlier word screen stays on the display, that is the deliberate rule: the place does not advance past the screen that the person still sees.

Without an earlier word screen, the original image of the new page shows under the progress line while the layout pass and the bands are on their way. That happens when the book opens in the word view, after a change to the word view, and after a page that had no words. In that time the new page is on the screen and its place is not saved. If Android stops Bookfin then, the saved place is the page before. boo-f9xa fixed the same loss for the text view and for the fallback to the text.

A possible fix: _startWords reports the opening place at once when PdfWordScreens holds no screen to retain. The value is the place that the first word screen reports anyway.

## Acceptance Criteria

A test opens a page in the word view with no earlier word screen and holds its words open. The session's saved place is that page before the words show. The rule for a retained word screen still holds.


## Notes

**2026-11-13T02:30:15Z**

The second change of boo-f9xa fixed this on 2026-11-12. In lib/reader/pdf_viewport.dart, _startWords now asks for a late report of the place when PdfWordScreens holds no word screen (_words.screen.value == null). If the first word screen did not show within 50 ms, the viewport reports the place of the page, and the session saves it. The first word screen then reports the place again, and the text refines it. The rule for a retained word screen did not change: while an earlier word screen stays on the display, the place does not advance.

Tests: in test/reader/pdf_word_view_test.dart, 'a page that opens in the word view with no earlier word screen reports its place while its words are on their way' failed before the change and passes now. 'while an earlier word screen stays on the display, a page whose words are late does not report its place' holds the rule for a retained screen. It fails when the condition on the retained screen is removed. In test/reader/pdf_place_test.dart, 'a turn in the word view with no word screen to keep saves the page while its words are on their way' covers the acceptance criterion with a session and a restart. Only the orchestrator closes this ticket.
