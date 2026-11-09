---
id: boo-hcxq
status: in_progress
deps: []
links: []
created: 2026-11-09T17:56:11Z
type: feature
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
---
# Turn reader pages by swiping, and enter full screen by tapping the middle of the page

Requested by the user on 2026-11-09.

1. In every reader view (PDF original, PDF reflow, EPUB and MOBI), a horizontal swipe turns the page, whether the bottom bar is open or not. Today the PDF reader needs the bottom bar's arrows.
2. A tap in the middle of the page enters full screen, and another tap there leaves it. Remove the full screen button in the top bar (Icons.fullscreen_rounded in lib/reader/screen.dart).
3. Full screen shows only the page: no top bar, no bottom bar, no buttons, no labels, and Android's system bars hidden (immersive).
4. One gesture model serves all reader views (AGENTS.md UI rule 2). Keep the reader's other gestures (text selection, links, footnotes, edge taps if they exist) working, and keep TalkBack actions for turning pages and for showing the controls.


## Added by the user, 2026-11-09 12:58

The user said: "Additionally, the top and bottom bars should lay over the unchanged page, instead of moving the page around. And really, there shouldn't be any top bar at all to the book view."

5. Remove the reader's top bar in every reader view (PDF, EPUB and MOBI). The person leaves the book with Android's back gesture or button. The bottom bar keeps its contents.
6. The bottom bar, and every other control that shows, lies over the page as glass. Showing or hiding the controls, and entering or leaving full screen, never moves, resizes, reflows or paginates the page again. A test makes sure that the page's layout size and the shown page stay the same when the controls show or hide. The page area keeps the same size whether Android's system bars show or hide.
