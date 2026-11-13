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

