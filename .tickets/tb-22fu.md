---
id: tb-22fu
status: open
deps: [tb-xjfi]
links: [t6-1luw]
created: 2026-11-10T02:33:42Z
type: feature
priority: 1
assignee: Alexis Purslane
parent: boo-fval
---
# Show the word view in the PDF viewport: waiting, places, turns and failure

W6 of docs/plans/pdf-word-image-reflow.md (The text under the images: places; Waiting, turns, the scrub deck and the scrub bar). Wire PdfWordPages into PdfViewport. One waiting flag covers text, analysis, layout and the first bands, with the original page under the progress line. Places come from the first piece of the shown screen, and a place opens the screen that holds it. Turns follow open decision 2. A failed analysis or render shows the text view. The scrub deck keeps original pages. If decision 2 picks screens, the text view also cuts into whole-line screens. Until W7 lands, reflow shows the word view.

## Acceptance Criteria

Behavior tests, red first: while recognition runs the original page shows under the progress line and the first screen replaces it with no notice; the place of a screen is its first word and reopening shows the same word; a place from the text view opens on the screen that holds it, and the reverse; turns pass from the last screen to the next page's first screen and back to the previous page's last screen; the deck starts no recognition; a failed analysis shows the text view. Engine rule 1 holds: no sync file call and no CPU work on the UI isolate.

