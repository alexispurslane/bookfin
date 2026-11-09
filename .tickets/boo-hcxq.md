---
id: boo-hcxq
status: open
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

