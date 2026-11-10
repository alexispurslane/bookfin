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
# Show the word view in the PDF viewport: waiting for words and text, places, turns and failure

W6 of docs/plans/pdf-word-image-reflow.md (The text under the images; Waiting, turns, the scrub deck and the scrub bar). Wire PdfWordPages into PdfViewport. One waiting flag covers the text layer text or the layout record, the analysis, the layout and the first bands, with the original page under the progress line. On a scanned page the words show after the layout pass, and the progress line stays until the text attaches. Places come from the first piece with a range on the shown screen, or the page itself before the text. A saved place inside a page without text is kept, not overwritten; when the text attaches and the person has not turned or touched, the screen that holds it shows. Turns follow decision 2 of 2026-11-10: a swipe shows the next whole-line screen, a swipe past a page's last screen shows the next page's first screen, back from a first screen shows the previous page's last screen, and a vertical drag does nothing. Failures follow the doc. The scrub deck keeps original pages. Until W7 lands, reflow shows the word view.

## Acceptance Criteria

Behavior tests, red first: on a scanned page the first word screen shows before recognition ends and the progress line stays until the text attaches, with no change of screen; before the text, a saved place inside the page opens the first screen and stays saved, and after the text it opens its screen if the person did not move; the place of a screen is its first word and reopening shows the same word; a place from the text view opens on the screen that holds it, and the reverse; turns pass between pages' first and last screens; a vertical drag changes nothing; the deck starts no layout pass and no recognition; a failed layout pass or analysis falls back as the doc says. Engine rule 1 holds.

## Notes

**2026-11-10T17:04:29Z**

From tb-xjfi: PdfWordPages(book) is the data source, one per viewport. column(page, settings) gives the WordColumn (column and band plans) or null without word geometry. show(page, settings, screen, forward:) shows a screen in the shown listenable once its bands are ready, keeps the old screen until then, and completes after the next screen is rendered ahead. WordScreenView(screen: pages.shown) draws it with the theme's tints and fills its constraints. Place it at a whole device pixel (for example a left margin of round(20 * ratio) / ratio), or level words lose their one-to-one pixels. WordSettings carries the column width, text size, screen height and device pixel ratio. The sprites of a screen are placed from the screen's top (column.screenTop(screen)) and the column's left edge, so the view draws a screen at its own origin.
