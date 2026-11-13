---
id: t8-dqir
status: open
deps: []
links: [boo-f9xa, boo-s11s]
created: 2026-11-13T02:30:27Z
type: task
priority: 3
assignee: Alexis Purslane
parent: boo-fs0n
tags: [reader, pdf]
---
# Report the place of a reflowed PDF page once when its text begins with white space

Found during the second change of boo-f9xa on 2026-11-12. Nothing was run for this finding. It comes from a read of lib/reader/pdf_viewport.dart and of preparePdfPage in lib/reader/pdf.dart.

In the PDF text view, a turn to a page reports the place when the text arrives, as character 0 of the page. The layout of the text screen then names the place as the first reading character of the shown screen (_textPlace). The reading text drops white space at the start of the page text. So when the page text begins with white space, the two places differ in their character and their quote, and the layout reports the place a second time. Each report is one save and one synced record (boo-s11s). When the page text begins with a printed character, the two places are equal, and since boo-f9xa the layout reports nothing.

A jump to a place inside a page, such as a search result, also reports twice: first the place of the jump, then the start of the screen that holds it. That second report is a real change of the saved place, and this ticket does not ask to remove it.

A possible fix: when the text arrives for a place at the start of the page, name the place by the first reading character, as the first text screen does. Check first what resolveAddress does with a character that is not 0 in another text representation of the page.

## Acceptance Criteria

A test turns to a page in the text view whose text begins with white space and is ready. The session saves the place once.

