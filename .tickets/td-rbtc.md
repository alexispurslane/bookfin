---
id: td-rbtc
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
# Let a second PDF jump start before the text of the first jump's page arrives

Found during boo-f9xa on 2026-11-12. ReaderSession._jump runs the jumps of one book one after another, and each jump waits for the navigator's display to complete. In lib/reader/pdf_viewport.dart, _load awaits _requestText, and _requestText awaits book.text(page). On a scanned page in the text view that is full recognition, which takes 3 to 10 seconds. So a second jump in that time does nothing until the recognition of the first jump's page ends. This applies to Undo, a contents entry, the scrub bar, a bookmark and a History entry. A page turn is not a jump and does not wait.

Since boo-f9xa the move of a jump is saved when its page shows, so the Undo offer shows while the page is recognized. A tap on Undo in that time waits for the recognition too.

Observed in a test of boo-f9xa before it was rewritten: a jump to page 3 whose recognition was held open, then undoMove, left the place at page 3.

A possible fix: the navigator's display completes when the page shows and its place is reported, not when its text arrives. The word view has the same wait in _startWords, which awaits the first word screen. The session-owned PDF pager of boo-0hin can own this decision.

## Acceptance Criteria

A test holds the recognition of a scanned page open, jumps to it in the text view, and then asks for Undo. The reader shows the place before the jump without waiting for the recognition.


## Notes

**2026-11-13T02:30:15Z**

The second change of boo-f9xa, on 2026-11-12, did not fix this ticket. It removed two results of the wait that this ticket describes.

1. The Undo offer of a jump now shows when the jump has ended, not when its page first reports its place. ReaderSession._endMove ends the earlier offer when it records the move of a jump, and _offerUndo sets the new offer when the navigator call of the jump completes. So the Undo pill no longer shows during the recognition of the page of the jump, where a tap did nothing and then ran late. The move is still recorded and saved at the first report.

2. Only a queued Undo gives up when the person turns a page or asks for another jump while it waits. ReaderSession counts these requests in _requests. Ordinary queued jumps retain their order. Before, a waiting Undo ran after the page turn that ended the jump in front of it, and took the person back.

What stays for this ticket: a jump still waits for the text of the page of the jump before it. When the navigator's display completes at the first report of the place, the Undo offer can show at that time again, because _offerUndo already runs at the end of the navigator call. The rule that drops only a superseded queued Undo can stay as it is.
